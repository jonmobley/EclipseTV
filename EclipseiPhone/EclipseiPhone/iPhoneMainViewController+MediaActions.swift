//
//  iPhoneMainViewController+MediaActions.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

// iPhoneMainViewController+MediaActions.swift
import UIKit
import PhotosUI
import os

// MARK: - Media Picking & Transfer Actions

extension iPhoneMainViewController {

    /// Begins re-sending a purged Apple TV item: flags the next transfer as a restore
    /// (so the TV puts it back in its original slot) and opens the existing picker.
    /// Restoring into a specific slot is a TV-side operation, so it still requires a live
    /// connection.
    func beginResend(forItemId id: String) {
        guard let selectedPeer = selectedPeer, connectionManager.isConnectedToPeer(selectedPeer) else {
            showTemporaryStatus("Please connect to Apple TV first")
            return
        }
        connectionManager.pendingRestoreId = id
        mediaPickerButtonTapped()
    }

    /// Opens the aspect cropper so the user can re-frame an existing library item.
    func beginEditCrop(forItemId id: String) {
        guard let item = TVLibraryStore.shared.items.first(where: { $0.id == id }) else { return }
        let target = MediaAspect.activeTarget
        let modeName = ExternalOutputSettings.isVerticalMode ? "Vertical" : "Landscape"
        let instruction = "Drag and pinch to reframe your \(modeName) crop"

        if item.isVideo {
            guard let url = LocalMediaStore.shared.localURL(forId: id) else {
                showTemporaryStatus("Couldn't edit that video.")
                return
            }
            showTemporaryStatus("Preparing crop…", duration: 30)
            Task { @MainActor in
                guard let frame = await VideoCropExporter.previewFrame(at: url) else {
                    self.showTemporaryStatus("Couldn't edit that video.")
                    return
                }
                self.statusLabel.alpha = 0
                self.pendingEditItemId = id
                self.pendingVideoCropURL = url
                self.pendingVideoThumbnail = TVLibraryStore.shared.thumbnail(for: id) ?? frame
                self.pendingVideoCropPreviewSize = MediaAspect.normalized(frame).size
                let cropper = AspectCropViewController(
                    image: frame,
                    targetAspect: target,
                    instruction: instruction,
                    confirmTitle: "Save"
                )
                cropper.delegate = self
                cropper.modalPresentationStyle = .overFullScreen
                self.present(cropper, animated: true)
            }
            return
        }

        let image: UIImage?
        if let url = LocalMediaStore.shared.localURL(forId: id) {
            image = UIImage(contentsOfFile: url.path)
        } else {
            image = TVLibraryStore.shared.thumbnail(for: id)
        }
        guard let image else {
            showTemporaryStatus("Couldn't edit that image.")
            return
        }

        pendingEditItemId = id
        let cropper = AspectCropViewController(
            image: image,
            targetAspect: target,
            instruction: instruction,
            confirmTitle: "Save"
        )
        cropper.delegate = self
        cropper.modalPresentationStyle = .overFullScreen
        present(cropper, animated: true)
    }

    /// Writes a re-cropped still over the existing library item and re-sends if linked.
    func replaceEditedImage(_ image: UIImage, itemId: String) {
        let optimized = MediaValidator.downscaleImage(image)
        guard let data = optimized.jpegData(compressionQuality: 0.85) else {
            showTemporaryStatus("Couldn't save the cropped image.")
            return
        }

        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(itemId)
        do {
            try data.write(to: tempURL, options: .atomic)
        } catch {
            showTemporaryStatus("Couldn't save the cropped image.")
            return
        }

        LocalMediaStore.shared.store(fileURL: tempURL, forId: itemId)
        TVLibraryStore.shared.setThumbnail(optimized, forId: itemId)
        refreshAirPlayIfLive(itemId: itemId)

        guard isConnected() else {
            cleanupTempFile(at: tempURL)
            return
        }

        connectionManager.pendingRestoreId = itemId
        currentTempFileURL = tempURL
        showTransferUI()
        if !connectionManager.sendImage(at: tempURL) {
            showTemporaryStatus("Failed to update image on Apple TV.")
            hideTransferUI()
            cleanupTempFile(at: tempURL)
            currentTempFileURL = nil
            connectionManager.pendingRestoreId = nil
        }
    }

