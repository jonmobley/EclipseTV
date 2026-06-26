// ImageViewController+ContentLoading.swift
import UIKit
import os.log
import MultipeerConnectivity

// MARK: - ConnectionManagerDelegate & Content Loading

extension ImageViewController {

    // MARK: - ConnectionManagerDelegate Implementation

    func connectionManager(_ manager: ConnectionManager, didReceiveImageAt path: String) {
        let startTime = Date()

        // Check if we're in move mode or showing a menu - if so, queue the content
        if isMoveMode || presentedViewController != nil {
            logger.info("Queuing received image as app is in move mode or settings: \(path)")
            queuedContent.append((path: path, isVideo: false))

            // Show a subtle notification that content was received but queued
            showNotificationToast(message: "New image received (will be added when ready)")
            return
        }

        // Add the newly received image using data source
        dataSource.addMedia(at: path)

        let endTime = Date()
        let duration = endTime.timeIntervalSince(startTime)
        logger.info("Added new image via data source in \(String(format: "%.3f", duration))s")
    }

    func connectionManager(_ manager: ConnectionManager, didUpdateConnectionState connected: Bool, with peer: MCPeerID?) {
        if connected, let peer = peer {
            // Show a notification that a device connected
            toastView.show(message: "Connected to \(peer.displayName)")
        }
    }

    /// The companion asked us to make a specific item live. Resolve it and bring it
    /// to fullscreen, mirroring the behavior of selecting it on the TV.
    func connectionManager(_ manager: ConnectionManager, didReceivePlayRequestForId id: String) {
        // A file may have been purged by tvOS since the last sync; catch it now (this
        // moves any missing file into the ledger and rebroadcasts an updated manifest)
        // before we attempt to display it.
        dataSource.revalidateAvailability()

        guard let index = libraryIndex(forItemId: id) else {
            logger.error("Play request for unavailable id: \(id, privacy: .public)")
            showNotificationToast(message: "That item is no longer available")
            Task { @MainActor in
                self.connectionManager?.librarySync?.librarySettingsDidChange()
            }
            return
        }

        // If the user is mid-reorder or a menu is open, just update the selection; the
        // live view will catch up once the UI returns to a safe state.
        if isMoveMode || presentedViewController != nil {
            dataSource.setCurrentIndex(index)
            showNotificationToast(message: "Selection updated from companion")
            return
        }

        dataSource.setCurrentIndex(index)

        if isInGridMode {
            hideGridView()
        } else {
            displayImageAtCurrentIndex()
        }
    }

    /// The companion asked us to delete an item.
    func connectionManager(_ manager: ConnectionManager, didReceiveDeleteRequestForId id: String) {
        guard let index = libraryIndex(forItemId: id) else {
            // Not in the live list: it may be an unavailable (purged) item the user chose
            // to remove. Drop the ledger entry and refresh the companion's manifest.
            if dataSource.unavailableLedger.remove(id: id) != nil {
                logger.info("Removed unavailable ledger entry: \(id, privacy: .public)")
                Task { @MainActor in
                    self.connectionManager?.librarySync?.librarySettingsDidChange()
                }
            } else {
                logger.error("Delete request for unknown id: \(id, privacy: .public)")
            }
            return
        }

        // Avoid mutating the list while the user is reorganizing or a menu is open.
        if isMoveMode || presentedViewController != nil {
            showNotificationToast(message: "Busy on TV - try again in a moment")
            return
        }

        let wasFullscreenTarget = !isInGridMode && index == dataSource.currentIndex
        dataSource.removeMedia(at: index)

        // If we just deleted the item shown fullscreen, refresh or fall back to the grid.
        if wasFullscreenTarget {
            if dataSource.isEmpty {
                showGridView()
            } else {
                displayImageAtCurrentIndex()
            }
        }
    }

    /// The companion asked us to move an item to a new position.
    func connectionManager(_ manager: ConnectionManager, didReceiveMoveRequestForId id: String, toIndex: Int) {
        guard let fromIndex = libraryIndex(forItemId: id) else {
            logger.error("Move request for unknown id: \(id, privacy: .public)")
            return
        }

        if isMoveMode || presentedViewController != nil {
            showNotificationToast(message: "Busy on TV - try again in a moment")
            return
        }

        let clampedTarget = max(0, min(toIndex, dataSource.count - 1))
        dataSource.moveMedia(from: fromIndex, to: clampedTarget)
    }

