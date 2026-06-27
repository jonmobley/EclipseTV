// RemoteAlbumStore.swift
import Foundation
import Combine
import os.log

/// On-disk location for downloaded album media. Kept separate from `ImageStorage`'s
/// `Caches/Media` so album files never mix with iPhone-sent items and are not subject
/// to the local library's delete-on-remove logic. Each album gets its own subdirectory
/// (`Album/<albumId>/…`) so albums can be pruned independently. Album files purged by
/// tvOS are simply re-downloaded on the next sync.
enum AlbumStorage {
    static let directory: URL = {
        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("Album", isDirectory: true)
    }()

    @discardableResult
    static func ensureRootDirectory() -> Bool {
        (try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)) != nil
    }

    /// Filesystem-safe directory for a single album.
    static func directory(forAlbumId albumId: String) -> URL {
        directory.appendingPathComponent(sanitize(albumId), isDirectory: true)
    }

    @discardableResult
    static func ensureDirectory(forAlbumId albumId: String) -> Bool {
        (try? FileManager.default.createDirectory(at: directory(forAlbumId: albumId),
                                                  withIntermediateDirectories: true)) != nil
    }

    static func path(forAlbumId albumId: String, fileName: String) -> String {
        directory(forAlbumId: albumId).appendingPathComponent(fileName).path
    }

    /// Reduces an arbitrary id to a safe single path component.
    static func sanitize(_ raw: String) -> String {
        let unsafe = CharacterSet(charactersIn: "/\\?%*|\"<>: ")
        return raw.components(separatedBy: unsafe).joined(separator: "_")
    }
}

/// A downloaded album item, resolved to a local file under its album's directory.
struct AlbumItem: Codable, Equatable {
    /// Stable manifest id (cross-sync identity).
    let id: String
    /// Id of the album this item belongs to (scopes its on-disk location).
    let albumId: String
    /// Display name.
    let name: String
    /// Image vs. video.
    let isVideo: Bool
    /// Source URL the file was downloaded from.
    let remoteURL: String
    /// Content fingerprint that produced the current local file (drives re-download).
    let checksum: String?
    /// File name within the album's directory.
    let localFileName: String

    /// Absolute path to the downloaded file.
    var localPath: String { AlbumStorage.path(forAlbumId: albumId, fileName: localFileName) }

    /// Whether the backing file is present on disk.
    var fileExists: Bool { FileManager.default.fileExists(atPath: localPath) }
}

/// A downloaded album: identity, display name, and its resolved items.
struct Album: Codable, Equatable {
    let id: String
    let name: String
    let items: [AlbumItem]
}

/// Single source of truth for the read-only albums mirrored on the Apple TV from an
/// account's online manifest.
///
/// Holds the configured account code plus the list of successfully downloaded albums,
/// and persists both to `UserDefaults` so they survive relaunches. Mutations to the
/// actual remote contents are performed by `RemoteAlbumSync`, which calls
/// `applyAlbums(_:)` once a sync completes.
final class RemoteAlbumStore: ObservableObject {

    // MARK: - Singleton

    static let shared = RemoteAlbumStore()

    // MARK: - Published State

    /// Downloaded albums (in manifest order) shown as the grid's album sections.
    @Published private(set) var albums: [Album] = []

    // MARK: - Configuration

    /// The configured account code, or `nil` when no account is set up. The manifest
    /// URL is composed from this code via `AlbumConfig`.
    private(set) var accountCode: String?
    /// Timestamp of the last successful sync.
    private(set) var lastSyncDate: Date?

    // MARK: - Private

    private let defaults: UserDefaults
    private let logger = Logger(subsystem: "com.eclipsetv.app", category: "RemoteAlbumStore")

