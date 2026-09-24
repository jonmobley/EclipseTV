//
//  CameraFrameMirrorGate.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import Foundation

/// Holds frame-tap previews across a lens swap until they have been retargeted.
///
/// A swap rebuilds the video input inside one configuration block. Frames from the
/// new lens start arriving on the frame queue the moment it commits, while the
/// views that rotate them are retargeted on main a little later. Without a gate the
/// first few frames draw at the previous lens's angle. The gate drops frames until
/// the swap commits, then claims exactly one frame; the caller retargets and
/// enqueues that frame together on main, so the new turn and the new picture land
/// in the same transaction, and only then does the gate open.
///
/// `generation` guards a second swap that begins while the first is still
/// retargeting: the stale resume is refused and its frame dropped.
struct CameraFrameMirrorGate: Equatable {

    /// What the frame queue should do with the sample it just received.
    enum Action: Equatable {
        /// Deliver to every mirror on the frame queue.
        case deliver
        /// Drop — a swap is configuring, or another frame is already retargeting.
        case drop
        /// Hand this one frame to main; resume with the tagged generation.
        case retarget(generation: Int)
    }

    private enum State: Equatable {
        case flowing
        case paused
        case awaitingFrame
        case retargeting
    }

    private var state: State = .flowing
    private(set) var generation = 0

    /// A swap has begun configuring. Frames are dropped from here on.
    mutating func pause() {
        state = .paused
        generation += 1
    }

    /// The swap committed. The next frame is claimed for retargeting.
    mutating func awaitFrame() {
        guard state == .paused else { return }
        state = .awaitingFrame
    }

    /// Nothing will retarget (session not running). Open immediately.
    mutating func open() {
        state = .flowing
    }

    /// Resolves the frame that just arrived on the frame queue.
    mutating func action() -> Action {
        switch state {
        case .flowing:
            return .deliver
        case .paused, .retargeting:
            return .drop
        case .awaitingFrame:
            state = .retargeting
            return .retarget(generation: generation)
        }
    }

    /// Reopens after the retarget for `generation`.
    /// - Returns: False when a newer swap paused the gate in the meantime.
    mutating func resume(generation: Int) -> Bool {
        guard state == .retargeting, generation == self.generation else { return false }
        state = .flowing
        return true
    }
}