    /// The companion saved a drag-and-drop arrangement. Apply the full new order at once.
    func connectionManager(_ manager: ConnectionManager, didReceiveReorderRequest orderedIds: [String]) {
        if isMoveMode || presentedViewController != nil {
            showNotificationToast(message: "Busy on TV - try again in a moment")
            return
        }
        dataSource.applyOrder(orderedIds: orderedIds)
    }

    /// The companion changed a per-item video setting (loop / mute).
    func connectionManager(_ manager: ConnectionManager, didReceiveVideoSettingForId id: String,
                           isLooping: Bool?, isMuted: Bool?) {
        guard let index = libraryIndex(forItemId: id), let path = dataSource.getPath(at: index) else {
            logger.error("Video setting for unknown id: \(id, privacy: .public)")
            return
        }

        let item = MediaItem(path: path)
        guard item.isVideo else { return }

        if let isLooping = isLooping {
            viewModel.updateVideoSetting(for: item, keyPath: \.isLooping, value: isLooping)
        }
        if let isMuted = isMuted {
            viewModel.updateVideoSetting(for: item, keyPath: \.isMuted, value: isMuted)
        }

        // If this video is the one playing fullscreen, apply the change live.
        if !isInGridMode, isVideo, index == dataSource.currentIndex {
            applySettingsToCurrentVideo()
        }

        // The path list didn't change, so push a fresh manifest to update the companion.
        Task { @MainActor in
            self.connectionManager?.librarySync?.librarySettingsDidChange()
        }
    }

    /// A purged item was re-sent from the companion: the fresh file was just added via
    /// the normal image/video path. Drop the ledger entry and move the new item back to
    /// the slot the original occupied.
    func connectionManager(_ manager: ConnectionManager, didRestoreItemForLedgerId ledgerId: String, newPath: String) {
        let entry = dataSource.unavailableLedger.remove(id: ledgerId)

        // Locate the freshly added item by its new file name.
        let newId = URL(fileURLWithPath: newPath).lastPathComponent
        if let fromIndex = libraryIndex(forItemId: newId), let entry = entry {
            let target = max(0, min(entry.lastIndex, dataSource.count - 1))
            if target != fromIndex {
                dataSource.moveMedia(from: fromIndex, to: target)
            }
        }

        // moveMedia/addMedia already nudge the manifest, but rebroadcast explicitly so the
        // dropped ledger entry is reflected even if nothing in the path list changed.
        Task { @MainActor in
            self.connectionManager?.librarySync?.librarySettingsDidChange()
        }
        logger.info("Restored item \(ledgerId, privacy: .public) as \(newId, privacy: .public)")
    }

    /// Finds the data-source index for an item id (file name), or nil if not present.
    private func libraryIndex(forItemId id: String) -> Int? {
        for index in 0..<dataSource.count {
            if let path = dataSource.getPath(at: index),
               URL(fileURLWithPath: path).lastPathComponent == id {
                return index
            }
        }
        return nil
    }

    func connectionManager(_ manager: ConnectionManager, didReceiveVideoAt path: String) {
        let startTime = Date()
        self.logger.info("Received video at path: \(path)")

        // Verify file exists and is readable
        let fileManager = FileManager.default
        if fileManager.fileExists(atPath: path) {
            do {
                let attributes = try fileManager.attributesOfItem(atPath: path)
                let fileSize = attributes[.size] as? UInt64 ?? 0
                self.logger.info("Video file exists, size: \(ByteCountFormatter.string(fromByteCount: Int64(fileSize), countStyle: .file))")
            } catch {
                self.logger.error("Failed to get video file attributes: \(error)")
            }
        } else {
            self.logger.error("Video file does not exist at path: \(path)")
        }

        // Check if we're in move mode or showing a menu - if so, queue the content
        if isMoveMode || presentedViewController != nil {
            logger.info("Queuing received video as app is in move mode or settings: \(path)")
            queuedContent.append((path: path, isVideo: true))

            // Show a subtle notification that content was received but queued
            showNotificationToast(message: "New video received (will be added when ready)")
            return
        }

        // Add the newly received video using data source
        dataSource.addMedia(at: path)

        let endTime = Date()
        let duration = endTime.timeIntervalSince(startTime)
        self.logger.info("Added new video via data source in \(String(format: "%.3f", duration))s")
    }

    // MARK: - Bundle Loading