    /// Writes a re-cropped video over the existing library item and re-sends if linked.
    func replaceEditedVideo(at croppedURL: URL, itemId: String, thumbnail: UIImage) {
        let namedURL = FileManager.default.temporaryDirectory.appendingPathComponent(itemId)
        try? FileManager.default.removeItem(at: namedURL)
        do {
            try FileManager.default.copyItem(at: croppedURL, to: namedURL)
        } catch {
            showTemporaryStatus("Couldn't save the cropped video.")
            cleanupTempFile(at: croppedURL)
            return
        }
        cleanupTempFile(at: croppedURL)

        LocalMediaStore.shared.store(fileURL: namedURL, forId: itemId)
        TVLibraryStore.shared.setThumbnail(thumbnail, forId: itemId)
        saveCustomThumbnail(thumbnail, for: namedURL)
        refreshAirPlayIfLive(itemId: itemId)

        guard isConnected() else {
            cleanupTempFile(at: namedURL)
            return
        }

        connectionManager.pendingRestoreId = itemId
        currentTempFileURL = namedURL
        sendMediaToAppleTV(namedURL)
    }

    /// If `itemId` is currently live, refreshes the AirPlay surface with the new file.
    private func refreshAirPlayIfLive(itemId: String) {
        guard TVLibraryStore.shared.currentId == itemId,
              let item = TVLibraryStore.shared.items.first(where: { $0.id == itemId }) else {
            return
        }
        ExternalDisplayManager.shared.present(
            .forLibraryItem(item, thumbnail: TVLibraryStore.shared.thumbnail(for: itemId))
        )
    }

    @objc func mediaPickerButtonTapped() {
        // Adding works whether or not an Apple TV is connected: offline additions are
        // shown immediately and uploaded automatically once a TV connects.
        let alertController = UIAlertController(title: nil, message: nil, preferredStyle: .actionSheet)

        // Add Image option
        alertController.addAction(UIAlertAction(title: "Image", style: .default) { [weak self] _ in
            self?.showImagePicker()
        })

        // Add Video option
        alertController.addAction(UIAlertAction(title: "Video", style: .default) { [weak self] _ in
            self?.showVideoPicker()
        })

        // Add Cancel option
        alertController.addAction(UIAlertAction(title: "Cancel", style: .cancel))

        // For iPad, we need to set the source view and rect
        if let popoverController = alertController.popoverPresentationController {
            popoverController.sourceView = headerBar.addAnchor
            popoverController.sourceRect = headerBar.addAnchor.bounds
        }

        present(alertController, animated: true)
    }

    private func showImagePicker() {
        // Keep the connection alive while the picker is presented
        isShowingPicker = true
        var config = PHPickerConfiguration()
        config.selectionLimit = 1
        config.filter = .images
        let picker = PHPickerViewController(configuration: config)
        picker.delegate = self
        present(picker, animated: true)
    }

    private func showVideoPicker() {
        // Keep the connection alive while the picker is presented
        isShowingPicker = true
        var config = PHPickerConfiguration()
        config.selectionLimit = 1
        config.filter = .videos
        let picker = PHPickerViewController(configuration: config)
        picker.delegate = self
        present(picker, animated: true)
    }

    /// Copies a picked video into the app's temporary directory so it remains accessible
    /// after the image picker delegate callback returns. Returns the local copy URL.
    func copyPickedVideoToSandbox(_ sourceURL: URL) -> URL? {
        let fileManager = FileManager.default
        let ext = sourceURL.pathExtension.isEmpty ? "mov" : sourceURL.pathExtension
        let destinationURL = fileManager.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension(ext)

        do {
            if fileManager.fileExists(atPath: destinationURL.path) {
                try fileManager.removeItem(at: destinationURL)
            }
            try fileManager.copyItem(at: sourceURL, to: destinationURL)
            return destinationURL
        } catch {
            logger.error("Failed to copy picked video to sandbox: \(error.localizedDescription)")
            return nil
        }
    }

