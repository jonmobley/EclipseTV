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
