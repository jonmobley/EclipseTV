//
//  ExternalDisplayManager+VideoTransport.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import Foundation

// MARK: - Library Video Transport (phone remote → AirPlay player)

extension ExternalDisplayManager {

    /// Posted as the AirPlay library video plays, pauses, or seeks.
    static let videoPlaybackDidChangeNotification = Notification.Name(
        "ExternalDisplayManager.videoPlaybackDidChange"
    )

    /// True when the external display is showing library video (player, no overlay).
    var isLibraryVideoLive: Bool {
        libraryVideoPlayer != nil || webVideoPresentation != nil
    }

    /// Phone-hero scrubber state. Empty when AirPlay is not on library / web video.
    var libraryVideoPlaybackState: PlaybackState {
        if let presentation = libraryVideoPresentation {
            var state = presentation.libraryVideoPlaybackState
            state.itemId = TVLibraryStore.shared.currentId
            return state
        }
        if let presentation = webVideoPresentation {
            return presentation.webVideoPlaybackState
        }
        return PlaybackState()
    }

    /// Play/pause AirPlay library or web video. False when neither player is live.
    @discardableResult
    func toggleLibraryVideoPlayback() -> Bool {
        if let presentation = libraryVideoPresentation {
            return presentation.toggleLibraryVideoPlayback()
        }
        return webVideoPresentation?.toggleWebVideoPlayback() ?? false
    }

    /// Relative skip on AirPlay library or web video.
    @discardableResult
    func skipLibraryVideo(by delta: TimeInterval) -> Bool {
        if let presentation = libraryVideoPresentation {
            return presentation.skipLibraryVideo(by: delta)
        }
        return webVideoPresentation?.skipWebVideo(by: delta) ?? false
    }

    /// Absolute seek on AirPlay library or web video.
    @discardableResult
    func seekLibraryVideo(to position: TimeInterval) -> Bool {
        if let presentation = libraryVideoPresentation {
            return presentation.seekLibraryVideo(to: position)
        }
        return webVideoPresentation?.seekWebVideo(to: position) ?? false
    }
}
