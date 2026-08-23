//
//  PresentationSource.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

// PresentationSource.swift
import UIKit

/// Describes what the external display should render fullscreen. Built from whatever the
/// user has selected in the app (a TV-library item, an album item, a picked file, or the
/// live camera) and handed to `PresentationViewController` via `ExternalDisplayManager`.
struct PresentationSource: Equatable {

    enum Content: Equatable {
        /// A still image at `url` (a local file or an HTTPS URL). `fill` crops the image
        /// to fill the panel instead of letterboxing it.
        case image(url: URL, fill: Bool)
        /// A video at `url` (a local file or an HTTPS URL), with playback options.
        case video(url: URL, isLooping: Bool, isMuted: Bool)
        /// Muted looping Screensaver; aspect-fill with a seamless crossfade at the loop.
        case screensaver(url: URL)
        /// Live back-camera feed from `CameraManager` (AirPlay only).
        case camera
        /// A web page rendered full-bleed on the external display (AirPlay only).
        case web(URL)
        /// A PDF rendered full-bleed on the external display (AirPlay only).
        case pdf(URL)
        /// Solid black screen with no idle brand chrome.
        case black
        /// The full-resolution file isn't on this device; show `thumbnail` (if any) with a
        /// short explanatory caption instead.
        case unavailable(thumbnail: UIImage?, message: String)
    }

    let content: Content
    /// Absolute seconds to seek when presenting `.video`. Ignored for other content.
    let videoStartAt: TimeInterval
    /// When false, `.video` is shown paused (blackout restore). Default is to play.
    let videoAutoplay: Bool

    /// - Parameter videoStartAt: Resume offset for library video (0 = from the start).
    /// - Parameter videoAutoplay: Play immediately. False parks on a still frame.
    init(
        content: Content,
        videoStartAt: TimeInterval = 0,
        videoAutoplay: Bool = true
    ) {
        self.content = content
        self.videoStartAt = videoStartAt
        self.videoAutoplay = videoAutoplay
    }

    // MARK: - Convenience builders

    static func image(_ url: URL, fill: Bool = false) -> PresentationSource {
        PresentationSource(content: .image(url: url, fill: fill))
    }

    static func video(
        _ url: URL,
        isLooping: Bool,
        isMuted: Bool,
        startAt: TimeInterval = 0,
        autoplay: Bool = true
    ) -> PresentationSource {
        PresentationSource(
            content: .video(url: url, isLooping: isLooping, isMuted: isMuted),
            videoStartAt: startAt,
            videoAutoplay: autoplay
        )
    }

    /// Same video, parked at `startAt` without playing. No-op for other content.
    func pausingVideo(at startAt: TimeInterval) -> PresentationSource {
        guard case .video = content else { return self }
        return PresentationSource(
            content: content,
            videoStartAt: startAt,
            videoAutoplay: false
        )
    }

    /// Muted seamless-loop Screensaver for AirPlay presentation.
    static func screensaver(_ url: URL) -> PresentationSource {
        PresentationSource(content: .screensaver(url: url))
    }

    /// Live camera feed for AirPlay presentation.
    static var camera: PresentationSource {
        PresentationSource(content: .camera)
    }

    /// Web page for AirPlay presentation.
    static func web(_ url: URL) -> PresentationSource {
        PresentationSource(content: .web(url))
    }

    /// PDF for AirPlay presentation.
    static func pdf(_ url: URL) -> PresentationSource {
        PresentationSource(content: .pdf(url))
    }

    /// Solid black output for the external display.
    static var black: PresentationSource {
        PresentationSource(content: .black)
    }

    static func unavailable(thumbnail: UIImage?, message: String) -> PresentationSource {
        PresentationSource(content: .unavailable(thumbnail: thumbnail, message: message))
    }

    /// Builds a source for a mirrored TV-library item, using the phone's local full-res
    /// copy when present and falling back to its thumbnail otherwise.
    ///
    /// Stills carry Fit / Fill (`fill` when set, otherwise the item's `MediaFitSettings`).
    /// - Parameter startAt: Resume offset for video (0 = from the start).
    /// - Parameter fill: Slideshow-level framing override for stills.
    static func forLibraryItem(
        _ item: LibraryItemDTO,
        thumbnail: UIImage?,
        startAt: TimeInterval = 0,
        fill: Bool? = nil
    ) -> PresentationSource {
        guard let localURL = LocalMediaStore.shared.localURL(forId: item.id) else {
            return .unavailable(thumbnail: thumbnail,
                                message: "Full-resolution copy isn't stored on this device.")
        }
        if item.isVideo {
            return .video(
                localURL,
                isLooping: item.isLooping ?? false,
                isMuted: item.isMuted ?? false,
                startAt: startAt
            )
        }
        return .image(localURL, fill: fill ?? MediaFitSettings.isFill(forId: item.id))
    }
}
