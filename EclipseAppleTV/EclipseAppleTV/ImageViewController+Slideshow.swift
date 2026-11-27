//
//  ImageViewController+Slideshow.swift
//  EclipseTV
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import UIKit

// MARK: - TV-Run Slideshows

/// Plays a slideshow the phone handed over (`play_slideshow`) on the TV by itself.
///
/// Each slide is shown the same way a phone `playRequest` shows a photo, so
/// framing, album placement and the phone's live marker all behave as before.
/// Thread Safety: Main thread only (UIKit).
extension ImageViewController: ConnectionManagerSlideshowDelegate {

    // MARK: - ConnectionManagerSlideshowDelegate

    func connectionManager(_ manager: ConnectionManager, didReceiveSlideshow slideshow: SlideshowDTO) {
        dataSource.revalidateAvailability()
        guard let plan = TVSlideshowPlan(
            dto: slideshow,
            isAvailable: { [weak self] id in self?.libraryIndex(forItemId: id) != nil }
        ) else {
            logger.error("Slideshow has no slides on this TV")
            showNotificationToast(message: "Those slides aren't on this TV yet")
            return
        }
        clearIdleParkForPlayRequest()
        hideIdleScreen()
        wireSlideshowPlayerIfNeeded()
        slideshowPlayer.start(plan)
    }

    func connectionManager(_ manager: ConnectionManager, didReceiveSlideshowGoTo id: String) {
        guard slideshowPlayer.goTo(id: id) else {
            logger.info("Slideshow step for a slide that isn't running: \(id, privacy: .public)")
            return
        }
    }

    func connectionManagerDidStopSlideshow(_ manager: ConnectionManager) {
        slideshowPlayer.stop()
    }

    // MARK: - Internal Helpers

    /// Stops a running slideshow because the viewer took over with the remote.
    func stopSlideshowForLocalNavigation() {
        guard slideshowPlayer.isRunning else { return }
        logger.info("Slideshow stopped by the remote")
        slideshowPlayer.stop()
    }

    // MARK: - Private Helpers

    private func wireSlideshowPlayerIfNeeded() {
        guard slideshowPlayer.presentSlide == nil else { return }
        slideshowPlayer.presentSlide = { [weak self] id, crossfade in
            self?.presentSlideshowSlide(id: id, crossfade: crossfade) ?? false
        }
    }

    /// Puts slide `id` on screen like a phone play request.
    /// - Returns: false when the TV no longer has the slide.
    private func presentSlideshowSlide(id: String, crossfade: Bool) -> Bool {
        guard let index = libraryIndex(forItemId: id) else { return false }
        pendingVideoStartAt = nil
        pendingVideoStartsPaused = false
        dataSource.setCurrentIndex(index)
        // A menu or Move is open: the selection follows; the screen catches up later.
        if isMoveMode || presentedViewController != nil { return true }
        applyCompanionBrowse(forPlayingId: id)
        activeCollection = .library
        if isInGridMode {
            hideGridView()
        } else if crossfade {
            displayImageAtCurrentIndexWithDissolveTransition()
        } else {
            displayImageAtCurrentIndex()
        }
        return true
    }
}
