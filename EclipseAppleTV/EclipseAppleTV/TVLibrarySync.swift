// TVLibrarySync.swift
import Foundation
import Combine
import UIKit
import AVFoundation
import MultipeerConnectivity
import os.log

/// Mirrors the Apple TV media library to connected companion peers.
///
/// Observes `MediaDataSource` (the single source of truth) and pushes:
/// - a full ordered manifest whenever the library changes,
/// - a lightweight "current changed" update when the live item changes,
/// - thumbnails (once per peer) for every item.
///
/// Lives for the lifetime of the scene and is owned by `SceneDelegate`.
@MainActor
final class TVLibrarySync {

    // MARK: - Properties

    private weak var connectionManager: ConnectionManager?
    private let dataSource: MediaDataSource
    private var cancellables = Set<AnyCancellable>()

    /// Ids (file names) whose thumbnails have already been sent to the current peer.
    private var sentThumbnailIds = Set<String>()

    /// Cached video durations (seconds) keyed by item id (file name). Populated lazily
    /// when thumbnails are generated; persists across reconnects so the manifest can
    /// report durations without recomputing them.
    private var videoDurations: [String: Double] = [:]

    private let thumbnailTargetSize = CGSize(width: 480, height: 270)
    private let logger = Logger(subsystem: "com.eclipsetv.app", category: "TVLibrarySync")

    // MARK: - Initialization

    init(connectionManager: ConnectionManager, dataSource: MediaDataSource = .shared) {
        self.connectionManager = connectionManager
        self.dataSource = dataSource
        observeDataSource()
    }

    // MARK: - Peer Lifecycle

    /// A companion connected: reset per-peer state and push the whole library.
    func peerDidConnect(_ peer: MCPeerID) {
        logger.info("Peer connected, pushing full library: \(peer.displayName, privacy: .public)")
        // Catch files purged by tvOS since launch so they're reported as unavailable.
        dataSource.revalidateAvailability()
        sentThumbnailIds.removeAll()
        broadcastManifest()
        sendPendingThumbnails()
    }

    /// A companion disconnected: if no peers remain, forget what we've sent so a future
    /// peer receives a fresh, complete set of thumbnails.
    func peerDidDisconnect(_ peer: MCPeerID) {
        if (connectionManager?.connectedPeerCount ?? 0) == 0 {
            sentThumbnailIds.removeAll()
        }
    }

    /// Pushes a fresh manifest after a change that doesn't alter the path list (e.g. a
    /// per-item video setting toggled remotely), so the companion reflects new state.
    func librarySettingsDidChange() {
        broadcastManifest()
    }

    // MARK: - Observation

    private func observeDataSource() {
        // Library contents changed (add / remove / reorder): resend manifest + any new thumbnails.
        dataSource.$mediaPaths
            .dropFirst()
            .debounce(for: .milliseconds(300), scheduler: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.broadcastManifest()
                self?.sendPendingThumbnails()
            }
            .store(in: &cancellables)

        // Live item changed: send a lightweight update so the companion can re-highlight.
        dataSource.$currentIndex
            .removeDuplicates()
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.broadcastCurrentChanged()
            }
            .store(in: &cancellables)
    }

    // MARK: - Broadcasting

    private func broadcastManifest() {
        guard let connectionManager = connectionManager, connectionManager.connectedPeerCount > 0 else { return }
        connectionManager.sendLibraryManifest(items: currentItems(), currentId: currentId())
    }

    private func broadcastCurrentChanged() {
        guard let connectionManager = connectionManager, connectionManager.connectedPeerCount > 0 else { return }
        connectionManager.sendCurrentChanged(currentId: currentId())
    }

    private func currentItems() -> [LibraryItemDTO] {
        // Fresh AppState reads the latest persisted video settings from UserDefaults so
        // the manifest reflects changes made via the TV UI or remotely from the phone.
        let settingsProvider = AppState()
        var items: [LibraryItemDTO] = []
        for index in 0..<dataSource.count {
            guard let path = dataSource.getPath(at: index) else { continue }
            let item = MediaItem(path: path)
            let duration = item.isVideo ? (videoDurations[item.fileName] ?? 0) : 0
            var dto = LibraryItemDTO(id: item.fileName, name: item.fileName,
                                     isVideo: item.isVideo, duration: duration)
            if item.isVideo {
                let settings = settingsProvider.getVideoSettings(for: path)
                dto.isLooping = settings.isLooping
                dto.isMuted = settings.isMuted
            }
            items.append(dto)
        }

        // Append purged items (not in the live list) so the companion can show them as
        // unavailable and offer to re-send. They reuse the phone's cached thumbnail.
        for entry in dataSource.unavailableLedger.items {
            var dto = LibraryItemDTO(id: entry.id, name: entry.name, isVideo: entry.isVideo, duration: 0)
            dto.isAvailable = false
            items.append(dto)
        }
        return items
    }

    private func currentId() -> String? {
        guard let path = dataSource.getCurrentPath() else { return nil }
        return URL(fileURLWithPath: path).lastPathComponent
    }

    // MARK: - Thumbnails

    /// Sends thumbnails for any items the current peer hasn't received yet.
    private func sendPendingThumbnails() {
        guard let connectionManager = connectionManager, connectionManager.connectedPeerCount > 0 else { return }

        for index in 0..<dataSource.count {
            guard let path = dataSource.getPath(at: index) else { continue }
            let id = URL(fileURLWithPath: path).lastPathComponent
            guard !sentThumbnailIds.contains(id) else { continue }

            // Mark optimistically so we don't kick off duplicate generation tasks.
            sentThumbnailIds.insert(id)
            Task { [weak self] in
                await self?.generateAndSendThumbnail(path: path, id: id)
            }
        }
    }

    private func generateAndSendThumbnail(path: String, id: String) async {
        let item = MediaItem(path: path)
        let image: UIImage?
        if item.isVideo {
            await cacheDurationIfNeeded(path: path, id: id)
            image = await VideoThumbnailCache.shared.getThumbnailAsync(for: path, targetSize: thumbnailTargetSize)
        } else {
            image = await AsyncImageLoader.shared.loadImage(from: path, targetSize: thumbnailTargetSize)
        }

        guard let image = image, let data = image.jpegData(compressionQuality: 0.7) else {
            logger.error("Failed to build thumbnail for \(id, privacy: .public)")
            sentThumbnailIds.remove(id) // allow a retry on the next sync
            return
        }

        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("eclipse_thumb_\(UUID().uuidString).jpg")
        do {
            try data.write(to: tempURL, options: [.atomic])
        } catch {
            logger.error("Failed to write temp thumbnail for \(id, privacy: .public): \(error.localizedDescription)")
            sentThumbnailIds.remove(id)
            return
        }

        connectionManager?.sendThumbnail(at: tempURL, forId: id)
    }

    /// Loads a video's duration once and caches it, then rebroadcasts the manifest so the
    /// companion can display the duration (the first manifest after connect reports 0).
    private func cacheDurationIfNeeded(path: String, id: String) async {
        guard videoDurations[id] == nil else { return }

        let asset = AVURLAsset(url: URL(fileURLWithPath: path))
        let seconds: Double
        do {
            let duration = try await asset.load(.duration)
            seconds = duration.seconds.isFinite ? duration.seconds : 0
        } catch {
            logger.error("Failed to load duration for \(id, privacy: .public): \(error.localizedDescription)")
            return
        }

        videoDurations[id] = seconds
        broadcastManifest()
    }
}
