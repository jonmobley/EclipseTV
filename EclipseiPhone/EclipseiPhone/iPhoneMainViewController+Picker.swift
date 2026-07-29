//
//  iPhoneMainViewController+Picker.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

// iPhoneMainViewController+Picker.swift
import UIKit
import PhotosUI
import UniformTypeIdentifiers
import AVFoundation
import os

// MARK: - UIDocumentPickerDelegate

extension iPhoneMainViewController: UIDocumentPickerDelegate {
    func documentPicker(_ controller: UIDocumentPickerViewController,
                        didPickDocumentsAt urls: [URL]) {
        isShowingPicker = false
        guard !urls.isEmpty else { return }
        switch pendingDocumentKind {
        case .pdf:
            guard let url = urls.first else { return }
            do {
                let doc = try PDFStore.shared.add(from: url, title: nil)
                libraryViewController.presentPDF(doc)
            } catch {
                showAlert(title: "Couldn't Add PDF", message: error.localizedDescription)
            }
        case .audio:
            Task {
                var failures = 0
                var lastError: Error?
                for audioURL in urls {
                    do {
                        _ = try await AudioStore.shared.add(from: audioURL, title: nil)
                    } catch {
                        failures += 1
                        lastError = error
                    }
                }
                guard failures > 0, let lastError else { return }
                let message: String
                if urls.count == 1 {
                    message = lastError.localizedDescription
                } else {
                    let added = urls.count - failures
                    message = "Added \(added) of \(urls.count). \(lastError.localizedDescription)"
                }
                showAlert(title: "Couldn't Add Music", message: message)
            }
        }
    }

    func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
        isShowingPicker = false
    }
}

// MARK: - PHPickerViewControllerDelegate

extension iPhoneMainViewController: PHPickerViewControllerDelegate {
    func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
        // Reset picker flag
        isShowingPicker = false
        picker.dismiss(animated: true)

        guard !results.isEmpty else {
            // User cancelled: drop any pending re-send so a later normal send isn't
            // mistaken for a restore.
            connectionManager.pendingRestoreId = nil
            pendingAlbumId = nil
            pendingSlideshowShowId = nil
            pendingSlideshowName = nil
            pendingLogoPick = false
            return
        }

        if pendingLogoPick {
            let provider = results[0].itemProvider
            guard provider.canLoadObject(ofClass: UIImage.self) else {
                pendingLogoPick = false
                showAlert(title: "Image Error", message: "Choose a photo for the Logo.")
                return
            }
            handlePickedLogo(provider)
            return
        }

        // Slideshow create: images only, skip crop, group as one tile.
        if pendingSlideshowShowId != nil {
            importPickedMediaBatch(results)
            return
        }

        // Multi-select Import: skip crop/confirm and ingest directly.
        if results.count > 1 {
            importPickedMediaBatch(results)
            return
        }

        let provider = results[0].itemProvider
        if provider.hasItemConformingToTypeIdentifier(UTType.movie.identifier) {
            handlePickedVideo(provider)
        } else if provider.canLoadObject(ofClass: UIImage.self) {
            handlePickedImage(provider)
        }
    }

    private func handlePickedLogo(_ provider: NSItemProvider) {
        provider.loadObject(ofClass: UIImage.self) { [weak self] object, _ in
            guard let self else { return }
            DispatchQueue.main.async {
                self.pendingLogoPick = false
                guard let image = object as? UIImage else {
                    self.showAlert(
                        title: "Image Error",
                        message: "Could not load the selected image. Please try again."
                    )
                    return
                }
                LogoStore.shared.save(image)
                self.libraryViewController.presentLogoLive()
            }
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
                // Vertical + non-9:16 → crop first; otherwise confirm preview.
                self.presentImageAddFlow(for: image)
            }
        }
    }
}

// MARK: - AspectCropDelegate