    /// Loads video files from the Videos folder in the app bundle
    func loadVideosFromBundle() {
        guard let videosURL = Bundle.main.resourceURL?.appendingPathComponent("Videos") else { return }
        let fileManager = FileManager.default

        // Load videos from main Videos folder
        logger.debug("Looking for videos in: \(videosURL.path, privacy: .public)")
        if let files = try? fileManager.contentsOfDirectory(at: videosURL, includingPropertiesForKeys: nil) {
            for file in files {
                let ext = file.pathExtension.lowercased()
                if ext == "mp4" || ext == "mov" {
                    let path = file.path
                    logger.debug("Adding video to dataSource: \(path, privacy: .public)")
                    dataSource.addMedia(at: path)
                }
            }
        } else {
            logger.debug("No files found in Videos folder")
        }

        // Also load videos from Videos/Loop subfolder
        let loopURL = videosURL.appendingPathComponent("Loop")
        logger.debug("Looking for videos in Loop folder: \(loopURL.path, privacy: .public)")
        if let loopFiles = try? fileManager.contentsOfDirectory(at: loopURL, includingPropertiesForKeys: nil) {
            for file in loopFiles {
                let ext = file.pathExtension.lowercased()
                if ext == "mp4" || ext == "mov" {
                    let path = file.path
                    logger.debug("Adding loop video to dataSource: \(path, privacy: .public)")
                    dataSource.addMedia(at: path)
                }
            }
        } else {
            logger.debug("No files found in Videos/Loop folder")
        }
    }

    /// Loads image files from the Images folder in the app bundle
    func loadImagesFromBundle() {
        guard let imagesURL = Bundle.main.resourceURL?.appendingPathComponent("Images") else { return }
        let fileManager = FileManager.default
        logger.debug("Looking for images in: \(imagesURL.path, privacy: .public)")
        if let files = try? fileManager.contentsOfDirectory(at: imagesURL, includingPropertiesForKeys: nil) {
            for file in files {
                let ext = file.pathExtension.lowercased()
                if ext == "jpg" || ext == "jpeg" || ext == "png" {
                    let path = file.path
                    logger.debug("Adding image to dataSource: \(path, privacy: .public)")
                    dataSource.addMedia(at: path)
                }
            }
        } else {
            logger.debug("No files found in Images folder")
        }
    }

    // MARK: - Queued Content

    /// Process any content that was queued while in move mode or settings
    func processQueuedContent() {
        // Check if we're already processing the queue or if there's nothing to process
        guard !self.isProcessingQueue, !self.queuedContent.isEmpty else {
            return
        }

        // Don't process if we're still in move mode or have a presented view controller
        if self.isMoveMode || self.presentedViewController != nil {
            self.logger.info("Skipping queue processing as app is still in move mode or settings")
            return
        }

        self.logger.info("Processing queued content - \(self.queuedContent.count) items")
        self.isProcessingQueue = true

        // Process all queued items
        var addedCount = 0
        var lastAddedIndex = -1

        for queuedItem in self.queuedContent {
            // Add the item via data source
            self.dataSource.addMedia(at: queuedItem.path)
            lastAddedIndex = self.dataSource.count - 1
            addedCount += 1
        }

        // Clear the queue
        self.queuedContent.removeAll()

        // Only update UI if we added items
        if addedCount > 0 {
            // If we were showing the empty state, hide it and switch to grid view
            if view.subviews.contains(emptyStateView) {
                hideEmptyState()
            }

            // Reload the grid with all the new content (delegate will handle this)
            // But force it just in case
            self.gridView.reloadData()

            // Select the last added item using SimpleSelectionManager
            if lastAddedIndex >= 0 {
                let indexPath = IndexPath(item: lastAddedIndex, section: 0)

                // Use async dispatch to ensure reload is complete before selection
                DispatchQueue.main.async {
                    self.simpleSelectionManager.selectItem(at: indexPath)
                    self.dataSource.setCurrentIndex(lastAddedIndex)

                    // Ensure visibility
                    if !self.gridView.indexPathsForVisibleItems.contains(indexPath) {
                        self.gridView.scrollToItem(at: indexPath, at: .centeredVertically, animated: true)
                    }

                    // Validate selection state after all operations
                    self.simpleSelectionManager.validateSelectionState()

                    // Ensure focus is updated
                    self.setNeedsFocusUpdate()
                    self.updateFocusIfNeeded()
                }
            }

            // Show a notification with the count of added items
            let itemText = addedCount == 1 ? "item" : "items"
            self.showNotificationToast(message: "\(addedCount) new \(itemText) added")
        }

        self.isProcessingQueue = false
    }
}
