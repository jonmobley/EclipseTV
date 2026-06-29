// RemoteAlbumSync.swift
import Foundation
import os.log

/// Fetches an account's album manifest over HTTPS, downloads new/changed media into
/// per-album directories under `AlbumStorage.directory`, and hands the resulting albums
/// to `RemoteAlbumStore`.
///
/// This is the Apple TV's only outbound internet networking. Sync is idempotent and
/// safe to call repeatedly (on launch, when an account is configured, on a manual
/// refresh, or when the scene becomes active); concurrent calls are coalesced.
final class RemoteAlbumSync {

    // MARK: - Singleton

    static let shared = RemoteAlbumSync()

    // MARK: - Errors

    enum SyncError: LocalizedError {
        case notConfigured
        case invalidURL
        /// HTTP 400 — the account code was missing or malformed.
        case invalidCode
        /// HTTP 404 — the account code is unknown to the server.
        case unknownCode
        case badResponse(Int)
        case decodeFailed

        var errorDescription: String? {
            switch self {
            case .notConfigured: return "No account configured"
            case .invalidURL: return "Invalid account code"
            case .invalidCode: return "That account code looks invalid"
            case .unknownCode: return "No account found for that code"
            case .badResponse(let status): return "Server error (\(status))"
            case .decodeFailed: return "Couldn't read the album data"
            }
        }

        /// Whether the error means the code itself is wrong (so it shouldn't be kept),
        /// as opposed to a transient/network/server issue worth retrying with the same code.
        var isBadCode: Bool {
            switch self {
            case .invalidURL, .invalidCode, .unknownCode: return true
            case .notConfigured, .badResponse, .decodeFailed: return false
            }
        }
    }

    // MARK: - Private

    private let store = RemoteAlbumStore.shared
    private let session: URLSession
    private let logger = Logger(subsystem: "com.eclipsetv.app", category: "RemoteAlbumSync")
    private var isSyncing = false

    init(session: URLSession = .shared) {
        self.session = session
    }

    // MARK: - Public Interface

    /// Performs a full sync against the configured account's manifest URL. Returns the
    /// number of items now downloaded across all albums, or throws if the account is
    /// unconfigured or unreachable.
    @discardableResult
    func sync() async throws -> Int {
        // Coalesce overlapping syncs: a second caller during an in-flight sync is a no-op.
        if isSyncing {
            logger.debug("Sync already in progress; skipping")
            return store.totalItemCount
        }
        isSyncing = true
        defer { isSyncing = false }

        guard store.hasAlbumConfigured else { throw SyncError.notConfigured }
        guard let url = store.manifestURL() else { throw SyncError.invalidURL }

        logger.info("Starting account sync from \(url.absoluteString, privacy: .public)")
        let manifest = try await fetchManifest(from: url)
        return try await apply(manifest: manifest)
    }

    /// Loads the built-in demo albums (no hosting or code entry required) by downloading
    /// their bundled-in remote sample media through the same pipeline. Returns the item
    /// count across the demo albums.
    @discardableResult
    func loadDemo() async throws -> Int {
        if isSyncing {
            logger.debug("Sync already in progress; skipping demo load")
            return store.totalItemCount
        }
        isSyncing = true
        defer { isSyncing = false }

        logger.info("Loading built-in demo albums")
        return try await apply(manifest: DemoAlbum.manifest)
    }

    /// Diffs `manifest` against the stored albums, downloads new/changed media, and
    /// commits the result. Per-item failures are logged and skipped so a single bad URL
    /// doesn't abort the whole sync.
    @discardableResult
    private func apply(manifest: AlbumManifest) async throws -> Int {
        // Item ids are globally unique, so a flat lookup is enough for checksum reuse.
        let existingById = Dictionary(existingItems().map { ($0.id, $0) },
                                      uniquingKeysWith: { first, _ in first })

        var resolvedAlbums: [Album] = []
        for albumEntry in manifest.albums {
            var resolvedItems: [AlbumItem] = []
            for entry in albumEntry.items {
                do {
                    if let item = try await resolve(entry,
                                                    albumId: albumEntry.id,
                                                    existing: existingById[entry.id]) {
                        resolvedItems.append(item)
                    }
                } catch {
                    logger.error("Skipping item \(entry.id, privacy: .public): \(error.localizedDescription, privacy: .public)")
                }
            }
            resolvedAlbums.append(Album(id: albumEntry.id,
                                        name: albumEntry.resolvedName,
                                        items: resolvedItems))
        }

        let finalAlbums = resolvedAlbums
        await store.applyAlbums(finalAlbums)
        let total = finalAlbums.reduce(0) { $0 + $1.items.count }
        logger.info("Account sync complete: \(finalAlbums.count) album(s), \(total) item(s)")
        return total
    }

    // MARK: - Manifest