    private let albumsKey = "EclipseTV.album.albums"
    private let codeKey = "EclipseTV.album.code"
    private let lastSyncKey = "EclipseTV.album.lastSync"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        AlbumStorage.ensureRootDirectory()
        loadFromStorage()
    }

    // MARK: - Public Interface

    /// Albums that actually have downloaded items, in manifest order. These back the
    /// grid's album sections (empty albums are hidden).
    var displayAlbums: [Album] { albums.filter { !$0.items.isEmpty } }

    /// Number of album sections shown in the grid.
    var albumSectionCount: Int { displayAlbums.count }

    /// Total downloaded items across all albums.
    var totalItemCount: Int { albums.reduce(0) { $0 + $1.items.count } }

    var isEmpty: Bool { totalItemCount == 0 }
    var hasAlbumConfigured: Bool { (accountCode?.isEmpty == false) }

    /// The display album at a section-relative index (0-based over `displayAlbums`).
    func album(at index: Int) -> Album? {
        let albums = displayAlbums
        guard index >= 0 && index < albums.count else { return nil }
        return albums[index]
    }

    /// Display index (0-based over `displayAlbums`) of the album with `id`, if present.
    func displayAlbumIndex(forId id: String) -> Int? {
        displayAlbums.firstIndex { $0.id == id }
    }

    /// Index of the item with `itemId` within the display album at `albumIndex`, if present.
    func itemIndex(inAlbumIndex albumIndex: Int, forId itemId: String) -> Int? {
        album(at: albumIndex)?.items.firstIndex { $0.id == itemId }
    }

    /// The item at `itemIndex` within the display album at `albumIndex`.
    func item(albumIndex: Int, itemIndex: Int) -> AlbumItem? {
        guard let album = album(at: albumIndex),
              itemIndex >= 0 && itemIndex < album.items.count else { return nil }
        return album.items[itemIndex]
    }

    /// Local file path for the item at `itemIndex` within display album `albumIndex`.
    func path(albumIndex: Int, itemIndex: Int) -> String? {
        item(albumIndex: albumIndex, itemIndex: itemIndex)?.localPath
    }

    /// Number of items in the display album at `albumIndex`.
    func itemCount(albumIndex: Int) -> Int {
        album(at: albumIndex)?.items.count ?? 0
    }

    /// Sets (or replaces) the account code and persists it. The raw input is normalized
    /// to digits; an invalid code is rejected. Does not fetch; callers should kick off
    /// `RemoteAlbumSync.shared.sync()` afterwards.
    @discardableResult
    func setAccountCode(_ rawCode: String) -> Bool {
        let normalized = AlbumConfig.normalize(rawCode)
        guard AlbumConfig.isValidCode(normalized) else {
            logger.error("Rejected invalid account code")
            return false
        }
        accountCode = normalized
        defaults.set(normalized, forKey: codeKey)
        logger.info("Account code set: \(normalized, privacy: .public)")
        return true
    }

    /// The currently configured manifest URL, composed from the account code, if valid.
    func manifestURL() -> URL? {
        guard let accountCode else { return nil }
        return AlbumConfig.manifestURL(forCode: accountCode)
    }

    /// Replaces the album contents after a sync and persists the new state. Removes any
    /// downloaded files (and whole album directories) no longer referenced.
    @MainActor
    func applyAlbums(_ newAlbums: [Album]) {
        pruneOrphanedFiles(keeping: newAlbums)
        albums = newAlbums
        lastSyncDate = Date()
        persistAlbums()
        defaults.set(lastSyncDate, forKey: lastSyncKey)
        logger.info("Applied \(newAlbums.count) album(s), \(self.totalItemCount) item(s) total")
    }

    /// Clears everything: config, persisted albums, and downloaded files.
    @MainActor
    func clearAlbum() {
        pruneOrphanedFiles(keeping: [])
        albums = []
        accountCode = nil
        lastSyncDate = nil
        defaults.removeObject(forKey: albumsKey)
        defaults.removeObject(forKey: codeKey)
        defaults.removeObject(forKey: lastSyncKey)
        logger.info("Albums cleared")
    }

    // MARK: - Storage

    private func loadFromStorage() {
        accountCode = defaults.string(forKey: codeKey)
        lastSyncDate = defaults.object(forKey: lastSyncKey) as? Date

        guard let data = defaults.data(forKey: albumsKey),
              let decoded = try? JSONDecoder().decode([Album].self, from: data) else {
            return
        }

        // Keep only items whose downloaded file is still present; anything purged by
        // tvOS is dropped so the next sync re-downloads it.
        var changed = false
        let present: [Album] = decoded.map { album in
            let items = album.items.filter { $0.fileExists }
            if items.count != album.items.count { changed = true }
            return Album(id: album.id, name: album.name, items: items)
        }
        albums = present
        if changed {
            persistAlbums()
            logger.info("Dropped purged album file(s) on load")
        }
    }

    private func persistAlbums() {
        if let data = try? JSONEncoder().encode(albums) {
            defaults.set(data, forKey: albumsKey)
        }
    }

    /// Deletes album directories and files not referenced by `keeping`.
    private func pruneOrphanedFiles(keeping newAlbums: [Album]) {
        let fm = FileManager.default
        let keepDirNames = Set(newAlbums.map { AlbumStorage.sanitize($0.id) })

        guard let albumDirs = try? fm.contentsOfDirectory(at: AlbumStorage.directory,
                                                           includingPropertiesForKeys: nil) else { return }
        for dir in albumDirs {
            let dirName = dir.lastPathComponent
            guard keepDirNames.contains(dirName) else {
                try? fm.removeItem(at: dir)
                continue
            }
            // Within a kept album, drop files no longer referenced.
            let keepFiles = Set(newAlbums
                .first { AlbumStorage.sanitize($0.id) == dirName }?
                .items.map { $0.localFileName } ?? [])
            if let files = try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) {
                for file in files where !keepFiles.contains(file.lastPathComponent) {
                    try? fm.removeItem(at: file)
                }
            }
        }
    }
}