extension iPhoneMainViewController: AspectCropDelegate {
    func aspectCrop(_ controller: AspectCropViewController,
                    didFinishWith image: UIImage,
                    cropRectInSource: CGRect) {
        if let videoURL = pendingVideoCropURL {
            let thumb = pendingVideoThumbnail ?? image
            let previewSize = pendingVideoCropPreviewSize ?? image.size
            let editId = pendingEditItemId
            pendingVideoCropURL = nil
            pendingVideoThumbnail = nil
            pendingVideoCropPreviewSize = nil
            controller.dismiss(animated: true) { [weak self] in
                self?.finishVerticalVideoCrop(
                    sourceURL: videoURL,
                    previewSize: previewSize,
                    cropRectInPreview: cropRectInSource,
                    thumbnail: thumb,
                    croppedStill: image,
                    replacingItemId: editId
                )
            }
            return
        }

        if let editId = pendingEditItemId {
            pendingEditItemId = nil
            controller.dismiss(animated: true) { [weak self] in
                self?.replaceEditedImage(image, itemId: editId)
            }
            return
        }

        // Crop confirm is the add decision — skip the second "Add to library?" prompt.
        controller.dismiss(animated: true) { [weak self] in
            self?.sendImageToAppleTV(image)
        }
    }

    func aspectCropDidCancel(_ controller: AspectCropViewController) {
        // Editing uses the library file as the crop source — never delete it on cancel.
        if pendingEditItemId == nil, let videoURL = pendingVideoCropURL {
            cleanupTempFile(at: videoURL)
        }
        pendingVideoCropURL = nil
        pendingVideoThumbnail = nil
        pendingVideoCropPreviewSize = nil
        pendingEditItemId = nil
        controller.dismiss(animated: true) { [weak self] in
            self?.connectionManager.pendingRestoreId = nil
        }
    }

    /// Scales the preview crop into video display pixels, exports, then adds or replaces.
    private func finishVerticalVideoCrop(sourceURL: URL,
                                         previewSize: CGSize,
                                         cropRectInPreview: CGRect,
                                         thumbnail: UIImage,
                                         croppedStill: UIImage,
                                         replacingItemId: String?) {
        guard previewSize.width > 0, previewSize.height > 0 else {
            showTemporaryStatus("Couldn't crop that video. Try another.")
            if replacingItemId == nil { cleanupTempFile(at: sourceURL) }
            pendingEditItemId = nil
            return
        }

        showTemporaryStatus("Cropping video…", duration: 60)
        Task { @MainActor in
            guard let videoSize = await MediaAspect.videoDisplaySize(at: sourceURL) else {
                self.showTemporaryStatus("Couldn't crop that video. Try another.")
                if replacingItemId == nil { self.cleanupTempFile(at: sourceURL) }
                self.pendingEditItemId = nil
                return
            }

            let scaleX = videoSize.width / previewSize.width
            let scaleY = videoSize.height / previewSize.height
            let videoCrop = CGRect(
                x: cropRectInPreview.origin.x * scaleX,
                y: cropRectInPreview.origin.y * scaleY,
                width: cropRectInPreview.size.width * scaleX,
                height: cropRectInPreview.size.height * scaleY
            )

            do {
                let croppedURL = try await VideoCropExporter.export(
                    sourceURL: sourceURL, cropRect: videoCrop
                )
                if replacingItemId == nil {
                    self.cleanupTempFile(at: sourceURL)
                }
                let croppedThumb = MediaAspect.crop(
                    MediaAspect.normalized(thumbnail),
                    to: self.scaledRect(
                        cropRectInPreview, from: previewSize, to: thumbnail.size
                    )
                ) ?? croppedStill

                if let editId = replacingItemId {
                    self.pendingEditItemId = nil
                    self.statusLabel.alpha = 0
                    self.replaceEditedVideo(
                        at: croppedURL, itemId: editId, thumbnail: croppedThumb
                    )
                } else {
                    self.currentTempFileURL = croppedURL
                    self.saveCustomThumbnail(croppedThumb, for: croppedURL)
                    self.addMedia(
                        localURL: croppedURL, isVideo: true,
                        thumbnail: croppedThumb, duration: 0
                    )
                }
            } catch {
                self.showTemporaryStatus("Couldn't crop that video. Try another.")
                if replacingItemId == nil { self.cleanupTempFile(at: sourceURL) }
                self.pendingEditItemId = nil
            }
        }
    }

