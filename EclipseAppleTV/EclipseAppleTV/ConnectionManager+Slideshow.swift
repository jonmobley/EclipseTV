//
//  ConnectionManager+Slideshow.swift
//  EclipseTV
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import Foundation

// MARK: - Slideshow Delegate

/// Slideshow messages from the phone, delivered on the main thread.
protocol ConnectionManagerSlideshowDelegate: AnyObject {
    /// The phone handed over a slideshow for the TV to play by itself.
    func connectionManager(_ manager: ConnectionManager, didReceiveSlideshow slideshow: SlideshowDTO)
    /// The phone stepped the running slideshow to the slide `id`.
    func connectionManager(_ manager: ConnectionManager, didReceiveSlideshowGoTo id: String)
    /// The phone stopped the slideshow, or sent something that replaces it.
    func connectionManagerDidStopSlideshow(_ manager: ConnectionManager)
}

// MARK: - Slideshow Message Routing

/// Routes `play_slideshow` / `slideshow_control` and stops a running slideshow when
/// the phone sends anything that replaces it (`TVSlideshowInterruption`).
///
/// Thread Safety: Called on the Multipeer queue; every delegate call hops to main,
/// in arrival order, so a stop always lands before the message that caused it.
extension ConnectionManager {

    /// Stops a running slideshow before applying a message that replaces it.
    /// - Parameter envelope: The message about to be handled.
    func stopSlideshowIfInterrupted(by envelope: EclipseShareEnvelope) {
        guard TVSlideshowInterruption.stops(envelope.kind) else { return }
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.slideshowDelegate?.connectionManagerDidStopSlideshow(self)
        }
    }

    /// Applies a `play_slideshow` message: stores each slide's framing, then hands over.
    /// - Parameter envelope: A decoded `play_slideshow` envelope.
    func handlePlaySlideshow(_ envelope: EclipseShareEnvelope) {
        guard let slideshow = envelope.slideshow, !slideshow.slides.isEmpty else {
            logger.error("Ignoring play_slideshow with no slides")
            return
        }
        logger.info("Received play_slideshow: \(slideshow.slides.count) slides")
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.activateModeIfNeeded(from: envelope)
            for slide in slideshow.slides {
                if let isFill = slide.isFill {
                    ImageFitSettings.setFill(isFill, forFileName: slide.id)
                }
                self.applyIncomingFraming(slide.framing, forFileName: slide.id)
            }
            self.slideshowDelegate?.connectionManager(self, didReceiveSlideshow: slideshow)
        }
    }

    /// Applies a `slideshow_control` message (go to a slide, or stop).
    /// - Parameter envelope: A decoded `slideshow_control` envelope.
    func handleSlideshowControl(_ envelope: EclipseShareEnvelope) {
        switch envelope.slideshowControlAction {
        case .goTo:
            guard let id = envelope.id else { return }
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.slideshowDelegate?.connectionManager(self, didReceiveSlideshowGoTo: id)
            }
        case .stop:
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.slideshowDelegate?.connectionManagerDidStopSlideshow(self)
            }
        case .none:
            logger.error("Ignoring slideshow_control with an unknown action")
        }
    }

    /// The delegate, when it also handles slideshows.
    private var slideshowDelegate: ConnectionManagerSlideshowDelegate? {
        delegate as? ConnectionManagerSlideshowDelegate
    }
}
