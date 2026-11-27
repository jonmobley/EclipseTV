//
//  LibraryGridViewController+SlideRemove.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import UIKit

extension LibraryGridViewController {

    /// Fewest slides a slideshow keeps; the Mac needs two to keep a slideshow.
    static let minimumSlidesKept = 2

    /// Whether a slideshow with `count` slides can lose one from the strip.
    static func canRemoveSlide(fromSlideshowWith count: Int) -> Bool {
        count > minimumSlidesKept
    }

    /// Touch-and-hold menu for a slide in the live slideshow strip.
    ///
    /// Camera and Live Poll strips share the section and get no menu.
    func liveSlideMenuConfiguration(at indexPath: IndexPath) -> UIContextMenuConfiguration? {
        guard !showsCameraRibbon, !showsLivePollRibbon, showsLiveSlideshowRibbon,
              let show = activeLiveSlideshow() else { return nil }
        let ids = liveSlideshowView?.slideIds ?? []
        guard ids.indices.contains(indexPath.item) else { return nil }
        let slideId = ids[indexPath.item]
        let canRemove = Self.canRemoveSlide(fromSlideshowWith: show.itemIds.count)
        return UIContextMenuConfiguration(identifier: nil, previewProvider: nil) { [weak self] _ in
            let remove = UIAction(
                title: "Remove Slide",
                image: UIImage(systemName: "trash"),
                attributes: canRemove ? .destructive : [.destructive, .disabled]
            ) { _ in
                self?.removeSlideWithUndo(slideId, slideshowId: show.id)
            }
            return UIMenu(children: [remove])
        }
    }

    /// Takes a slide out of its slideshow, then offers Undo.
    ///
    /// Only the slideshow changes (the picture stays in the Library), so the
    /// slideshow's earlier slide order and cover are enough to put it back.
    func removeSlideWithUndo(_ slideId: String, slideshowId: UUID) {
        let store = SlideshowStore.shared
        guard let before = store.slideshow(id: slideshowId),
              before.itemIds.contains(slideId),
              Self.canRemoveSlide(fromSlideshowWith: before.itemIds.count) else { return }
        store.remove(itemId: slideId, fromSlideshowId: slideshowId)
        SlideshowPlaybackController.shared.reloadActiveSlides(slideshowId: slideshowId)
        Haptics.success()
        showUndoToast("Slide removed") {
            let store = SlideshowStore.shared
            store.reorder(itemIds: before.itemIds, inSlideshowId: slideshowId)
            if let cover = before.coverId {
                store.setCover(itemId: cover, slideshowId: slideshowId)
            }
            SlideshowPlaybackController.shared.reloadActiveSlides(slideshowId: slideshowId)
        }
    }
}