    private func scaledRect(_ rect: CGRect, from fromSize: CGSize, to toSize: CGSize) -> CGRect {
        guard fromSize.width > 0, fromSize.height > 0 else { return rect }
        return CGRect(
            x: rect.origin.x * (toSize.width / fromSize.width),
            y: rect.origin.y * (toSize.height / fromSize.height),
            width: rect.size.width * (toSize.width / fromSize.width),
            height: rect.size.height * (toSize.height / fromSize.height)
        )
    }
}

// MARK: - ImagePreviewDelegate

extension iPhoneMainViewController: ImagePreviewDelegate {
    func imagePreview(_ controller: ImagePreviewViewController, didConfirm image: UIImage) {
        controller.dismiss(animated: true) { [weak self] in
            guard let self = self else { return }
            if MediaValidator.imageNeedsDownscaling(image) {
                if let description = MediaValidator.getDownscalingDescription(for: image) {
                    self.showTemporaryStatus(description, duration: 4.0)
                }
            }

            // Downscale if needed and send with default fit-to-fill centered.
            let optimizedImage = MediaValidator.downscaleImage(image)
            self.sendImageToAppleTV(optimizedImage)
        }
    }

    func imagePreviewDidCancel(_ controller: ImagePreviewViewController) {
        controller.dismiss(animated: true) { [weak self] in
            // Backing out of a re-send must clear the pending flag so a later normal
            // send isn't mistaken for a restore.
            self?.connectionManager.pendingRestoreId = nil
        }
    }
}

// MARK: - VideoThumbnailPreviewDelegate

extension iPhoneMainViewController: VideoThumbnailPreviewDelegate {
    func videoThumbnailPreview(_ controller: VideoThumbnailPreviewViewController,
                               didFinishWithVideoURL videoURL: URL,
                               selectedThumbnail: UIImage) {
        controller.dismiss(animated: true) { [weak self] in
            self?.continueVideoAdd(videoURL: videoURL, thumbnail: selectedThumbnail)
        }
    }

    func videoThumbnailPreviewDidCancel(_ controller: VideoThumbnailPreviewViewController) {
        controller.dismiss(animated: true)
    }

    /// Adds the video, or opens a 9:16 crop first when Vertical mode requires it.
    private func continueVideoAdd(videoURL: URL, thumbnail: UIImage) {
        guard MediaAspect.requiresVerticalCrop else {
            finishVideoAdd(videoURL: videoURL, thumbnail: thumbnail)
            return
        }

        showTemporaryStatus("Preparing crop…", duration: 30)
        Task { @MainActor in
            let size = await MediaAspect.videoDisplaySize(at: videoURL)
            guard let size, !MediaAspect.matches(size, target: MediaAspect.vertical) else {
                self.statusLabel.alpha = 0
                self.finishVideoAdd(videoURL: videoURL, thumbnail: thumbnail)
                return
            }

            let frame = await VideoCropExporter.previewFrame(at: videoURL) ?? thumbnail
            self.statusLabel.alpha = 0
            self.pendingVideoCropURL = videoURL
            self.pendingVideoThumbnail = thumbnail
            self.pendingVideoCropPreviewSize = MediaAspect.normalized(frame).size
            let cropper = AspectCropViewController(
                image: frame,
                targetAspect: MediaAspect.vertical,
                instruction: "Drag and pinch to frame your Vertical video crop"
            )
            cropper.delegate = self
            cropper.modalPresentationStyle = .overFullScreen
            self.presentationAnchor.present(cropper, animated: true)
        }
    }

    private func finishVideoAdd(videoURL: URL, thumbnail: UIImage) {
        saveCustomThumbnail(thumbnail, for: videoURL)
        addMedia(localURL: videoURL, isVideo: true, thumbnail: thumbnail, duration: 0)
    }

    func saveCustomThumbnail(_ thumbnail: UIImage, for videoURL: URL) {
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
