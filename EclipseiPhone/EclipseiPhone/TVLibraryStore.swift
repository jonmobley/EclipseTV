// TVLibraryStore.swift
import UIKit
import os.log

/// Receives updates as the companion's read-only mirror of the Apple TV library.
protocol TVLibraryStoreDelegate: AnyObject {
    func libraryStoreDidUpdateItems(_ store: TVLibraryStore)
    func libraryStoreDidUpdateCurrent(_ store: TVLibraryStore)
    func libraryStore(_ store: TVLibraryStore, didUpdateThumbnailFor id: String)
    func libraryStoreDidChangeConnection(_ store: TVLibraryStore)
    /// The live video's playback state (play/pause/position/duration) changed.
    func libraryStoreDidUpdatePlayback(_ store: TVLibraryStore)
}

/// Live playback state mirrored from the Apple TV for the currently playing video.
struct PlaybackState: Equatable {
    var itemId: String?
    var isPlaying: Bool = false
    var currentTime: Double = 0
    var duration: Double = 0
}

/// Read-only mirror of the Apple TV library, populated from messages received over
/// the MultipeerConnectivity link and cached on disk so the last-synced library is
/// available even when the Apple TV is disconnected. The Apple TV remains the single
/// source of truth; this only reflects it for display in the companion grid.
///
/// State is namespaced per Apple TV (keyed by the device's `MCPeerID.displayName`)
/// so a phone paired with several Apple TVs keeps each library separate. The
/// "active" TV is whichever one the user is currently viewing; persistence and
/// thumbnails are scoped to it.
@MainActor
final class TVLibraryStore {

    /// Shared instance written by `iPhoneConnectionManager` and read by the grid.
    static let shared = TVLibraryStore()

    // MARK: - State

    private(set) var items: [LibraryItemDTO] = []
    private(set) var currentId: String?

    /// The Apple TV whose library is currently being shown, or nil if none has ever
    /// been selected. Used to namespace all persisted state.
    private(set) var activeTVName: String?

    /// Whether we are currently connected to the Apple TV. Not persisted.
    private(set) var isOnline = false

    /// Live playback state for the currently playing video on the Apple TV. Not persisted.
    private(set) var playback = PlaybackState()

    private var thumbnails: [String: UIImage] = [:]

    weak var delegate: TVLibraryStoreDelegate?

    var isEmpty: Bool { items.isEmpty }

    // MARK: - Persistence Config

    /// Prefixes for the per-TV UserDefaults keys; the active TV's hash is appended.
    private let itemsKeyPrefix = "EclipseTV.companion.items."
    private let currentIdKeyPrefix = "EclipseTV.companion.currentId."
    private let activeTVNameKey = "EclipseTV.companion.activeTVName"

    /// Root of the per-TV thumbnail caches; each TV gets a `<hash>` subdirectory.
    private let baseThumbnailDirectory: URL
    private let logger = Logger(subsystem: "com.eclipseapp.ios", category: "TVLibraryStore")

    private init() {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        baseThumbnailDirectory = caches.appendingPathComponent("TVLibraryThumbnails", isDirectory: true)
        try? FileManager.default.createDirectory(at: baseThumbnailDirectory, withIntermediateDirectories: true)

        // Restore the last-viewed TV so the cached library shows on a cold launch while
        // offline. Legacy single-bucket caches (pre per-TV) are ignored; they re-sync
        // automatically on the next connect.
        if let name = UserDefaults.standard.string(forKey: activeTVNameKey) {
            activeTVName = name
            ensureThumbnailDirectory()
            loadPersistedManifest()
        }
    }

    // MARK: - Active TV Selection

    /// Switches the active library to `name`, loading that TV's persisted manifest and
    /// thumbnails. Records the TV in the registry so it appears in the header dropdown
    /// even when later offline.
    func setActiveTV(_ name: String) {
        KnownTVRegistry.shared.remember(name: name)

        guard name != activeTVName else { return }
        activeTVName = name
        UserDefaults.standard.set(name, forKey: activeTVNameKey)

        // Drop the previous TV's in-memory state and load the new one's cache.
        thumbnails = [:]
        ensureThumbnailDirectory()
        loadPersistedManifest()

        delegate?.libraryStoreDidUpdateItems(self)
        delegate?.libraryStoreDidUpdateCurrent(self)
    }

    // MARK: - Reads

    func thumbnail(for id: String) -> UIImage? {
        if let cached = thumbnails[id] { return cached }
        // Fall back to the on-disk cache (e.g. after a relaunch while offline).
        guard let url = thumbnailFileURL(for: id) else { return nil }
        if let image = UIImage(contentsOfFile: url.path) {
            thumbnails[id] = image
            return image
        }
        return nil
    }

    func item(at index: Int) -> LibraryItemDTO? {
        guard index >= 0 && index < items.count else { return nil }
        return items[index]
    }

    // MARK: - Connection State

    func setOnline(_ online: Bool) {
        guard online != isOnline else { return }
        isOnline = online
        // Playback state is only meaningful while connected; clear it when going offline
        // so the companion's scrubber doesn't appear to keep playing.
        if !online, playback != PlaybackState() {
            playback = PlaybackState()
            delegate?.libraryStoreDidUpdatePlayback(self)
        }
        delegate?.libraryStoreDidChangeConnection(self)
    }

