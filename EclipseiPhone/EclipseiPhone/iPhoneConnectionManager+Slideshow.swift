//
//  iPhoneConnectionManager+Slideshow.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import Foundation

// MARK: - TV-Run Slideshows

/// Sends for slideshows the Apple TV plays by itself. Only the active TV gets
/// them (like `playRequest`), and only when it listed the slideshow capability.
/// Thread Safety: Main actor (reads `AppleTVCapabilities`).
extension iPhoneConnectionManager {

    /// Whether the active TV can play a whole slideshow by itself.
    @MainActor
    var activeTVRunsSlideshows: Bool {
        AppleTVCapabilities.shared.supportsSlideshow(activeTargetPeer)
    }

    /// Hands a whole slideshow to the active TV.
    /// - Parameter slideshow: Slides and timing.
    /// - Returns: Whether it was sent.
    @MainActor
    @discardableResult
    func sendPlaySlideshow(_ slideshow: SlideshowDTO) -> Bool {
        let sent = sendCommand(.playSlideshow(slideshow), description: "play slideshow")
        // Like a play request, a slideshow lifts the TV's park cover.
        if sent {
            AirPlayOverlayPark.noteUnparkedByPlayRequest()
        }
        return sent
    }

    /// Steps the TV's slideshow to slide `id` (restarts its slide timer).
    /// - Parameter id: The slide's library id.
    /// - Returns: Whether it was sent.
    @discardableResult
    func sendSlideshowGoTo(id: String) -> Bool {
        sendCommand(.slideshowGoTo(id: id), description: "slideshow go to")
    }

    /// Stops the TV's slideshow; its current slide stays on screen.
    /// - Returns: Whether it was sent.
    @discardableResult
    func sendSlideshowStop() -> Bool {
        sendCommand(.slideshowStop(), description: "slideshow stop")
    }
}
