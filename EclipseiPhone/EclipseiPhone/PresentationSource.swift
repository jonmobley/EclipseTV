//
//  PresentationSource.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

// PresentationSource.swift
import UIKit

/// Describes what the external display should render fullscreen. Built from whatever the
/// user has selected in the app (a TV-library item, an album item, or a picked file) and
/// handed to `PresentationViewController` via `ExternalDisplayManager`.
struct PresentationSource: Equatable {

    enum Content: Equatable {
        /// A still image at `url` (a local file or an HTTPS URL).
        case image(URL)
        /// A video at `url` (a local file or an HTTPS URL), with playback options.
        case video(url: URL, isLooping: Bool, isMuted: Bool)
        /// The full-resolution file isn't on this device; show `thumbnail` (if any) with a
        /// short explanatory caption instead.
        case unavailable(thumbnail: UIImage?, message: String)
    }

    let content: Content

    // MARK: - Convenience builders

    static func image(_ url: URL) -> PresentationSource {
        PresentationSource(content: .image(url))
    }

    static func video(_ url: URL, isLooping: Bool, isMuted: Bool) -> PresentationSource {
        PresentationSource(content: .video(url: url, isLooping: isLooping, isMuted: isMuted))
    }

    static func unavailable(thumbnail: UIImage?, message: String) -> PresentationSource {
        PresentationSource(content: .unavailable(thumbnail: thumbnail, message: message))
    }

    /// Builds a source for a mirrored TV-library item, using the phone's local full-res
    /// copy when present and falling back to its thumbnail otherwise.
    static func forLibraryItem(_ item: LibraryItemDTO, thumbnail: UIImage?) -> PresentationSource {
        guard let localURL = LocalMediaStore.shared.localURL(forId: item.id) else {
            return .unavailable(thumbnail: thumbnail,
                                message: "Full-resolution copy isn't stored on this device.")
        }
        if item.isVideo {
            return .video(localURL, isLooping: item.isLooping ?? false, isMuted: item.isMuted ?? false)
        }
        return .image(localURL)
    }
}
