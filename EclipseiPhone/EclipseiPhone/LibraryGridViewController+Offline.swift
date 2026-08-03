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
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        } else {
            presentNotConnectedAlert()
        }
    }

    /// Selects an item as live without the Eclipse TV app (AirPlay remember / push).
    ///
    /// Only used when `hasLiveOutputDestination` is true. With no display and no TV
    /// link, video taps use `presentPhoneLiveVideo` and stills open Preview.
    func presentOfflineLive(for item: LibraryItemDTO) {
        if item.isVideo {
            AudioPlayerController.shared.stop()
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

    /// Marks a local video live and plays it in the phone hero (no external display).
    func presentPhoneLiveVideo(_ item: LibraryItemDTO) {
        guard item.isVideo,
              LocalMediaStore.shared.localURL(forId: item.id) != nil else {
            presentLocalPreview(
                for: item,
                in: openShowItems.isEmpty ? displayItems : openShowItems
            )
            return
        }
        SlideshowPlaybackController.shared.stop()
        AudioPlayerController.shared.stop()
        let startAt = VideoResumeStore.shared.position(for: item.id) ?? 0
        VideoResumeStore.shared.clear(for: item.id)
        isBlackSelected = false
        isLogoSelected = false
        isScreensaverSelected = false
        store.updateCurrentId(item.id)
        phoneLiveVideoStartAt = startAt
        let source = PresentationSource.forLibraryItem(
            item, thumbnail: store.thumbnail(for: item.id), startAt: startAt
        )
        AudioAmbientPolicy.applyYieldIfNeeded(for: source)
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        updateHeroVisibility()
        reloadLibraryGrid()
        refreshLiveHeader()
    }

    /// Fullscreen Preview of a local full-res copy (⋯ Preview, or tap when locked).
    ///
    /// Videos use system `AVPlayerViewController` chrome; images use the swipe gallery.
    func presentLocalPreview(for item: LibraryItemDTO) {
        presentLocalPreview(for: item, in: displayItems)
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

        guard !isAlreadyOpen(LocalMediaPreviewViewController.self),
              !isAlreadyOpen(LocalVideoPreviewViewController.self) else { return }
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
        guard !isAlreadyOpen(LocalVideoPreviewViewController.self),
              !isAlreadyOpen(LocalMediaPreviewViewController.self) else { return }
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

    /// Phone Preview for Background (⋯ Preview, or tap when live output is locked).
    func presentLogoPhonePreview() {
        guard let url = LogoStore.shared.fileURL else {
            onChooseLogo?()
            return
        }
        presentPhonePreview(
            id: ShowToolToken.logo, fileURL: url, isVideo: false
        )
    }

    /// Phone Preview for Screensaver (⋯ Preview, or tap when live output is locked).
    func presentScreensaverPhonePreview() {
        guard let source = ScreensaverStore.shared.presentationSource else { return }
        switch source.content {
        case .image(let url, _):
            presentPhonePreview(
                id: ShowToolToken.screensaver, fileURL: url, isVideo: false
            )
        case .screensaver(let url), .video(let url, _, _):
            presentPhonePreview(
                id: ShowToolToken.screensaver, fileURL: url, isVideo: true
            )
        case .camera, .web, .pdf, .black, .unavailable:
            break
        }
    }

    /// Single-item fullscreen Preview (Show tools; not a gallery swipe).
    func presentPhonePreview(id: String, fileURL: URL, isVideo: Bool) {
        if isVideo {
            // Screensaver / tool videos loop like the live surface.
            presentLocalVideoPreview(fileURL: fileURL, isLooping: true)
            return
        }
        guard !isAlreadyOpen(LocalMediaPreviewViewController.self),
              !isAlreadyOpen(LocalVideoPreviewViewController.self) else { return }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        let item = LocalMediaPreviewItem(id: id, fileURL: fileURL, isVideo: false)
        present(
            LocalMediaPreviewViewController(items: [item], startIndex: 0),
            animated: true
        )
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
