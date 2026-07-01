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

        guard isConnected() else {
            showTemporaryStatus("Added. It'll upload to your Apple TV once you connect.")
            return
        }

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
