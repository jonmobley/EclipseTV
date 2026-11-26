//
//  SlideshowTVHandoff.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import Foundation

/// Rules for handing a whole slideshow to an Apple TV that can run it itself.
///
/// When the TV can (`EclipseShareCapability.slideshow`), the phone sends the
/// slideshow once and the TV keeps time. Otherwise, or when a slide only lives on
/// the phone (a capture), the phone falls back to sending one photo at a time,
/// exactly as before.
///
/// Thread Safety: Pure; safe from any thread.
enum SlideshowTVHandoff {

    /// One slide's framing as the TV should show it.
    struct SlideFraming: Equatable {
        var isFill: Bool
        var framing: MediaFramingDTO?
    }

    /// Whether the TV should run this slideshow by itself.
    /// - Parameters:
    ///   - tvSupportsSlideshow: The active TV listed the slideshow capability.
    ///   - slideIds: Slides in play order.
    ///   - isPhoneOnly: Whether a slide lives only on the phone (never on the TV).
    /// - Returns: `true` to send `play_slideshow`; `false` to send photo by photo.
    static func tvRunsSlideshow(
        tvSupportsSlideshow: Bool,
        slideIds: [String],
        isPhoneOnly: (String) -> Bool
    ) -> Bool {
        tvSupportsSlideshow && !slideIds.isEmpty && !slideIds.contains(where: isPhoneOnly)
    }

    /// Builds the message body for a TV-run slideshow.
    /// - Parameters:
    ///   - slideshow: The slideshow's settings (Autoplay, seconds, Loop, Crossfade).
    ///   - slideIds: Playable slides in order.
    ///   - startIndex: Slide to start on.
    ///   - framing: Each slide's Fit / Fill and custom crop.
    /// - Returns: The DTO for `EclipseShareEnvelope.playSlideshow`.
    static func makeDTO(
        for slideshow: Slideshow,
        slideIds: [String],
        startIndex: Int,
        framing: (String) -> SlideFraming
    ) -> SlideshowDTO {
        let slides = slideIds.map { id -> SlideshowSlideDTO in
            let slide = framing(id)
            return SlideshowSlideDTO(id: id, isFill: slide.isFill, framing: slide.framing)
        }
        return SlideshowDTO(
            slides: slides,
            startIndex: startIndex,
            seconds: slideshow.autoplay ? Double(slideshow.autoplaySeconds.rawValue) : nil,
            loops: slideshow.loop,
            crossfades: slideshow.crossfade
        )
    }

    /// A slide's framing the same way `sendPlayRequest` works it out: a custom
    /// crop always fills, so older TVs that ignore the crop still fill.
    /// - Parameter id: The slide's library id.
    /// - Returns: Its Fit / Fill and crop.
    static func currentFraming(forId id: String) -> SlideFraming {
        let framing = MediaFramingStore.framing(forId: id)
        let isFill = framing != nil ? true : MediaFitSettings.isFill(forId: id)
        return SlideFraming(isFill: isFill, framing: framing.map { $0.asDTO })
    }
}
