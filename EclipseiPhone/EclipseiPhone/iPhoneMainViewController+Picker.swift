// iPhoneMainViewController+Picker.swift
import UIKit
import PhotosUI
import UniformTypeIdentifiers
import AVFoundation
import os

// MARK: - PHPickerViewControllerDelegate

extension iPhoneMainViewController: PHPickerViewControllerDelegate {
    func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
        // Reset picker flag
        isShowingPicker = false
        picker.dismiss(animated: true)

        guard let provider = results.first?.itemProvider else { return }

        if provider.hasItemConformingToTypeIdentifier(UTType.movie.identifier) {
            handlePickedVideo(provider)
        } else if provider.canLoadObject(ofClass: UIImage.self) {
            handlePickedImage(provider)
        }
    }

    private func handlePickedVideo(_ provider: NSItemProvider) {
        statusLabel.text = "Loading video..."
        statusLabel.alpha = 1.0

        // PHPicker provides the file in a temporary location that is removed when the
        // completion returns, so copy it into our sandbox inside the callback.
        provider.loadFileRepresentation(forTypeIdentifier: UTType.movie.identifier) { [weak self] url, _ in
            guard let self = self else { return }
            guard let url = url, let localVideoURL = self.copyPickedVideoToSandbox(url) else {
                DispatchQueue.main.async {
                    self.statusLabel.alpha = 0
                    self.showAlert(title: "Video Error", message: "Could not access the selected video. Please try again.")
                }
                return
            }

            Task {
                let validationResult = await MediaValidator.validateVideo(at: localVideoURL)
                await MainActor.run {
                    self.statusLabel.text = "Validating video..."
                    switch validationResult {
                    case .valid:
                        self.statusLabel.alpha = 0
                        self.showVideoThumbnailPreview(for: localVideoURL)
                    case .invalid(let reason):
                        self.statusLabel.alpha = 0
                        self.cleanupTempFile(at: localVideoURL)
                        self.showAlert(title: "Video Rejected", message: reason)
                    }
                }
            }
        }
    }

    private func handlePickedImage(_ provider: NSItemProvider) {
        provider.loadObject(ofClass: UIImage.self) { [weak self] object, _ in
            guard let self = self else { return }
            guard let image = object as? UIImage else {
                DispatchQueue.main.async {
                    self.showAlert(title: "Image Error", message: "Could not load the selected image. Please try again.")
                }
                return
            }

            DispatchQueue.main.async {
                if MediaValidator.imageNeedsDownscaling(image) {
                    if let description = MediaValidator.getDownscalingDescription(for: image) {
                        self.showTemporaryStatus(description, duration: 4.0)
                    }
                }

                // Downscale image if needed and send directly with default fit-to-fill centered
                let optimizedImage = MediaValidator.downscaleImage(image)
                self.sendImageToAppleTV(optimizedImage)
            }
        }
    }
}

// MARK: - VideoThumbnailPreviewDelegate

extension iPhoneMainViewController: VideoThumbnailPreviewDelegate {
    func videoThumbnailPreview(_ controller: VideoThumbnailPreviewViewController, didFinishWithVideoURL videoURL: URL, selectedThumbnail: UIImage) {
        controller.dismiss(animated: true) { [weak self] in
            // Save the custom thumbnail for later use
            self?.saveCustomThumbnail(selectedThumbnail, for: videoURL)
            // Send the video to Apple TV
            self?.sendMediaToAppleTV(videoURL)
        }
    }

    func videoThumbnailPreviewDidCancel(_ controller: VideoThumbnailPreviewViewController) {
        controller.dismiss(animated: true)
    }

    private func saveCustomThumbnail(_ thumbnail: UIImage, for videoURL: URL) {
        // Save the custom thumbnail to a temporary location
        // We'll use this when the video is received on the Apple TV side
        guard let thumbnailData = thumbnail.jpegData(compressionQuality: 0.8) else { return }

        let tempDir = FileManager.default.temporaryDirectory
        let thumbnailFileName = "thumbnail_\(videoURL.lastPathComponent).jpg"
        let thumbnailURL = tempDir.appendingPathComponent(thumbnailFileName)

        do {
            try thumbnailData.write(to: thumbnailURL)
            // Store the thumbnail path associated with the video
            UserDefaults.standard.set(thumbnailURL.path, forKey: "customThumbnail_\(videoURL.lastPathComponent)")
        } catch {
            logger.error("Failed to save custom thumbnail: \(error.localizedDescription)")
        }
    }
}
