//
//  LibraryGridViewController+Offline.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import UIKit

// MARK: - Offline Add / Browse Helpers

extension LibraryGridViewController {

    /// Confirms deletion. Pending (not-yet-synced) items can be removed locally even
    /// while offline; TV-backed items still require a live connection to delete.
    func confirmDelete(id: String, name: String) {
        let isPending = PendingUploadStore.shared.contains(id: id)
        let message = isPending
            ? "This removes the item you added."
            : "This removes the item from your Apple TV library."
        let alert = UIAlertController(title: "Delete?", message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(UIAlertAction(title: "Delete", style: .destructive) { [weak self] _ in
            self?.performDelete(id: id)
        })
        present(alert, animated: true)
    }

    /// Deletes an item. Queued items are removed locally and dropped from the upload
    /// queue; a delete is still sent to the TV in case it already has the item.
    func performDelete(id: String) {
        let wasPending = PendingUploadStore.shared.contains(id: id)
        let sent = connectionManager.sendDeleteRequest(id: id)
        if wasPending {
            store.removeLocalItem(id: id)
        } else if sent {
            // TV will confirm via manifest; drop album membership immediately.
            LocalAlbumStore.shared.removeItemFromAllAlbums(itemId: id)
            SlideshowStore.shared.removeItemFromAllSlideshows(itemId: id)
        }
        if sent || wasPending {
            MediaFitSettings.clear(forId: id)
            MediaFramingStore.clear(forId: id)
            MediaNoteStore.clear(forId: id)
            MediaTitleStore.clear(forId: id)
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        } else {
            presentNotConnectedAlert()
        }
    }

    /// Selects an item as live without the Eclipse TV app (AirPlay remember / push).
    func presentOfflineLive(for item: LibraryItemDTO) {
        if item.isVideo {
            AudioPlayerController.shared.stop()
            if let localURL = LocalMediaStore.shared.localURL(forId: item.id) {
                PresentationPrewarmer.shared.prewarm(url: localURL)
            }
        } else {
            PresentationPrewarmer.shared.clear()
        }
        let startAt = item.isVideo ? (VideoResumeStore.shared.position(for: item.id) ?? 0) : 0
        if item.isVideo { VideoResumeStore.shared.clear(for: item.id) }
        let thumbnail = store.thumbnail(for: item.id)
        let source = PresentationSource.forLibraryItem(
            item, thumbnail: thumbnail, startAt: startAt
        )
        store.updateCurrentId(item.id)
        ExternalDisplayManager.shared.present(source)
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    /// Fullscreen Preview of a local full-res copy (⋯ Preview, or tap when locked
    /// / disconnected without Practice Mode).
    ///
    /// Videos use system `AVPlayerViewController` chrome; images use the swipe gallery.
    func presentLocalPreview(for item: LibraryItemDTO) {
        presentLocalPreview(for: item, in: displayItems)
    }

    /// Add note / Edit note action for still tiles.
    func noteAction(for item: LibraryItemDTO) -> UIAction {
        UIAction(
            title: MediaNoteStore.menuTitle(forId: item.id),
            image: UIImage(systemName: "note.text")
        ) { [weak self] _ in
            self?.presentNoteComposer(forId: item.id)
        }
    }

    /// Opens the slide-up note composer for a still.
    func presentNoteComposer(forId id: String) {
        presentMediaNoteComposer(forId: id)
    }

    /// Presents Preview for `item` among `neighbors` (images swipe; video is modal).
    func presentLocalPreview(for item: LibraryItemDTO, in neighbors: [LibraryItemDTO]) {
        guard let url = LocalMediaStore.shared.localURL(forId: item.id) else {
            let alert = UIAlertController(
                title: "Can't Preview",
                message: "No local copy on this phone. Add the item from Photos first.",
                preferredStyle: .alert
            )
            alert.addAction(UIAlertAction(title: "OK", style: .default))
            present(alert, animated: true)
            return
        }

        if item.isVideo {
            presentLocalVideoPreview(
                fileURL: url,
                isMuted: item.isMuted ?? false,
                isLooping: item.isLooping ?? false
            )
            return
        }

        if isShowMode, presentShowPreviewGallery(startingAt: item.id) {
            return
        }

        guard !isPreviewAlreadyOpen else { return }
        let previewable = LocalMediaPreviewViewController.imagePreviewableItems(from: neighbors)
        guard let index = previewable.firstIndex(where: { $0.id == item.id }) else {
            let alert = UIAlertController(
                title: "Can't Preview",
                message: "No local copy on this phone. Add the item from Photos first.",
                preferredStyle: .alert
            )
            alert.addAction(UIAlertAction(title: "OK", style: .default))
            present(alert, animated: true)
            return
        }

        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        let preview = LocalMediaPreviewViewController(items: previewable, startIndex: index)
        preview.onDismiss = { [weak self] id in
            self?.revealShowMember(id: id)
        }
        preview.optionsMenuProvider = { [weak self] context in
            self?.previewOptionsMenu(context)
        }
        present(preview, animated: true)
    }

    /// Modal system-player Preview for a local video file.
    func presentLocalVideoPreview(
        fileURL: URL,
        isMuted: Bool = false,
        isLooping: Bool = false,
        startAt: TimeInterval = 0,
        onDismiss: ((TimeInterval) -> Void)? = nil
    ) {
        guard !isPreviewAlreadyOpen else { return }
        AudioAmbientPolicy.applyYieldIfNeeded(
            for: PresentationSource.video(fileURL, isLooping: isLooping, isMuted: isMuted)
        )
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        let preview = LocalVideoPreviewViewController(
            fileURL: fileURL,
            isMuted: isMuted,
            isLooping: isLooping,
            startAt: startAt
        )
        preview.onDismiss = onDismiss
        present(preview, animated: true)
    }

    /// Phone Preview for Background (⋯ Preview, or tap when locked / disconnected).
    func presentLogoPhonePreview() {
        guard let url = LogoStore.shared.fileURL else {
            onChooseLogo?()
            return
        }
        if isShowMode, presentShowPreviewGallery(startingAt: ShowToolToken.logo) {
            return
        }
        presentPhonePreview(
            id: ShowToolToken.logo, fileURL: url, isVideo: false
        )
    }

    /// Phone Preview for Screensaver (⋯ Preview, or tap when locked / disconnected).
    func presentScreensaverPhonePreview() {
        guard let source = ScreensaverStore.shared.presentationSource else { return }
        if isShowMode, presentShowPreviewGallery(startingAt: ShowToolToken.screensaver) {
            return
        }
        switch source.content {
        case .image(let url, _, _):
            presentPhonePreview(
                id: ShowToolToken.screensaver, fileURL: url, isVideo: false
            )
        case .screensaver(let url, _), .video(let url, _, _):
            presentPhonePreview(
                id: ShowToolToken.screensaver, fileURL: url, isVideo: true
            )
        case .camera, .web, .webVideo, .pdf, .black, .countdown, .unavailable:
            break
        }
    }

    /// Single-item Preview for Show tools, framed to Display Mode with aspect-fill.
    ///
    /// Matches tile / AirPlay framing: landscape Screensaver art fills a Vertical
    /// 9:16 panel (cropped) instead of letterboxing on the phone.
    func presentPhonePreview(id: String, fileURL: URL, isVideo: Bool) {
        guard !isPreviewAlreadyOpen else { return }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        let preview = DisplayModeMediaPreviewViewController(
            fileURL: fileURL,
            isVideo: isVideo,
            usesSeamlessLoop: isVideo && id == ShowToolToken.screensaver
        )
        present(preview, animated: true)
    }

    func presentNotConnectedAlert() {
        let alert = UIAlertController(
            title: "EclipseTV Not Linked",
            message: "This action needs a link to the Eclipse TV app (pairing code). "
                + "AirPlay alone is enough to present, but not for this.",
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(UIAlertAction(title: "Connect…", style: .default) { [weak self] _ in
            self?.onRequestEclipseTVConnect?()
        })
        present(alert, animated: true)
    }
}