    private func fetchManifest(from url: URL) async throws -> AlbumManifest {
        var request = URLRequest(url: url)
        request.cachePolicy = .reloadIgnoringLocalCacheData
        let (data, response) = try await session.data(for: request)
        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            switch http.statusCode {
            case 400: throw SyncError.invalidCode
            case 404: throw SyncError.unknownCode
            default: throw SyncError.badResponse(http.statusCode)
            }
        }
        do {
            return try JSONDecoder().decode(AlbumManifest.self, from: data)
        } catch {
            logger.error("Manifest decode failed: \(error.localizedDescription, privacy: .public)")
            throw SyncError.decodeFailed
        }
    }

    private func existingItems() -> [AlbumItem] {
        store.albums.flatMap { $0.items }
    }

    // MARK: - Per-item resolution

    /// Reuses the existing local file when the checksum matches and the file is present;
    /// otherwise downloads the entry into the album's directory.
    private func resolve(_ entry: AlbumManifestItem,
                         albumId: String,
                         existing: AlbumItem?) async throws -> AlbumItem? {
        guard let remoteURL = entry.remoteURL else { return nil }

        if let existing,
           existing.checksum == entry.checksum,
           existing.checksum != nil,
           existing.albumId == albumId,
           existing.fileExists {
            // Unchanged content with a stable checksum: keep the current file, but refresh
            // metadata (name/type) from the manifest. Re-fetch the thumbnail only if it's
            // newly offered or its prior download didn't land.
            let thumbnailFileName = await resolveThumbnail(for: entry,
                                                           albumId: albumId,
                                                           existing: existing)
            return AlbumItem(id: entry.id,
                             albumId: albumId,
                             name: entry.resolvedName,
                             isVideo: entry.isVideo,
                             remoteURL: entry.url,
                             checksum: entry.checksum,
                             localFileName: existing.localFileName,
                             thumbnailFileName: thumbnailFileName)
        }

        let fileName = localFileName(for: entry)
        let destination = URL(fileURLWithPath: AlbumStorage.path(forAlbumId: albumId, fileName: fileName))
        try await download(from: remoteURL, to: destination, albumId: albumId)

        let thumbnailFileName = await resolveThumbnail(for: entry, albumId: albumId, existing: nil)
        return AlbumItem(id: entry.id,
                         albumId: albumId,
                         name: entry.resolvedName,
                         isVideo: entry.isVideo,
                         remoteURL: entry.url,
                         checksum: entry.checksum,
                         localFileName: fileName,
                         thumbnailFileName: thumbnailFileName)
    }

    /// Downloads the server-provided thumbnail (`thumbnailUrl`) into the album directory
    /// so the grid can show it without generating one from the full media. Best-effort:
    /// a failure returns `nil` and the TV falls back to local thumbnail generation. Reuses
    /// an already-downloaded thumbnail when present.
    private func resolveThumbnail(for entry: AlbumManifestItem,
                                  albumId: String,
                                  existing: AlbumItem?) async -> String? {
        guard let thumbString = entry.thumbnailUrl,
              let thumbURL = URL(string: thumbString) else { return nil }

        let fileName = thumbnailFileName(for: entry, thumbnailURL: thumbURL)

        // Reuse a still-present thumbnail from a prior sync (keyed by the same file name).
        if let existing, existing.thumbnailFileName == fileName,
           FileManager.default.fileExists(atPath: AlbumStorage.path(forAlbumId: albumId, fileName: fileName)) {
            return fileName
        }

        let destination = URL(fileURLWithPath: AlbumStorage.path(forAlbumId: albumId, fileName: fileName))
        do {
            try await download(from: thumbURL, to: destination, albumId: albumId)
            return fileName
        } catch {
            logger.error("Thumbnail download failed for \(entry.id, privacy: .public): \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    private func download(from url: URL, to destination: URL, albumId: String) async throws {
        AlbumStorage.ensureDirectory(forAlbumId: albumId)
        let (tempURL, response) = try await session.download(from: url)
        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            throw SyncError.badResponse(http.statusCode)
        }
        let fm = FileManager.default
        if fm.fileExists(atPath: destination.path) {
            try? fm.removeItem(at: destination)
        }
        try fm.moveItem(at: tempURL, to: destination)
    }

    /// Builds a stable, filesystem-safe filename for an entry, preserving a sensible
    /// extension derived from the URL (falling back to the declared media type).
    private func localFileName(for entry: AlbumManifestItem) -> String {
        let safeStem = AlbumStorage.sanitize(entry.id)
        var ext = entry.remoteURL?.pathExtension ?? ""
        if ext.isEmpty {
            ext = entry.isVideo ? "mp4" : "jpg"
        }
        return "\(safeStem).\(ext)"
    }

    /// Filename for an entry's server thumbnail, distinct from its media file so the two
    /// can coexist in the album directory. The extension follows the thumbnail URL,
    /// defaulting to `jpg`.
    private func thumbnailFileName(for entry: AlbumManifestItem, thumbnailURL: URL) -> String {
        let safeStem = AlbumStorage.sanitize(entry.id)
        var ext = thumbnailURL.pathExtension
        if ext.isEmpty { ext = "jpg" }
        return "\(safeStem)_thumb.\(ext)"
    }
}
