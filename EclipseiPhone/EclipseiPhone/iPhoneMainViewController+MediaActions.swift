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

    /// Opens the video frame picker to replace an existing item’s poster thumbnail.
    func beginChangeVideoThumbnail(forItemId id: String) {
        guard let item = TVLibraryStore.shared.items.first(where: { $0.id == id }),
              item.isVideo,
              let url = LocalMediaStore.shared.localURL(forId: id) else {
            showTemporaryStatus("Couldn't open that video.")
            return
        }
        pendingThumbnailEditItemId = id
        showVideoThumbnailPreview(for: url)
    }

    /// Writes a new poster for an existing video (phone tile + optional EclipseTV push).
    func applyVideoThumbnail(_ thumbnail: UIImage, forItemId id: String, videoURL: URL) {
        TVLibraryStore.shared.setThumbnail(thumbnail, forId: id)
        saveCustomThumbnail(thumbnail, for: videoURL)
        _ = connectionManager.sendCustomVideoThumbnail(thumbnail, videoFileName: videoURL.lastPathComponent)
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
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

    /// System menu for the header "+" control.
    ///
    /// Library and History sit at the top; Image / Video / Website / Slideshow /
    /// Live Poll / PDF follow under a divider. In a Show, imports add non-live
    /// cards; Website opens the compose sheet (History is reachable from there).
    func makeAddMenu() -> UIMenu {
        let albumId = libraryViewController.openShowId
        let library = UIAction(
            title: "Media Library",
            image: UIImage(systemName: "square.grid.2x2")
        ) { [weak self] _ in
            self?.presentMediaLibrary()
        }
        let history = UIAction(
            title: "History",
            image: UIImage(systemName: "clock.arrow.circlepath")
        ) { [weak self] _ in
            self?.presentPages()
        }
        let image = UIAction(
            title: "Image",
            image: UIImage(systemName: "photo")
        ) { [weak self] _ in
            self?.pendingSlideshowShowId = nil
            self?.pendingSlideshowName = nil
            self?.pendingAlbumId = albumId
            self?.showImagePicker()
        }
        let video = UIAction(
            title: "Video",
            image: UIImage(systemName: "video")
        ) { [weak self] _ in
            self?.pendingSlideshowShowId = nil
            self?.pendingSlideshowName = nil
            self?.pendingAlbumId = albumId
            self?.showVideoPicker()
        }
        let website = UIAction(
            title: "Website",
            image: UIImage(systemName: "safari")
        ) { [weak self] _ in
            if let albumId {
                self?.promptAddWebsite(toAlbumId: albumId)
            } else {
                self?.promptAddWebsite()
            }
        }
        let slideshow = UIAction(
            title: "Slideshow",
            image: UIImage(systemName: "rectangle.stack.badge.play")
        ) { [weak self] _ in
            guard let albumId else { return }
            self?.promptNewSlideshow(inShowId: albumId)
        }
        if albumId == nil {
            slideshow.attributes = .disabled
        }
        let livePoll = UIAction(
            title: "Live Poll",
            image: UIImage(systemName: "chart.bar.fill")
        ) { [weak self] _ in
            guard let albumId else { return }
            self?.libraryViewController.addLivePollCard(toShowId: albumId)
        }
        if albumId == nil {
            livePoll.attributes = .disabled
        }
        let pdf = UIAction(
            title: "PDF",
            image: UIImage(systemName: "doc.richtext")
        ) { [weak self] _ in
            self?.pendingAlbumId = albumId
            self?.showPDFPicker()
        }
        let imports = UIMenu(
            title: "",
            options: .displayInline,
            children: [image, video, website, slideshow, livePoll, pdf]
        )
        // In a Show, Website opens the compose sheet (History is on that sheet).
        // Home keeps History for manage / open.
        let browse: [UIMenuElement] = albumId == nil ? [library, history] : [library]
        var children: [UIMenuElement] = [
            UIMenu(title: "", options: .displayInline, children: browse),
            imports
        ]
        if let albumId,
           let album = LocalAlbumStore.shared.album(id: albumId) {
            let missing = album.missingToolTokens
            if !missing.isEmpty {
                let restoreActions: [UIAction] = missing.compactMap { token in
                    guard let title = ShowToolToken.title(for: token),
                          let image = ShowToolToken.systemImage(for: token)
                    else { return nil }
                    return UIAction(
                        title: title,
                        image: UIImage(systemName: image)
                    ) { _ in
                        LocalAlbumStore.shared.showTool(token, albumId: albumId)
                    }
                }
                if !restoreActions.isEmpty {
                    children.append(UIMenu(
                        title: "",
                        options: .displayInline,
                        children: restoreActions
                    ))
                }
            }
        }
        return UIMenu(children: children)
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

    /// Creates a Show in the active Display Mode (Landscape by default) and opens it.
    func promptNewAlbum() {
        presentShowNamePrompt(
            title: "New Show",
            confirmTitle: "Create"
        ) { [weak self] name in
            self?.createLocalAlbum(
                name: name,
                orientation: ExternalOutputSettings.orientation
            )
        }
    }

    /// Creates the Show in `orientation` and opens it (switches Display Mode if needed).
    func createLocalAlbum(name: String, orientation: ExternalOutputOrientation) {
        do {
            let show = try LocalAlbumStore.shared.create(name: name, orientation: orientation)
            // `openLocalAlbum` switches Display Mode when the Show's layout differs.
            libraryViewController.openLocalAlbum(id: show.id)
        } catch {
            showAlert(title: "Couldn't Create Show", message: error.localizedDescription)
        }
    }

    /// Opens the document picker to import a PDF into the library / open Show.
    func showPDFPicker() {
        pendingDocumentKind = .pdf
        if pendingAlbumId == nil {
            pendingAlbumId = libraryViewController.openShowId
        }
        let picker = UIDocumentPickerViewController(
            forOpeningContentTypes: [.pdf],
            asCopy: true
        )
        picker.delegate = self
        picker.allowsMultipleSelection = false
        presentSystemPicker(picker)
    }

    /// Opens the document picker to import audio into the Music library.
    func showAudioPicker() {
        pendingDocumentKind = .audio
        let picker = AddMusicDocumentPicker()
        picker.delegate = self
        presentSystemPicker(picker)
    }

    /// Creates an empty playlist from the Home dropdown Music menu.
    func promptNewPlaylist() {
        let alert = UIAlertController(
            title: "New Playlist", message: nil, preferredStyle: .alert
        )
        alert.addTextField {
            $0.placeholder = "Name"
            $0.autocapitalizationType = .words
            UserDisplayName.configureTextField($0)
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

    /// Compose-first Website add (URL + Title, History suggestions).
    func promptAddWebsite() {
        presentAddWebsite(targetShowId: nil)
    }

    /// Compose sheet; Add / a History suggestion joins the Show as a card.
    func promptAddWebsite(toAlbumId albumId: UUID) {
        presentAddWebsite(targetShowId: albumId)
    }

    /// Presents or reuses the Website compose sheet (one at a time).
    private func presentAddWebsite(targetShowId: UUID?) {
        let reveal: (UUID) -> Void = { [weak self] pageId in
            self?.libraryViewController.revealAddedShowMember(id: pageId.uuidString)
        }
        if let open = openController(ofType: AddWebsiteViewController.self) {
            open.onAdded = reveal
            open.navigationController?.popToViewController(open, animated: true)
            return
        }
        if let history = openController(ofType: WebPagesViewController.self),
           let nav = history.navigationController {
            history.onAdded = reveal
            let compose = AddWebsiteViewController(targetShowId: targetShowId)
            compose.onAdded = reveal
            nav.pushViewController(compose, animated: true)
            return
        }
        let compose = AddWebsiteViewController(targetShowId: targetShowId)
        compose.onAdded = reveal
        let nav = UINavigationController(rootViewController: compose)
        nav.modalPresentationStyle = .formSheet
        presentationAnchor.present(nav, animated: true)
    }

    /// Topmost presented controller so sheets/pickers appear above album modals.
    var presentationAnchor: UIViewController {
        var top: UIViewController = self
        while let presented = top.presentedViewController {
            top = presented
        }
        return top
    }

    /// Presents a system picker above whatever is already on screen — one at a time.
    ///
    /// Pickers go through `presentationAnchor`, which walks *past* an open picker, so
    /// UIKit's own refusal to present twice never fires: a second tap on a control that
    /// opens one (the Background tile with no image saved yet, a Show's add tile) stacks a
    /// second copy, and dismissing it reveals the first still sitting there. Bailing
    /// also leaves `isShowingPicker` and the pending-intent flags as the first tap set
    /// them, which is what the picker that is actually open still needs.
    private func presentSystemPicker(_ picker: UIViewController) {
        guard !isAlreadyOpen(PHPickerViewController.self),
              !isAlreadyOpen(UIDocumentPickerViewController.self) else { return }
        // Keeps the Apple TV connection alive while the picker is up.
        isShowingPicker = true
        presentationAnchor.present(picker, animated: true)
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
            UserDisplayName.configureTextField(field)
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
        var config = PHPickerConfiguration()
        config.selectionLimit = 0
        config.filter = .any(of: [.images, .videos])
        let picker = PHPickerViewController(configuration: config)
        picker.delegate = self
        presentSystemPicker(picker)
    }

    /// Images-only multi-select for creating a Slideshow.
    func showSlideshowImagePicker() {
        var config = PHPickerConfiguration()
        config.selectionLimit = 0
        config.filter = .images
        let picker = PHPickerViewController(configuration: config)
        picker.delegate = self
        presentSystemPicker(picker)
    }

    func showImagePicker() {
        var config = PHPickerConfiguration()
        config.selectionLimit = 1
        config.filter = .images
        let picker = PHPickerViewController(configuration: config)
        picker.delegate = self
        presentSystemPicker(picker)
    }

    /// Opens Photos to pick a still for the home-grid Background tile.
    func showLogoPicker() {
        pendingLogoPick = true
        pendingScreensaverPick = false
        showImagePicker()
    }

    /// Opens Photos to replace Screensaver with an image or video.
    func showScreensaverPicker() {
        pendingScreensaverPick = true
        pendingLogoPick = false
        var config = PHPickerConfiguration()
        config.selectionLimit = 1
        config.filter = .any(of: [.images, .videos])
        let picker = PHPickerViewController(configuration: config)
        picker.delegate = self
        presentSystemPicker(picker)
    }

    func showVideoPicker() {
        var config = PHPickerConfiguration()
        config.selectionLimit = 1
        config.filter = .videos
        let picker = PHPickerViewController(configuration: config)
        picker.delegate = self
        presentSystemPicker(picker)
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
        // Large stills encode off the main thread; no status toast — add is local-first
        // and Multipeer progress (when linked) already surfaces via transfer UI.
        let largestSide = max(image.size.width, image.size.height)
        let isLargeImage = largestSide > 3840
        let processQueue = isLargeImage ? DispatchQueue.global(qos: .userInitiated) : DispatchQueue.main

        processQueue.async {
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
                self.addMedia(localURL: fileURL, isVideo: false, thumbnail: image, duration: 0)
            }
        }
    }
}
