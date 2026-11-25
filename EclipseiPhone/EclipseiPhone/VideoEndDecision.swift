//
//  VideoEndDecision.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import Foundation

// MARK: - VideoEndDecision

/// What to do the moment a live video plays to its end.
///
/// Pause and Loop need nothing here (the player already holds or restarts), so
/// only Next and Screensaver ever take over output, and only when the video is
/// really what the room is looking at and this phone owns that output.
///
/// Thread safety: pure value logic.
enum VideoEndDecision: Equatable {
    /// Leave output alone.
    case stay
    /// Go live with the next item in the Show (or black at the last card).
    case next
    /// Switch output to the Screensaver.
    case screensaver

    /// Posted when a non-looping live video reaches its end.
    ///
    /// Sent by the AirPlay player and by the hero player when it is the output
    /// (Practice Mode). `userInfo` is empty: the live video is `TVLibraryStore.currentId`.
    static let didFinishNotification = Notification.Name("VideoEndDecision.didFinish")

    /// Decides what a finished video does.
    ///
    /// - Parameters:
    ///   - action: The video's "When Video Ends" choice.
    ///   - isVideoLive: The finished video is still the live item.
    ///   - isRemoteOperator: This phone drives another phone's output.
    ///   - isOutputLocked: The operator pinned live output in place.
    ///   - isPhonePreview: The video was only a private phone preview.
    ///   - isBlackoutHolding: Blackout is holding the room dark.
    static func decide(
        action: VideoEndAction,
        isVideoLive: Bool,
        isRemoteOperator: Bool,
        isOutputLocked: Bool,
        isPhonePreview: Bool,
        isBlackoutHolding: Bool
    ) -> VideoEndDecision {
        guard isVideoLive, !isRemoteOperator, !isOutputLocked,
              !isPhonePreview, !isBlackoutHolding else { return .stay }
        switch action {
        case .pause, .loop: return .stay
        case .next: return .next
        case .screensaver: return .screensaver
        }
    }
}