    // MARK: - Updates (from the connection manager)

    /// Replaces the full manifest and persists it. Prunes cached thumbnails (memory and
    /// disk) for items that are no longer present.
    func updateManifest(items: [LibraryItemDTO], currentId: String?) {
        self.items = items
        self.currentId = currentId

        let liveIds = Set(items.map { $0.id })
        thumbnails = thumbnails.filter { liveIds.contains($0.key) }
        pruneDiskThumbnails(keeping: liveIds)
        // Free full-resolution copies for items no longer in the TV library.
        LocalMediaStore.shared.prune(keeping: liveIds)
        persistManifest()

        delegate?.libraryStoreDidUpdateItems(self)
    }

    func updateCurrentId(_ currentId: String?) {
        self.currentId = currentId
        if let key = currentIdKey() {
            UserDefaults.standard.set(currentId, forKey: key)
        }
        delegate?.libraryStoreDidUpdateCurrent(self)
    }

    /// Updates the mirrored playback state for the live video. Notifies the delegate only
    /// when something actually changed to avoid redundant UI work on frequent updates.
    func updatePlayback(currentId: String?, isPlaying: Bool, position: Double, duration: Double) {
        let newState = PlaybackState(itemId: currentId, isPlaying: isPlaying,
                                     currentTime: position, duration: duration)
        guard newState != playback else { return }
        playback = newState
        delegate?.libraryStoreDidUpdatePlayback(self)
    }

    func setThumbnail(_ image: UIImage, forId id: String) {
        thumbnails[id] = image
        persistThumbnail(image, forId: id)
        delegate?.libraryStore(self, didUpdateThumbnailFor: id)
    }

    /// Clears all mirrored state for a single Apple TV, including its persisted data.
    /// If it was the active TV, the in-memory state is cleared too.
    func reset(tvName: String) {
        let hash = Self.stableHash(tvName)
        UserDefaults.standard.removeObject(forKey: itemsKeyPrefix + hash)
        UserDefaults.standard.removeObject(forKey: currentIdKeyPrefix + hash)
        try? FileManager.default.removeItem(at: baseThumbnailDirectory.appendingPathComponent(hash, isDirectory: true))

        guard tvName == activeTVName else { return }
        items = []
        currentId = nil
        thumbnails = [:]
        delegate?.libraryStoreDidUpdateItems(self)
        delegate?.libraryStoreDidUpdateCurrent(self)
    }

    // MARK: - Persistence

    private func loadPersistedManifest() {
        items = []
        currentId = nil
        guard let itemsKey = itemsKey(), let currentIdKey = currentIdKey() else { return }
        if let data = UserDefaults.standard.data(forKey: itemsKey),
           let decoded = try? JSONDecoder().decode([LibraryItemDTO].self, from: data) {
            items = decoded
        }
        currentId = UserDefaults.standard.string(forKey: currentIdKey)
    }

    private func persistManifest() {
        guard let itemsKey = itemsKey(), let currentIdKey = currentIdKey() else { return }
        if let data = try? JSONEncoder().encode(items) {
            UserDefaults.standard.set(data, forKey: itemsKey)
        }
        UserDefaults.standard.set(currentId, forKey: currentIdKey)
    }

    private func persistThumbnail(_ image: UIImage, forId id: String) {
        guard let url = thumbnailFileURL(for: id),
              let data = image.jpegData(compressionQuality: 0.7) else { return }
        do {
            try data.write(to: url, options: [.atomic])
        } catch {
            logger.error("Failed to persist thumbnail for \(id, privacy: .public): \(error.localizedDescription)")
        }
    }

    private func pruneDiskThumbnails(keeping liveIds: Set<String>) {
        guard let directory = activeThumbnailDirectory() else { return }
        let liveFileNames = Set(liveIds.map { "\(Self.stableHash($0)).jpg" })
        guard let files = try? FileManager.default.contentsOfDirectory(at: directory,
                                                                       includingPropertiesForKeys: nil) else {
            return
        }
        for file in files where !liveFileNames.contains(file.lastPathComponent) {
            try? FileManager.default.removeItem(at: file)
        }
    }

    // MARK: - Key & Path Helpers

    private func itemsKey() -> String? {
        guard let name = activeTVName else { return nil }
        return itemsKeyPrefix + Self.stableHash(name)
    }

    private func currentIdKey() -> String? {
        guard let name = activeTVName else { return nil }
        return currentIdKeyPrefix + Self.stableHash(name)
    }

    private func activeThumbnailDirectory() -> URL? {
        guard let name = activeTVName else { return nil }
        return baseThumbnailDirectory.appendingPathComponent(Self.stableHash(name), isDirectory: true)
    }

    private func ensureThumbnailDirectory() {
        guard let directory = activeThumbnailDirectory() else { return }
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    private func thumbnailFileURL(for id: String) -> URL? {
        guard let directory = activeThumbnailDirectory() else { return nil }
        return directory.appendingPathComponent("\(Self.stableHash(id)).jpg")
    }

    /// Deterministic FNV-1a 64-bit hash so disk filenames and keys are stable across launches.
    private static func stableHash(_ string: String) -> String {
        var hash: UInt64 = 0xcbf29ce484222325
        let prime: UInt64 = 0x100000001b3
        for byte in string.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* prime
        }
        return String(hash, radix: 16, uppercase: false)
    }
}
