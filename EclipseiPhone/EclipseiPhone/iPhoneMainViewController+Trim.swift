//
//  iPhoneMainViewController+Trim.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import UIKit

extension iPhoneMainViewController {

    /// Opens the trimmer for a library video. Save permanently replaces the file with
    /// the kept part (like Crop), keeps the poster, and re-sends to Apple TV if linked.
    func beginTrimVideo(forItemId id: String) {
        guard let item = TVLibraryStore.shared.item(id: id), item.isVideo,
              let url = LocalMediaStore.shared.localURL(forId: id) else {
            showPresentationToast("Couldn't open that video.")
            return
        }
        Task { @MainActor in
            let duration = await VideoTrimExporter.durationSeconds(at: url)
            guard duration > 0.1 else {
                self.showPresentationToast("Couldn't open that video.")
                return
            }
            let trimmer = VideoTrimViewController(sourceURL: url, duration: duration)
            trimmer.onCancel = { [weak trimmer] in
                trimmer?.dismiss(animated: true)
            }
            trimmer.onTrimmed = { [weak self, weak trimmer] trimmedURL, range in
                guard let self else { return }
                trimmer?.dismiss(animated: true)
                self.finishTrim(trimmedURL: trimmedURL, length: range.length, itemId: id)
            }
            self.topmostPresenter.present(trimmer, animated: true)
        }
    }

    private func finishTrim(trimmedURL: URL, length: Double, itemId: String) {
        Task { @MainActor in
            var thumbnail = TVLibraryStore.shared.thumbnail(for: itemId)
            if thumbnail == nil {
                thumbnail = await VideoCropExporter.previewFrame(at: trimmedURL)
            }
            guard let thumbnail else {
                self.cleanupTempFile(at: trimmedURL)
                self.showPresentationToast("Couldn't save the edited video.")
                return
            }
            self.replaceEditedVideo(at: trimmedURL, itemId: itemId, thumbnail: thumbnail)
            TVLibraryStore.shared.applyVideoDurations([itemId: length], replacingExisting: true)
            Haptics.impactLight()
        }
    }

    /// The controller to present from, even while a sheet (Media Library) is up.
    private var topmostPresenter: UIViewController {
        var top: UIViewController = self
        while let next = top.presentedViewController, !next.isBeingDismissed {
            top = next
        }
        return top
    }
}
