//
//  iPhoneMainViewController+MediaActions.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

// iPhoneMainViewController+MediaActions.swift
import UIKit
import PhotosUI
import UniformTypeIdentifiers
import os

// MARK: - Media Picking & Transfer Actions

extension iPhoneMainViewController {

    /// Begins re-sending a purged Apple TV item: flags the next transfer as a restore
    /// (so the TV puts it back in its original slot) and opens the existing picker.
    /// Restoring into a specific slot is a TV-side operation, so it still requires a live
    /// connection.
    func beginResend(forItemId id: String) {
        guard let selectedPeer = selectedPeer, connectionManager.isConnectedToPeer(selectedPeer) else {
            showTemporaryStatus("Connect EclipseTV in Settings first")
            return
        }
        connectionManager.pendingRestoreId = id
        presentResendMediaPicker()
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

    /// System menu for the header "+" control: import types, then create containers.
    /// In Show mode, Image/Video add into the open Show.
    func makeAddMenu() -> UIMenu {
        var pdfChildren: [UIMenuElement] = PDFStore.shared.documents.map { doc in
            UIAction(title: doc.title, image: UIImage(systemName: "doc.richtext")) { [weak self] _ in
                self?.libraryViewController.presentPDF(doc)
            }
        }
        pdfChildren.append(UIAction(
            title: "Add PDF…",
            image: UIImage(systemName: "plus")
        ) { [weak self] _ in
            self?.showPDFPicker()
        })
        let music = UIMenu(
            title: "Music",
            image: UIImage(systemName: "music.note"),
            children: [
                UIAction(
                    title: "Open Music",
                    image: UIImage(systemName: "music.note")
                ) { [weak self] _ in
                    self?.presentAudioLibrary()
                },
                UIAction(
                    title: "New Playlist…",
                    image: UIImage(systemName: "music.note.list")
                ) { [weak self] _ in
                    self?.promptNewPlaylist()
                }
            ]
        )
        let extras = UIMenu(title: "", options: .displayInline, children: [
            UIAction(title: "Web…", image: UIImage(systemName: "globe")) { [weak self] _ in
                self?.presentPages()
            },
            UIMenu(
                title: "PDF",
                image: UIImage(systemName: "doc.richtext"),
                children: pdfChildren
            ),
            music
        ])

        if let albumId = libraryViewController.openShowId {
            let importAction = UIAction(
                title: "Import…",
                image: UIImage(systemName: "photo.on.rectangle.angled")
            ) { [weak self] _ in
                self?.pendingSlideshowShowId = nil
                self?.pendingSlideshowName = nil
                self?.pendingAlbumId = albumId
                self?.showImportPicker()
            }
            let slideshowAction = UIAction(
                title: "New Slideshow…",
                image: UIImage(systemName: "rectangle.stack.badge.play")
            ) { [weak self] _ in
                self?.promptNewSlideshow(inShowId: albumId)
            }
            let media = UIMenu(
                title: "",
                options: .displayInline,
                children: [importAction, slideshowAction]
            )
            return UIMenu(children: [media, extras])
        }

        let createShow = UIAction(
            title: "New Show…",
            image: UIImage(systemName: "rectangle.stack.badge.plus")
        ) { [weak self] _ in
            self?.promptNewAlbum()
        }
        return UIMenu(children: [createShow, extras])
    }

    /// Image/video chooser when re-sending a purged Apple TV library item.
    private func presentResendMediaPicker() {
        let sheet = UIAlertController(title: nil, message: nil, preferredStyle: .actionSheet)
        sheet.addAction(UIAlertAction(title: "Image", style: .default) { [weak self] _ in
            self?.pendingAlbumId = nil
            self?.showImagePicker()
        })
        sheet.addAction(UIAlertAction(title: "Video", style: .default) { [weak self] _ in
            self?.pendingAlbumId = nil
            self?.showVideoPicker()
        })
        sheet.addAction(UIAlertAction(title: "Cancel", style: .cancel) { [weak self] _ in
            self?.connectionManager.pendingRestoreId = nil
        })
        if let popover = sheet.popoverPresentationController {
            popover.sourceView = headerBar.addAnchor
            popover.sourceRect = headerBar.addAnchor.bounds
        }
        present(sheet, animated: true)
    }

    /// Creates a Show: name, then Display Mode; opens the new Show.
    func promptNewAlbum() {
        let alert = UIAlertController(
            title: "New Show", message: nil, preferredStyle: .alert
        )
        alert.addTextField { field in
            field.placeholder = "Show name"
            field.autocapitalizationType = .words
        }
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(UIAlertAction(title: "Next", style: .default) { [weak self] _ in
            let name = alert.textFields?.first?.text ?? ""
            let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else {
                self?.showAlert(
                    title: "Couldn't Create Show",
                    message: LocalAlbumStore.StoreError.emptyName.localizedDescription
                )
                return
            }
            self?.promptAlbumDisplayMode(name: trimmed)
        })
        present(alert, animated: true)
    }

    /// Picks Landscape or Vertical for a new Show, then creates and opens it.
    func promptAlbumDisplayMode(name: String) {
        let sheet = UIAlertController(
            title: "Display Mode",
            message: "Same presentation in both formats. Choose where this Show starts.",
            preferredStyle: .actionSheet
        )
        for mode in ExternalOutputOrientation.allCases {
            let label = mode == ExternalOutputSettings.orientation
                ? "\(mode.rawValue) (Current)"
                : mode.rawValue
            sheet.addAction(UIAlertAction(title: label, style: .default) { [weak self] _ in
                self?.createLocalAlbum(name: name, orientation: mode)
            })
        }
        sheet.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        if let popover = sheet.popoverPresentationController {
            popover.sourceView = headerBar.libraryAnchor
            popover.sourceRect = headerBar.libraryAnchor.bounds
        }
        present(sheet, animated: true)
    }

    /// Switches Display Mode if needed, creates the Show, and opens it.
    func createLocalAlbum(name: String, orientation: ExternalOutputOrientation) {
        do {
            if ExternalOutputSettings.orientation != orientation {
                ExternalOutputSettings.orientation = orientation
            }
            let show = try LocalAlbumStore.shared.create(name: name, orientation: orientation)
            libraryViewController.openLocalAlbum(id: show.id)
        } catch {
            showAlert(title: "Couldn't Create Show", message: error.localizedDescription)
        }
    }

    /// Opens the document picker to add a PDF (AirPlay only), then presents it.
    func showPDFPicker() {
        isShowingPicker = true
        pendingDocumentKind = .pdf
        let picker = UIDocumentPickerViewController(
            forOpeningContentTypes: [.pdf],
            asCopy: true
        )
        picker.delegate = self
        picker.allowsMultipleSelection = false
        presentationAnchor.present(picker, animated: true)
    }

    /// Opens the document picker to import audio into the Music library.
    func showAudioPicker() {
        isShowingPicker = true
        pendingDocumentKind = .audio
        let picker = UIDocumentPickerViewController(
            forOpeningContentTypes: AudioStore.importTypes,
            asCopy: true
        )
        picker.delegate = self
        picker.allowsMultipleSelection = false
        presentationAnchor.present(picker, animated: true)
    }

    /// Creates an empty playlist from the home `+` sheet.
    func promptNewPlaylist() {
        let alert = UIAlertController(
            title: "New Playlist", message: nil, preferredStyle: .alert
        )
        alert.addTextField {
            $0.placeholder = "Name"
            $0.autocapitalizationType = .words
        }
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(UIAlertAction(title: "Create", style: .default) { [weak self] _ in
            let name = alert.textFields?.first?.text ?? ""
            do {
                _ = try AudioPlaylistStore.shared.create(name: name)
                self?.presentAudioLibrary()
            } catch {
                self?.showAlert(
                    title: "Couldn't Create Playlist",
                    message: error.localizedDescription
                )
            }
        })
        present(alert, animated: true)
    }

    /// Adds an HTTPS page via `WebPageStore`.
    func promptAddWebsite() {
        let alert = UIAlertController(
            title: "Add Website",
            message: "HTTPS pages only.",
            preferredStyle: .alert
        )
        alert.addTextField { $0.placeholder = "Title" }
        alert.addTextField { field in
            field.placeholder = "https://…"
            field.keyboardType = .URL
            field.textContentType = .URL
            field.autocapitalizationType = .none
            field.autocorrectionType = .no
        }
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(UIAlertAction(title: "Add", style: .default) { [weak self] _ in
            let title = alert.textFields?[0].text ?? ""
            let urlString = alert.textFields?[1].text ?? ""
            do {
                _ = try WebPageStore.shared.add(title: title, urlString: urlString)
            } catch {
                self?.showAlert(title: "Couldn't Add Page", message: error.localizedDescription)
            }
        })
        present(alert, animated: true)
    }

    /// Topmost presented controller so sheets/pickers appear above album modals.
    var presentationAnchor: UIViewController {
        var top: UIViewController = self
        while let presented = top.presentedViewController {
            top = presented
        }
        return top
    }

    /// Opens Photos multi-select (images + videos) for adding into a Show.
    func promptAddMedia(toAlbumId albumId: UUID) {
        pendingSlideshowShowId = nil
        pendingSlideshowName = nil
        pendingAlbumId = albumId
        showImportPicker()
    }

    /// Names a Slideshow, then opens an images-only multi-select picker.
    func promptNewSlideshow(inShowId showId: UUID) {
        let alert = UIAlertController(
            title: "New Slideshow", message: nil, preferredStyle: .alert
        )
        alert.addTextField { field in
            field.placeholder = "Slideshow name"
            field.autocapitalizationType = .words
        }
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(UIAlertAction(title: "Next", style: .default) { [weak self] _ in
            let name = alert.textFields?.first?.text ?? ""
            let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else {
                self?.showAlert(
                    title: "Couldn't Create Slideshow",
                    message: SlideshowStore.StoreError.emptyName.localizedDescription
                )
                return
            }
            self?.pendingAlbumId = nil
            self?.pendingSlideshowShowId = showId
            self?.pendingSlideshowName = trimmed
            self?.showSlideshowImagePicker()
        })
        present(alert, animated: true)
    }

    /// Multi-select Photos picker for Show import. One item keeps crop/confirm;
    /// two or more skip crop and ingest directly.
    func showImportPicker() {
        isShowingPicker = true
        var config = PHPickerConfiguration()
        config.selectionLimit = 0
        config.filter = .any(of: [.images, .videos])
        let picker = PHPickerViewController(configuration: config)
        picker.delegate = self
        presentationAnchor.present(picker, animated: true)
    }

    /// Images-only multi-select for creating a Slideshow.
    func showSlideshowImagePicker() {
        isShowingPicker = true
        var config = PHPickerConfiguration()
        config.selectionLimit = 0
        config.filter = .images
        let picker = PHPickerViewController(configuration: config)
        picker.delegate = self
        presentationAnchor.present(picker, animated: true)
    }

    func showImagePicker() {
        // Keep the connection alive while the picker is presented
        isShowingPicker = true
        var config = PHPickerConfiguration()
        config.selectionLimit = 1
        config.filter = .images
        let picker = PHPickerViewController(configuration: config)
        picker.delegate = self
        presentationAnchor.present(picker, animated: true)
    }

    /// Opens Photos to pick a still for the home-grid Logo tile.
    func showLogoPicker() {
        pendingLogoPick = true
        showImagePicker()
    }

    func showVideoPicker() {
        // Keep the connection alive while the picker is presented
        isShowingPicker = true
        var config = PHPickerConfiguration()
        config.selectionLimit = 1
        config.filter = .videos
        let picker = PHPickerViewController(configuration: config)
        picker.delegate = self
        presentationAnchor.present(picker, animated: true)
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
    /// `LocalMediaStore` (keyed by the canonical file name, which becomes its library id).
    /// When a TV later connects, `PendingUploadStore` entries are flushed automatically.
    ///
    /// - Parameters:
    ///   - toAlbumId: Explicit Show membership. When nil, uses then clears `pendingAlbumId`.
    ///   - sendIfConnected: When false, only queues locally (batch import flushes later).
    /// Adds media to the library. Returns the canonical library id.
    @discardableResult
    func addMedia(
        localURL: URL,
        isVideo: Bool,
        thumbnail: UIImage?,
        duration: Double,
        toAlbumId: UUID? = nil,
        sendIfConnected: Bool = true
    ) -> String {
        // Match on-disk naming (UUID hyphens → underscores) so orphan recovery won't
        // re-add the same file under a second id.
        let id = LocalMediaStore.canonicalFileName(forId: localURL.lastPathComponent)
        var namedURL = localURL
        if localURL.lastPathComponent != id {
            let renamed = FileManager.default.temporaryDirectory.appendingPathComponent(id)
            try? FileManager.default.removeItem(at: renamed)
            do {
                try FileManager.default.copyItem(at: localURL, to: renamed)
                cleanupTempFile(at: localURL)
                namedURL = renamed
            } catch {
                // Fall back to the original temp path; LocalMediaStore still keys by `id`.
            }
        }

        LocalMediaStore.shared.store(fileURL: namedURL, forId: id)

        let item = LibraryItemDTO(id: id,
                                  name: id,
                                  isVideo: isVideo,
                                  duration: duration,
                                  isLooping: isVideo ? false : nil,
                                  isMuted: isVideo ? false : nil,
                                  isAvailable: true)
        TVLibraryStore.shared.addLocalItem(item, thumbnail: thumbnail)

        if let albumId = toAlbumId ?? pendingAlbumId {
            LocalAlbumStore.shared.add(itemId: id, toAlbumId: albumId)
        }
        if toAlbumId == nil {
            pendingAlbumId = nil
        }

        guard sendIfConnected, isConnected() else { return id }

        if isVideo {
            sendMediaToAppleTV(namedURL)
        } else {
            currentTempFileURL = namedURL
            showTransferUI()
            if !connectionManager.sendImage(at: namedURL) {
                showTemporaryStatus("Failed to send image. Please try again.")
                hideTransferUI()
                cleanupTempFile(at: namedURL)
                currentTempFileURL = nil
            }
        }
        return id
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
