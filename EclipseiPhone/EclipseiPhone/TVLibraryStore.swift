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

    /// Posted when a library thumbnail is written or rebuilt (`userInfo[thumbnailIdKey]`).
    static let thumbnailDidChangeNotification =
        Notification.Name("TVLibraryStore.thumbnailDidChange")
    /// `userInfo` key for the media id whose thumbnail changed.
    static let thumbnailIdKey = "id"

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

    /// Decoded grid thumbnails: purgeable `NSCache` + on-screen pins (see cache type).
    private let thumbnails = ThumbnailMemoryCache(
        megabyteLimit: ThumbnailMemoryCache.defaultMegabyteLimit()
    )

    /// Ids with a disk load already in flight, so a scrolling grid doesn't kick off
    /// duplicate reads for the same cell.
    private var pendingDiskLoads: Set<String> = []
    /// Miss retries while LocalMedia / JPEG writes are still landing.
    private var diskLoadAttempts: [String: Int] = [:]

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
        // Live selection is session-scoped. Restoring a previous `currentId` made
        // Show tiles look live on launch even when nothing was selected this session.
        clearCurrentIdForColdLaunch()

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
        thumbnails.removeAll()
        pendingDiskLoads.removeAll()
        diskLoadAttempts.removeAll()
        ensureThumbnailDirectory()
        loadPersistedManifest()
        mergePendingUploads()
        mergeCaptures()
        mergeImportedMedia()
        recoverOrphanedLocalMedia()
        warmMissingThumbnails()
        fillMissingVideoDurations()
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
        thumbnails.removeAll()
        pendingDiskLoads.removeAll()
        diskLoadAttempts.removeAll()
        ensureThumbnailDirectory()
        loadPersistedManifest()
        mergePendingUploads()
        mergeCaptures()
        mergeImportedMedia()
        recoverOrphanedLocalMedia()
        warmMissingThumbnails()
        fillMissingVideoDurations()

        delegate?.libraryStoreDidUpdateItems(self)
        delegate?.libraryStoreDidUpdateCurrent(self)
    }

    // MARK: - Reads

    func thumbnail(for id: String) -> UIImage? {
        if let cached = thumbnails[id] { return cached }
        loadThumbnailFromDisk(id)
        return nil
    }

    /// Pins thumbnails for tiles currently on screen (and the live item for the hero).
    ///
    /// Call after layout / reload so go-live memory pressure can’t blank visible cells
    /// when `NSCache` purges. Off-screen tiles reload from disk when they scroll in.
    func setVisibleThumbnailIds(_ ids: Set<String>) {
        thumbnails.setVisibleIds(ids)
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
            // Only a thumb rebuilt from another location needs writing back; the active
            // mode's own cache file would otherwise be re-encoded on every single load.
            var needsPersist = true

            for url in thumbURLs {
                if let loaded = ThumbnailDecoder.decode(fileURL: url) {
                    if isVideo && !VideoPosterFrame.isUsable(loaded) {
                        continue
                    }
                    image = loaded
                    needsPersist = url != thumbURLs.first
                    break
                }
            }
            if image == nil {
                for url in mediaURLs {
                    if isVideo {
                        image = VideoPosterFrame.image(at: url)
                    } else {
                        image = ThumbnailDecoder.decode(fileURL: url)
                    }
                    if image != nil { break }
                }
            }

            Task { @MainActor in
                self.pendingDiskLoads.remove(id)
                guard self.activeTVName == tvName,
                      self.activeLibraryMode == mode else { return }
                // Miss / failure: leave pending clear so the next configure can retry.
                guard let image else {
                    self.scheduleThumbnailRetry(id: id, tvName: tvName, mode: mode)
                    return
                }
                self.diskLoadAttempts.removeValue(forKey: id)
                // Always re-insert — refills NSCache after a memory-pressure purge.
                self.thumbnails[id] = image
                if needsPersist {
                    self.persistThumbnail(image, forId: id)
                }
                self.notifyThumbnailUpdated(for: id)
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
        mergeCaptures()
        mergeImportedMedia()
        recoverOrphanedLocalMedia()

        let keepIds = Set(self.items.map { $0.id })
            .union(PendingUploadStore.shared.pendingIds(for: mode))
            .union(CaptureStore.shared.keepIds)
            .union(ImportedMediaStore.shared.keepIds)
        thumbnails.retain(ids: keepIds)
        pruneDiskThumbnails(keeping: keepIds)
        // Keep full-res copies that still exist on disk even if the TV omitted them.
        // Captures are never pruned by TV manifests (separate root in LocalMediaStore).
        // Slideshows and Show membership use the same set so a TV omit cannot
        // empty a just-created slideshow whose files are still local-only.
        let localKeep = keepIds.union(Set(LocalMediaStore.shared.storedIds(for: mode)))
        LocalMediaStore.shared.prune(keeping: localKeep, mode: mode)
        LocalAlbumStore.shared.pruneMissingItems(keeping: localKeep)
        SlideshowStore.shared.pruneMissingItems(keeping: localKeep)
        persistManifest()
        fillMissingVideoDurations()

        delegate?.libraryStoreDidUpdateItems(self)
    }

    // MARK: - Local (offline) Additions

    /// Records an item added on the phone for the active library mode.
    /// - Parameter showId: Show that owns this import for CloudKit, if any.
    func addLocalItem(
        _ item: LibraryItemDTO,
        thumbnail: UIImage?,
        showId: UUID? = nil
    ) {
        let mode = activeLibraryMode
        PendingUploadStore.shared.enqueue(item, mode: mode)
        // Offline / never-paired: mint "My Library" so thumbnails have a disk home
        // before the first persist (otherwise batch imports only keep the last few
        // in NSCache and Slideshow rows stay blank).
        ensureLibraryIdentity()
        ensureThumbnailDirectory()
        if let thumbnail = thumbnail {
            let thumb = ThumbnailDecoder.downsample(thumbnail)
            thumbnails[item.id] = thumb
            persistThumbnail(thumb, forId: item.id)
            notifyThumbnailUpdated(for: item.id)
        }
        if !items.contains(where: { $0.id == item.id }) {
            items.append(item)
            persistManifest()
        }
        if !CaptureStore.shared.contains(id: item.id) {
            _ = ImportedMediaStore.shared.register(
                libraryId: item.id,
                isVideo: item.isVideo,
                duration: item.duration,
                orientation: ExternalOutputSettings.orientation,
                showId: showId
            )
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
        LocalAlbumStore.shared.removeItemFromAllAlbums(itemId: id)
        SlideshowStore.shared.removeItemFromAllSlideshows(itemId: id)
        if let imported = ImportedMediaStore.shared.record(id: id) {
            ImportedMediaStore.shared.markDeleted(cloudId: imported.cloudId)
        }
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

    /// Merges phone-owned captures into the display list (never sent to Apple TV).
    private func mergeCaptures() {
        let existing = Set(items.map { $0.id })
        let mode = ExternalOutputSettings.orientation
        for capture in CaptureStore.shared.capturesForCurrentMode
        where capture.orientation == mode {
            let dto = capture.asLibraryItem
            guard !existing.contains(dto.id) else { continue }
            items.append(dto)
        }
    }

    /// Merges CloudKit-synced imports that are not yet in the TV manifest.
    private func mergeImportedMedia() {
        let existing = Set(items.map { $0.id })
        let mode = ExternalOutputSettings.orientation
        for imported in ImportedMediaStore.shared.allActive
        where imported.orientation == mode {
            let dto = imported.asLibraryItem
            guard !existing.contains(dto.id) else { continue }
            items.append(dto)
        }
    }

    /// Re-merges captures after CloudKit fetch / local capture changes.
    func refreshMergedCaptures() {
        mergeCaptures()
        persistManifest()
        delegate?.libraryStoreDidUpdateItems(self)
    }

    /// Re-merges imported CloudKit media after a remote apply.
    func refreshMergedImports() {
        mergeImportedMedia()
        persistManifest()
        delegate?.libraryStoreDidUpdateItems(self)
    }

    /// True when the other Display Mode still has library content.
    func inactiveModeHasContent() -> Bool {
        let other: EclipseShareProtocol.LibraryMode =
            activeLibraryMode == .landscape ? .vertical : .landscape
        if !LocalMediaStore.shared.storedIds(for: other).isEmpty { return true }
        return !persistedItems(for: other).isEmpty
    }

    /// Restores items from LocalMedia / cached manifests.
    private func runLaunchRecovery() {
        ensureLibraryIdentity()
        mergePendingUploads()
        mergeCaptures()
        mergeImportedMedia()
        recoverOrphanedLocalMedia()
        recoverFromCachedManifests()
        warmMissingThumbnails()
        fillMissingVideoDurations()
    }

    /// Drops any persisted live item so launch starts with nothing selected.
    /// A connected Apple TV can reassert live via `current_changed` / manifest.
    private func clearCurrentIdForColdLaunch() {
        currentId = nil
        guard let name = activeTVName else { return }
        let hash = Self.stableHash(name)
        for mode in EclipseShareProtocol.LibraryMode.allCases {
            UserDefaults.standard.removeObject(
                forKey: currentIdKeyPrefix + hash + "." + mode.rawValue
            )
        }
        UserDefaults.standard.removeObject(forKey: currentIdKeyPrefix + hash)
    }

    /// Kicks off disk / LocalMedia thumbnail rebuilds for items missing a preview.
    private func warmMissingThumbnails() {
        for item in items where thumbnails[item.id] == nil {
            loadThumbnailFromDisk(item.id)
        }
    }

    /// Reloads a preview when the full file or JPEG lands after the first miss.
    func retryThumbnailIfMissing(for id: String) {
        guard thumbnails[id] == nil else { return }
        loadThumbnailFromDisk(id)
    }

    /// Retries a miss while LocalMedia / cache JPEGs are still being written.
    private func scheduleThumbnailRetry(
        id: String,
        tvName: String?,
        mode: EclipseShareProtocol.LibraryMode
    ) {
        let attempt = (diskLoadAttempts[id] ?? 0) + 1
        guard attempt <= 3 else {
            diskLoadAttempts.removeValue(forKey: id)
            return
        }
        diskLoadAttempts[id] = attempt
        let delay = 0.35 * Double(attempt)
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self,
                  self.activeTVName == tvName,
                  self.activeLibraryMode == mode else { return }
            self.loadThumbnailFromDisk(id)
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
        // Drop hyphenated / underscore twins created by older orphan matching first.
        dedupeItemsSharingLocalFile()

        let mode = activeLibraryMode
        // Compare against sanitized filenames — disk ids never keep UUID hyphens.
        let existingCanonical = Set(
            items.map { LocalMediaStore.canonicalFileName(forId: $0.id) }
        )
        // Imported only — captures must never enter PendingUpload / Multipeer.
        let orphans = LocalMediaStore.shared.storedIds(for: mode, provenance: .imported)
            .filter { !existingCanonical.contains($0) }
            .filter { !CaptureStore.shared.contains(id: $0) }
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
               let image = ThumbnailDecoder.decode(fileURL: url) {
                thumbnails[id] = image
                persistThumbnail(image, forId: id)
            }
        }
        persistManifest()
    }

    /// Removes duplicate library rows that point at the same on-disk LocalMedia file.
    ///
    /// Older builds listed UUID ids with hyphens while disk used underscores; orphan
    /// recovery then re-added the disk name as a second item.
    private func dedupeItemsSharingLocalFile() {
        let mode = activeLibraryMode
        var seenCanonical = Set<String>()
        var kept: [LibraryItemDTO] = []
        var removedIds: [String] = []

        for item in items {
            let canonical = LocalMediaStore.canonicalFileName(forId: item.id)
            if seenCanonical.contains(canonical) {
                removedIds.append(item.id)
                continue
            }
            seenCanonical.insert(canonical)
            kept.append(item)
        }

        guard !removedIds.isEmpty else { return }
        logger.info(
            "Removed \(removedIds.count) duplicate \(mode.rawValue, privacy: .public) library rows"
        )
        for id in removedIds {
            PendingUploadStore.shared.remove(id: id, mode: mode)
            thumbnails[id] = nil
            if currentId == id {
                currentId = kept.first(where: {
                    LocalMediaStore.canonicalFileName(forId: $0.id)
                        == LocalMediaStore.canonicalFileName(forId: id)
                })?.id
            }
        }
        items = kept
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
        let previousId = self.currentId
        if let previousId, previousId != currentId {
            // AirPlay player is still on the prior item until `present` runs next.
            VideoResumeStore.shared.parkLeavingVideoIfNeeded(itemId: previousId)
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
        ensureLibraryIdentity()
        ensureThumbnailDirectory()
        let thumb = ThumbnailDecoder.downsample(image)
        thumbnails[id] = thumb
        persistThumbnail(thumb, forId: id)
        notifyThumbnailUpdated(for: id)
    }

    /// Notifies the grid delegate and any other observers (e.g. Slideshow editor).
    private func notifyThumbnailUpdated(for id: String) {
        delegate?.libraryStore(self, didUpdateThumbnailFor: id)
        NotificationCenter.default.post(
            name: Self.thumbnailDidChangeNotification,
            object: self,
            userInfo: [Self.thumbnailIdKey: id]
        )
    }

    /// Updates loop / mute for a video and persists the manifest (local + pending upload).
    func updateVideoSetting(id: String, isLooping: Bool?, isMuted: Bool?) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        var item = items[index]
        guard item.isVideo else { return }
        var changed = false
        if let isLooping, item.isLooping != isLooping {
            item.isLooping = isLooping
            changed = true
        }
        if let isMuted, item.isMuted != isMuted {
            item.isMuted = isMuted
            changed = true
        }
        guard changed else { return }
        items[index] = item
        persistManifest()
        PendingUploadStore.shared.update(item, mode: activeLibraryMode)
        delegate?.libraryStoreDidUpdateItems(self)
    }

    /// Writes known file durations onto video items that were ingested with `0`.
    func applyVideoDurations(_ durations: [String: Double]) {
        var changed = false
        for (id, seconds) in durations {
            guard seconds > 0.05,
                  let index = items.firstIndex(where: { $0.id == id }) else { continue }
            let item = items[index]
            guard item.isVideo, item.duration <= 0 else { continue }
            let updated = LibraryItemDTO(
                id: item.id,
                name: item.name,
                isVideo: item.isVideo,
                duration: seconds,
                isLooping: item.isLooping,
                isMuted: item.isMuted,
                isAvailable: item.isAvailable
            )
            items[index] = updated
            PendingUploadStore.shared.update(updated, mode: activeLibraryMode)
            changed = true
        }
        guard changed else { return }
        persistManifest()
        delegate?.libraryStoreDidUpdateItems(self)
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
        thumbnails.removeAll()
        pendingDiskLoads.removeAll()
        diskLoadAttempts.removeAll()
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
                return
            }
            Task { @MainActor in
                // Batch import can evict NSCache before this write finishes.
                guard self.thumbnails[id] == nil else { return }
                self.thumbnails[id] = image
                self.notifyThumbnailUpdated(for: id)
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