    @objc func cancelButtonTapped() {
        // Cancel the current transfer
        connectionManager.cancelCurrentTransfer()

        // Reset UI
        hideTransferUI()

        // Show cancellation message
        statusLabel.text = "Transfer cancelled"
        UIView.animate(withDuration: 0.3) {
            self.statusLabel.alpha = 1.0
        } completion: { _ in
            // Fade out the message after a delay
            DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
                UIView.animate(withDuration: 0.3) {
                    self.statusLabel.alpha = 0
                }
            }
        }
    }

    private func showTransferUI() {
        // Show initial status
        statusLabel.text = "Preparing to send..."
        UIView.animate(withDuration: 0.3) {
            self.statusLabel.alpha = 1.0
            self.cancelButton.alpha = 1.0
        }
        cancelButton.isHidden = false

        // Disable the "+" button while sending.
        headerBar.setAddEnabled(false)
    }

    func hideTransferUI() {
        UIView.animate(withDuration: 0.3) {
            self.statusLabel.alpha = 0
            self.cancelButton.alpha = 0
        } completion: { _ in
            self.cancelButton.isHidden = true
            // Adding is always available (offline additions upload later), so re-enable
            // the "+" button regardless of connection state.
            self.headerBar.setAddEnabled(true)

            // Clean up temp file when transfer UI is hidden
            if let tempURL = self.currentTempFileURL {
                self.cleanupTempFile(at: tempURL)
                self.currentTempFileURL = nil
            }
        }
    }

    /// Adds a picked/confirmed media file to the library, then either sends it to the
    /// connected Apple TV or queues it for upload if none is connected.
    ///
    /// The item is shown in the grid right away and its full-resolution copy is kept in
    /// `LocalMediaStore` (keyed by the file name, which becomes its library id). When a TV
    /// later connects, `PendingUploadStore` entries are flushed automatically.
    func addMedia(localURL: URL, isVideo: Bool, thumbnail: UIImage?, duration: Double) {
        let id = localURL.lastPathComponent
        LocalMediaStore.shared.store(fileURL: localURL, forId: id)

        let item = LibraryItemDTO(id: id,
                                  name: id,
                                  isVideo: isVideo,
                                  duration: duration,
                                  isLooping: isVideo ? false : nil,
                                  isMuted: isVideo ? false : nil,
                                  isAvailable: true)
        TVLibraryStore.shared.addLocalItem(item, thumbnail: thumbnail)

        guard isConnected() else { return }

        if isVideo {
            sendMediaToAppleTV(localURL)
        } else {
            currentTempFileURL = localURL
            showTransferUI()
            if !connectionManager.sendImage(at: localURL) {
                showTemporaryStatus("Failed to send image. Please try again.")
                hideTransferUI()
                cleanupTempFile(at: localURL)
                currentTempFileURL = nil
            }
        }
    }

    func sendMediaToAppleTV(_ mediaURL: URL) {
        // Remove aspect ratio check: allow all videos
        // Show transfer UI
        showTransferUI()
        // Send the media
        let success = connectionManager.sendVideoData(mediaURL)
        if !success {
            // Handle failure
            statusLabel.text = "Failed to send media"
            hideTransferUI()
        }
    }

    func sendImageToAppleTV(_ image: UIImage) {
        // Show processing UI if image is large
        let largestSide = max(image.size.width, image.size.height)
        let isLargeImage = largestSide > 3840

        if isLargeImage {
            DispatchQueue.main.async {
                self.statusLabel.text = "Processing image..."
                self.statusLabel.alpha = 1.0
            }
        }

        // Process image on background queue for large images
        let processQueue = isLargeImage ? DispatchQueue.global(qos: .userInitiated) : DispatchQueue.main

        processQueue.async {
            // Save image to a temporary file
            let tempDir = FileManager.default.temporaryDirectory
            let fileName = "temp_image_\(UUID().uuidString).jpg"
            let fileURL = tempDir.appendingPathComponent(fileName)

            guard let imageData = image.jpegData(compressionQuality: 0.7) else {
                DispatchQueue.main.async {
                    self.showTemporaryStatus("Failed to prepare image for sending")
                    self.hideTransferUI()
                }
                return
            }

            do {
                try imageData.write(to: fileURL)
            } catch {
                DispatchQueue.main.async {
                    self.showTemporaryStatus("Failed to save image for sending")
                    self.hideTransferUI()
                }
                return
            }

            DispatchQueue.main.async {
                if isLargeImage {
                    self.statusLabel.text = "Sending optimized image..."
                }
                self.addMedia(localURL: fileURL, isVideo: false, thumbnail: image, duration: 0)
            }
        }
    }
}
