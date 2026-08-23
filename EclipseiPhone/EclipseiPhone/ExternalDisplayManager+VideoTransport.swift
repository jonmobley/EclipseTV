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
    var isLibraryVideoLive: Bool { libraryVideoPlayer != nil }

    /// Phone-hero scrubber state. Empty when AirPlay is not on library video.
    var libraryVideoPlaybackState: PlaybackState {
        var state = libraryVideoPresentation?.libraryVideoPlaybackState ?? PlaybackState()
        state.itemId = TVLibraryStore.shared.currentId
        return state
    }

    /// Play/pause AirPlay library video. False when that player is not live.
    @discardableResult
    func toggleLibraryVideoPlayback() -> Bool {
        libraryVideoPresentation?.toggleLibraryVideoPlayback() ?? false
    }

    /// Relative skip on AirPlay library video.
    @discardableResult
    func skipLibraryVideo(by delta: TimeInterval) -> Bool {
        libraryVideoPresentation?.skipLibraryVideo(by: delta) ?? false
    }

    /// Absolute seek on AirPlay library video.
    @discardableResult
    func seekLibraryVideo(to position: TimeInterval) -> Bool {
        libraryVideoPresentation?.seekLibraryVideo(to: position) ?? false
    }
}
