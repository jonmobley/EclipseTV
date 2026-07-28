//
//  TVLibraryStore.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

// TVLibraryStore.swift
import UIKit
import AVFoundation
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

/// Read-only mirror of the Apple TV library, populated from Multipeer messages and
/// cached on disk. State is namespaced per Apple TV **and** per Landscape / Vertical
/// library mode. Legacy unscoped keys migrate to landscape.
@MainActor
final class TVLibraryStore {

    /// Shared instance written by `iPhoneConnectionManager` and read by the grid.
    static let shared = TVLibraryStore()

    // MARK: - State

    private(set) var items: [LibraryItemDTO] = []
    private(set) var currentId: String?

    /// Active Landscape / Vertical bucket (tracks `ExternalOutputSettings.libraryMode`).
    private(set) var activeLibraryMode: EclipseShareProtocol.LibraryMode = .landscape

    /// The Apple TV whose library is currently being shown, or nil if none has ever
    /// been selected. Used to namespace all persisted state.
    private(set) var activeTVName: String?

    /// Whether we are currently connected to the Apple TV. Not persisted.
    private(set) var isOnline = false

    /// Live playback state for the currently playing video on the Apple TV. Not persisted.
    private(set) var playback = PlaybackState()

    private var thumbnails: [String: UIImage] = [:]

    /// Ids with a disk load already in flight, so a scrolling grid doesn't kick off
    /// duplicate reads for the same cell.
    private var pendingDiskLoads: Set<String> = []

    /// Serial queue for thumbnail disk I/O.
    private let ioQueue = DispatchQueue(label: "com.eclipseapp.ios.TVLibraryStore.io", qos: .utility)

    weak var delegate: TVLibraryStoreDelegate?

    var isEmpty: Bool { items.isEmpty }

    // MARK: - Persistence Config

    private let itemsKeyPrefix = "EclipseTV.companion.items."
    private let currentIdKeyPrefix = "EclipseTV.companion.currentId."
    private let activeTVNameKey = "EclipseTV.companion.activeTVName"

    private let baseThumbnailDirectory: URL
    private let logger = Logger(subsystem: "com.eclipseapp.ios", category: "TVLibraryStore")
    private var settingsObserver: NSObjectProtocol?

