//
//  EclipseShareProtocol+Slideshow.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

// EclipseShareProtocol+Slideshow.swift
//
// IMPORTANT: Duplicated verbatim in the iPhone target
// (`EclipseiPhone/EclipseiPhone/EclipseShareProtocol+Slideshow.swift`).
// `Scripts/verify_shared_sources.sh` fails the build if the copies drift.
import Foundation

/// Feature names a TV lists in its library manifest (`capabilities`).
///
/// A phone only uses a feature the TV it talks to has listed, so an older TV
/// (which lists nothing) keeps getting today's messages. Thread Safety: pure values.
enum EclipseShareCapability {
    /// The TV can play a whole slideshow by itself (`play_slideshow`, `slideshow_control`).
    static let slideshow = "slideshow"

    /// Everything this build of the Apple TV app understands.
    static let advertisedByTV: [String] = [slideshow]

    /// Whether a TV's reported list includes TV-run slideshows.
    /// - Parameter capabilities: The manifest's list; nil for TVs that predate it.
    /// - Returns: `true` only when the TV said so.
    static func supportsSlideshow(_ capabilities: [String]?) -> Bool {
        capabilities?.contains(slideshow) ?? false
    }
}

// MARK: - Slideshow DTOs

/// One slide of a TV-run slideshow: a TV library file name plus its framing.
///
/// `isFill` / `framing` mirror what a `playRequest` carries for a still, so each
/// slide looks the same as when the phone sent it on its own.
struct SlideshowSlideDTO: Codable, Equatable {
    let id: String
    var isFill: Bool?
    var framing: MediaFramingDTO?
}

/// A slideshow the TV plays by itself (`play_slideshow`).
struct SlideshowDTO: Codable, Equatable {
    /// Slides in play order.
    var slides: [SlideshowSlideDTO]
    /// Slide to show first (clamped by the TV).
    var startIndex: Int
    /// Seconds per slide when Autoplay is on; nil means the phone steps by hand.
    var seconds: Double?
    /// After the last slide, start again from the first.
    var loops: Bool
    /// Dissolve between slides (else cut).
    var crossfades: Bool
}

/// What a `slideshow_control` message asks for.
enum SlideshowControlAction: String {
    /// Show the slide named by the envelope's `id` and restart the slide timer.
    case goTo = "goto"
    /// Stop advancing; the slide on screen stays.
    case stop
}

// MARK: - Builders

extension EclipseShareEnvelope {

    /// Hands a whole slideshow to the TV.
    /// - Parameter slideshow: Slides, start slide and timing.
    /// - Returns: A `play_slideshow` envelope.
    static func playSlideshow(_ slideshow: SlideshowDTO) -> EclipseShareEnvelope {
        EclipseShareEnvelope(
            eclipseMsg: EclipseShareProtocol.Kind.playSlideshow.rawValue,
            slideshow: slideshow
        )
    }

    /// Steps the TV's slideshow to the slide with file name `id`.
    /// - Parameter id: The slide's TV library id.
    /// - Returns: A `slideshow_control` envelope.
    static func slideshowGoTo(id: String) -> EclipseShareEnvelope {
        EclipseShareEnvelope(
            eclipseMsg: EclipseShareProtocol.Kind.slideshowControl.rawValue,
            id: id,
            mode: SlideshowControlAction.goTo.rawValue
        )
    }

    /// Stops the TV's slideshow, leaving its current slide on screen.
    /// - Returns: A `slideshow_control` envelope.
    static func slideshowStop() -> EclipseShareEnvelope {
        EclipseShareEnvelope(
            eclipseMsg: EclipseShareProtocol.Kind.slideshowControl.rawValue,
            mode: SlideshowControlAction.stop.rawValue
        )
    }

    /// The control action of a `slideshow_control` message, nil if unknown.
    var slideshowControlAction: SlideshowControlAction? {
        mode.flatMap(SlideshowControlAction.init(rawValue:))
    }
}