    private init() {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        baseThumbnailDirectory = caches.appendingPathComponent("TVLibraryThumbnails", isDirectory: true)
        try? FileManager.default.createDirectory(at: baseThumbnailDirectory, withIntermediateDirectories: true)

        activeLibraryMode = ExternalOutputSettings.libraryMode

        if let name = UserDefaults.standard.string(forKey: activeTVNameKey) {
            activeTVName = name
            migrateLegacyKeysIfNeeded(for: name)
            ensureThumbnailDirectory()
            loadPersistedManifest()
        }
        runLaunchRecovery()

        settingsObserver = NotificationCenter.default.addObserver(
            forName: ExternalOutputSettings.didChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.syncLibraryModeFromSettings()
            }
        }
    }

    deinit {
        if let settingsObserver {
            NotificationCenter.default.removeObserver(settingsObserver)
        }
    }

    // MARK: - Mode Switching

    /// Reloads the in-memory bucket when Display Mode changes.
    func syncLibraryModeFromSettings() {
        let mode = ExternalOutputSettings.libraryMode
        guard mode != activeLibraryMode else { return }
        persistManifest()
        activeLibraryMode = mode
        thumbnails = [:]
        pendingDiskLoads.removeAll()
        ensureThumbnailDirectory()
        loadPersistedManifest()
        mergePendingUploads()
        recoverOrphanedLocalMedia()
        warmMissingThumbnails()
        playback = PlaybackState()
        delegate?.libraryStoreDidUpdateItems(self)
        delegate?.libraryStoreDidUpdateCurrent(self)
        delegate?.libraryStoreDidUpdatePlayback(self)
        logger.info("Library mode -> \(mode.rawValue, privacy: .public)")
    }

    // MARK: - Active TV Selection

    /// Switches the active library to `name`, loading that TV's persisted manifest.
    func setActiveTV(_ name: String) {
        KnownTVRegistry.shared.remember(name: name)

        guard name != activeTVName else { return }
        activeTVName = name
        UserDefaults.standard.set(name, forKey: activeTVNameKey)

        migrateLegacyKeysIfNeeded(for: name)
        thumbnails = [:]
        ensureThumbnailDirectory()
        loadPersistedManifest()
        mergePendingUploads()
        recoverOrphanedLocalMedia()

        delegate?.libraryStoreDidUpdateItems(self)
        delegate?.libraryStoreDidUpdateCurrent(self)
    }

    // MARK: - Reads

    func thumbnail(for id: String) -> UIImage? {
        if let cached = thumbnails[id] { return cached }
        loadThumbnailFromDisk(id)
        return nil
    }

    /// Loads a cached thumb, or rebuilds one from LocalMedia / the other mode's cache.
    private func loadThumbnailFromDisk(_ id: String) {
        guard !pendingDiskLoads.contains(id) else { return }
        pendingDiskLoads.insert(id)
        let tvName = activeTVName
        let mode = activeLibraryMode
        let thumbURLs = thumbnailCandidateURLs(for: id)
        let mediaURLs = [
            LocalMediaStore.shared.localURL(forId: id, mode: mode),
            LocalMediaStore.shared.localURL(
                forId: id,
                mode: mode == .landscape ? .vertical : .landscape
            )
        ].compactMap { $0 }
        let isVideo = items.first(where: { $0.id == id })?.isVideo
            ?? Self.isVideoFilename(id)

        ioQueue.async {
            var image: UIImage?
            for url in thumbURLs {
                if let loaded = UIImage(contentsOfFile: url.path)?.preparingForDisplay() {
                    image = loaded
                    break
                }
            }
            if image == nil {
                for url in mediaURLs {
                    if isVideo {
                        image = Self.videoPreviewImage(at: url)?.preparingForDisplay()
                    } else {
                        image = UIImage(contentsOfFile: url.path)?.preparingForDisplay()
                    }
                    if image != nil { break }
                }
            }

            Task { @MainActor in
                self.pendingDiskLoads.remove(id)
                guard let image,
                      self.activeTVName == tvName,
                      self.activeLibraryMode == mode else { return }
                if self.thumbnails[id] == nil {
                    self.thumbnails[id] = image
                }
                self.persistThumbnail(image, forId: id)
                self.delegate?.libraryStore(self, didUpdateThumbnailFor: id)
            }
        }
    }

    /// Thumbnail paths: active mode, other mode, then legacy flat `<tvHash>/<idHash>.jpg`.
    private func thumbnailCandidateURLs(for id: String) -> [URL] {
        guard let name = activeTVName else { return [] }
        let tvDir = baseThumbnailDirectory
            .appendingPathComponent(Self.stableHash(name), isDirectory: true)
        let file = "\(Self.stableHash(id)).jpg"
        let other: EclipseShareProtocol.LibraryMode =
            activeLibraryMode == .landscape ? .vertical : .landscape
        return [
            tvDir.appendingPathComponent(activeLibraryMode.directoryName)
                .appendingPathComponent(file),
            tvDir.appendingPathComponent(other.directoryName).appendingPathComponent(file),
            tvDir.appendingPathComponent(file)
        ]
    }

    private static func videoPreviewImage(at url: URL) -> UIImage? {
        let asset = AVURLAsset(url: url)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 720, height: 720)
        let semaphore = DispatchSemaphore(value: 0)
        var image: UIImage?
        Task {
            defer { semaphore.signal() }
            do {
                let cg = try await generator.image(at: .zero).image
                image = UIImage(cgImage: cg)
            } catch {
                image = nil
            }
        }
        _ = semaphore.wait(timeout: .now() + 5)
        return image
    }

    func item(at index: Int) -> LibraryItemDTO? {
        guard index >= 0 && index < items.count else { return nil }
        return items[index]
    }

    // MARK: - Connection State

    func setOnline(_ online: Bool) {
        guard online != isOnline else { return }
        isOnline = online
        if !online, playback != PlaybackState() {
            playback = PlaybackState()
            delegate?.libraryStoreDidUpdatePlayback(self)
        }
        delegate?.libraryStoreDidChangeConnection(self)
    }

    // MARK: - Updates (from the connection manager)

    /// Replaces the full manifest for `mode`. When `mode` matches the active bucket,
    /// updates the UI; otherwise persists quietly into that mode's cache.
    func updateManifest(items: [LibraryItemDTO],
                        currentId: String?,
                        mode: EclipseShareProtocol.LibraryMode = ExternalOutputSettings.libraryMode) {
        let modeSuffix = mode.rawValue
        let manifestIds = Set(items.map { $0.id })

        for id in PendingUploadStore.shared.pendingIds(for: mode) where manifestIds.contains(id) {
            PendingUploadStore.shared.remove(id: id, mode: mode)
        }

        // An empty remote bucket must not wipe phone-side LocalMedia (e.g. TV Caches
        // miss after Landscape/Vertical migration). Recover local files instead.
        if items.isEmpty {
            let localIds = LocalMediaStore.shared.storedIds(for: mode)
            if !localIds.isEmpty {
                logger.warning(
                    "Ignoring empty \(modeSuffix, privacy: .public) manifest; \(localIds.count) local files remain"
                )
                if mode == activeLibraryMode {
                    mergePendingUploads()
                    recoverOrphanedLocalMedia()
                    persistManifest()
                    delegate?.libraryStoreDidUpdateItems(self)
                }
                return
            }
        }

        if mode != activeLibraryMode {
            persistBucket(items: items, currentId: currentId, mode: mode)
            logger.debug("Stored offline manifest for mode \(modeSuffix, privacy: .public)")
            return
        }

        self.items = items
        self.currentId = currentId
        mergePendingUploads()
        recoverOrphanedLocalMedia()

        let keepIds = Set(self.items.map { $0.id })
            .union(PendingUploadStore.shared.pendingIds(for: mode))
        thumbnails = thumbnails.filter { keepIds.contains($0.key) }
        pruneDiskThumbnails(keeping: keepIds)
        // Keep full-res copies that still exist on disk even if the TV omitted them.
        let localKeep = keepIds.union(Set(LocalMediaStore.shared.storedIds(for: mode)))
        LocalMediaStore.shared.prune(keeping: localKeep, mode: mode)
        persistManifest()

        delegate?.libraryStoreDidUpdateItems(self)
    }

    // MARK: - Local (offline) Additions

    /// Records an item added on the phone for the active library mode.
    func addLocalItem(_ item: LibraryItemDTO, thumbnail: UIImage?) {
        let mode = activeLibraryMode
        PendingUploadStore.shared.enqueue(item, mode: mode)
        if let thumbnail = thumbnail {
            thumbnails[item.id] = thumbnail
            persistThumbnail(thumbnail, forId: item.id)
        }
        if !items.contains(where: { $0.id == item.id }) {
            items.append(item)
            persistManifest()
        }
        delegate?.libraryStoreDidUpdateItems(self)
    }

    /// Removes a not-yet-synced local item from the active mode.
    func removeLocalItem(id: String) {
        let mode = activeLibraryMode
        PendingUploadStore.shared.remove(id: id, mode: mode)
        LocalMediaStore.shared.remove(id: id, mode: mode)
        thumbnails[id] = nil
        if let index = items.firstIndex(where: { $0.id == id }) {
            items.remove(at: index)
            persistManifest()
        }
        if currentId == id { currentId = nil }
        delegate?.libraryStoreDidUpdateItems(self)
    }

    /// Appends queued uploads for the active mode that aren't already present.
    private func mergePendingUploads() {
        let existing = Set(items.map { $0.id })
        for item in PendingUploadStore.shared.items(for: activeLibraryMode)
        where !existing.contains(item.id) {
            items.append(item)
        }
    }

    /// True when the other Display Mode still has library content.
    func inactiveModeHasContent() -> Bool {
        let other: EclipseShareProtocol.LibraryMode =
            activeLibraryMode == .landscape ? .vertical : .landscape
        if !LocalMediaStore.shared.storedIds(for: other).isEmpty { return true }
        return !persistedItems(for: other).isEmpty
    }

    /// Restores items from LocalMedia / cached manifests; opens Vertical if that's
    /// where the library actually is.
    private func runLaunchRecovery() {
        ensureLibraryIdentity()
        mergePendingUploads()
        recoverOrphanedLocalMedia()
        recoverFromCachedManifests()
        if items.isEmpty {
            adoptVerticalIfLandscapeEmpty()
        }
        warmMissingThumbnails()
    }

    /// Kicks off disk / LocalMedia thumbnail rebuilds for items missing a preview.
    private func warmMissingThumbnails() {
        for item in items where thumbnails[item.id] == nil {
            loadThumbnailFromDisk(item.id)
        }
    }

    private static let localLibraryName = "My Library"

    private func ensureLibraryIdentity() {
        guard activeTVName == nil else { return }
        let hasLocal =
            !LocalMediaStore.shared.storedIds(for: .landscape).isEmpty
            || !LocalMediaStore.shared.storedIds(for: .vertical).isEmpty
            || !PendingUploadStore.shared.allUploads.isEmpty
        guard hasLocal else { return }
        activeTVName = Self.localLibraryName
        UserDefaults.standard.set(Self.localLibraryName, forKey: activeTVNameKey)
        ensureThumbnailDirectory()
    }

    private func recoverOrphanedLocalMedia() {
        let mode = activeLibraryMode
        let existing = Set(items.map(\.id))
        let orphans = LocalMediaStore.shared.storedIds(for: mode).filter { !existing.contains($0) }
        guard !orphans.isEmpty else { return }

        logger.info(
            "Recovering \(orphans.count) local \(mode.rawValue, privacy: .public) items"
        )
        for id in orphans {
            let isVideo = Self.isVideoFilename(id)
            let item = LibraryItemDTO(
                id: id,
                name: id,
                isVideo: isVideo,
                duration: 0,
                isLooping: isVideo ? false : nil,
                isMuted: isVideo ? false : nil,
                isAvailable: true
            )
            PendingUploadStore.shared.enqueue(item, mode: mode)
            if !items.contains(where: { $0.id == id }) {
                items.append(item)
            }
            if let url = LocalMediaStore.shared.localURL(forId: id, mode: mode),
               !isVideo,
               let image = UIImage(contentsOfFile: url.path) {
                thumbnails[id] = image
                persistThumbnail(image, forId: id)
            }
        }
        persistManifest()
    }

    private func recoverFromCachedManifests() {
        guard items.isEmpty else { return }

        var names = KnownTVRegistry.shared.all().map(\.name)
        if let activeTVName, !names.contains(activeTVName) {
            names.insert(activeTVName, at: 0)
        }
        if !names.contains(Self.localLibraryName) {
            names.append(Self.localLibraryName)
        }

        let mode = activeLibraryMode
        var best: (name: String, items: [LibraryItemDTO], currentId: String?)?
        for name in names {
            migrateLegacyKeysIfNeeded(for: name)
            let decoded = persistedItems(for: mode, tvName: name)
            guard decoded.count > (best?.items.count ?? 0) else { continue }
            let current = UserDefaults.standard.string(
                forKey: currentIdKeyPrefix + Self.stableHash(name) + "." + mode.rawValue
            )
            best = (name, decoded, current)
        }
        guard let best else { return }

        logger.info(
            "Restored \(best.items.count) \(mode.rawValue, privacy: .public) items from \(best.name, privacy: .public)"
        )
        if activeTVName != best.name {
            activeTVName = best.name
            UserDefaults.standard.set(best.name, forKey: activeTVNameKey)
            ensureThumbnailDirectory()
        }
        items = best.items
        currentId = best.currentId
        mergePendingUploads()
        recoverOrphanedLocalMedia()
        persistManifest()
    }

    /// Recent adds during Vertical testing live in that bucket — don't leave Landscape empty.
    private func adoptVerticalIfLandscapeEmpty() {
        guard activeLibraryMode == .landscape, items.isEmpty else { return }
        let hasVertical =
            !LocalMediaStore.shared.storedIds(for: .vertical).isEmpty
            || !persistedItems(for: .vertical).isEmpty
        guard hasVertical else { return }

        logger.info("Landscape empty; opening Vertical library which still has content")
        UserDefaults.standard.set(
            ExternalOutputOrientation.portrait.rawValue,
            forKey: "EclipseTV.camera.outputOrientation"
        )
        activeLibraryMode = .vertical
        thumbnails = [:]
        pendingDiskLoads.removeAll()
        ensureThumbnailDirectory()
        loadPersistedManifest()
        mergePendingUploads()
        recoverOrphanedLocalMedia()
    }

    private func persistedItems(
        for mode: EclipseShareProtocol.LibraryMode,
        tvName: String? = nil
    ) -> [LibraryItemDTO] {
        guard let name = tvName ?? activeTVName else { return [] }
        let key = itemsKeyPrefix + Self.stableHash(name) + "." + mode.rawValue
        guard let data = UserDefaults.standard.data(forKey: key),
              let decoded = try? JSONDecoder().decode([LibraryItemDTO].self, from: data) else {
            return []
        }
        return decoded
    }

    private static func isVideoFilename(_ name: String) -> Bool {
        let ext = (name as NSString).pathExtension.lowercased()
        return ["mp4", "mov", "m4v", "avi", "mkv"].contains(ext)
    }

    func updateCurrentId(_ currentId: String?,
                         mode: EclipseShareProtocol.LibraryMode = ExternalOutputSettings.libraryMode) {
        if mode != activeLibraryMode {
            if let key = currentIdKey(for: mode) {
                UserDefaults.standard.set(currentId, forKey: key)
            }
            return
        }
        self.currentId = currentId
        if let key = currentIdKey() {
            UserDefaults.standard.set(currentId, forKey: key)
        }
        delegate?.libraryStoreDidUpdateCurrent(self)
    }

    func updatePlayback(currentId: String?, isPlaying: Bool, position: Double, duration: Double,
                        mode: EclipseShareProtocol.LibraryMode = ExternalOutputSettings.libraryMode) {
        guard mode == activeLibraryMode else { return }
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

    /// Clears all mirrored state for a single Apple TV (both modes).
    func reset(tvName: String) {
        let hash = Self.stableHash(tvName)
        for mode in EclipseShareProtocol.LibraryMode.allCases {
            UserDefaults.standard.removeObject(forKey: itemsKeyPrefix + hash + "." + mode.rawValue)
            UserDefaults.standard.removeObject(forKey: currentIdKeyPrefix + hash + "." + mode.rawValue)
        }
        // Legacy unscoped keys
        UserDefaults.standard.removeObject(forKey: itemsKeyPrefix + hash)
        UserDefaults.standard.removeObject(forKey: currentIdKeyPrefix + hash)
        try? FileManager.default.removeItem(
            at: baseThumbnailDirectory.appendingPathComponent(hash, isDirectory: true)
        )

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
        persistBucket(items: items, currentId: currentId, mode: activeLibraryMode)
    }

    private func persistBucket(items: [LibraryItemDTO],
                               currentId: String?,
                               mode: EclipseShareProtocol.LibraryMode) {
        guard let itemsKey = itemsKey(for: mode),
              let currentIdKey = currentIdKey(for: mode) else { return }
        if let data = try? JSONEncoder().encode(items) {
            UserDefaults.standard.set(data, forKey: itemsKey)
        }
        UserDefaults.standard.set(currentId, forKey: currentIdKey)
    }

    private func persistThumbnail(_ image: UIImage, forId id: String) {
        guard let url = thumbnailFileURL(for: id) else { return }
        ioQueue.async { [logger] in
            guard let data = image.jpegData(compressionQuality: 0.7) else { return }
            do {
                try data.write(to: url, options: [.atomic])
            } catch {
                logger.error(
                    "Failed to persist thumbnail for \(id, privacy: .public): \(error.localizedDescription)"
                )
            }
        }
    }

    private func pruneDiskThumbnails(keeping liveIds: Set<String>) {
        guard let directory = activeThumbnailDirectory() else { return }
        let liveFileNames = Set(liveIds.map { "\(Self.stableHash($0)).jpg" })
        ioQueue.async {
            guard let files = try? FileManager.default.contentsOfDirectory(
                at: directory, includingPropertiesForKeys: nil
            ) else { return }
            for file in files where !liveFileNames.contains(file.lastPathComponent) {
                try? FileManager.default.removeItem(at: file)
            }
        }
    }

    // MARK: - Key & Path Helpers

    private func itemsKey(for mode: EclipseShareProtocol.LibraryMode? = nil) -> String? {
        guard let name = activeTVName else { return nil }
        let m = mode ?? activeLibraryMode
        return itemsKeyPrefix + Self.stableHash(name) + "." + m.rawValue
    }

    private func currentIdKey(for mode: EclipseShareProtocol.LibraryMode? = nil) -> String? {
        guard let name = activeTVName else { return nil }
        let m = mode ?? activeLibraryMode
        return currentIdKeyPrefix + Self.stableHash(name) + "." + m.rawValue
    }

    private func activeThumbnailDirectory() -> URL? {
        guard let name = activeTVName else { return nil }
        return baseThumbnailDirectory
            .appendingPathComponent(Self.stableHash(name), isDirectory: true)
            .appendingPathComponent(activeLibraryMode.directoryName, isDirectory: true)
    }

    private func ensureThumbnailDirectory() {
        guard let directory = activeThumbnailDirectory() else { return }
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    private func thumbnailFileURL(for id: String) -> URL? {
        guard let directory = activeThumbnailDirectory() else { return nil }
        return directory.appendingPathComponent("\(Self.stableHash(id)).jpg")
    }

    /// Migrates legacy `…items.<hash>` / `…currentId.<hash>` → `.landscape`.
    private func migrateLegacyKeysIfNeeded(for tvName: String) {
        let hash = Self.stableHash(tvName)
        let legacyItems = itemsKeyPrefix + hash
        let landscapeItems = legacyItems + "." + EclipseShareProtocol.LibraryMode.landscape.rawValue
        if UserDefaults.standard.data(forKey: landscapeItems) == nil,
           let data = UserDefaults.standard.data(forKey: legacyItems) {
            UserDefaults.standard.set(data, forKey: landscapeItems)
            UserDefaults.standard.removeObject(forKey: legacyItems)
            logger.info("Migrated companion items → landscape for \(tvName, privacy: .public)")
        }
        let legacyCurrent = currentIdKeyPrefix + hash
        let landscapeCurrent = legacyCurrent + "." + EclipseShareProtocol.LibraryMode.landscape.rawValue
        if UserDefaults.standard.object(forKey: landscapeCurrent) == nil,
           let value = UserDefaults.standard.string(forKey: legacyCurrent) {
            UserDefaults.standard.set(value, forKey: landscapeCurrent)
            UserDefaults.standard.removeObject(forKey: legacyCurrent)
        }

        // Move flat thumbs under `<hash>/` into `<hash>/Landscape/`.
        let tvDir = baseThumbnailDirectory.appendingPathComponent(hash, isDirectory: true)
        let landscapeDir = tvDir.appendingPathComponent(
            EclipseShareProtocol.LibraryMode.landscape.directoryName, isDirectory: true
        )
        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: tvDir, includingPropertiesForKeys: [.isDirectoryKey]
        ) else { return }
        try? FileManager.default.createDirectory(at: landscapeDir, withIntermediateDirectories: true)
        for url in contents {
            let isDir = (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
            if isDir { continue }
            let dest = landscapeDir.appendingPathComponent(url.lastPathComponent)
            if FileManager.default.fileExists(atPath: dest.path) {
                try? FileManager.default.removeItem(at: url)
            } else {
                try? FileManager.default.moveItem(at: url, to: dest)
            }
        }
    }

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
