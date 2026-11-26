//
//  LiveSlideshowView.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import Foundation

/// The slideshow that is live, as one device sees it: which one, its slides in
/// order, and the slide on the TV.
///
/// The phone running the Show reads it from its own player; a second phone
/// acting as a remote reads it from what the first phone reports. Everything
/// that draws the slide strip or steps slides goes through this one value, so
/// both phones show the same strip and neither reads the other's source.
struct LiveSlideshowView: Equatable {
    let slideshowId: UUID
    let slideIds: [String]
    let index: Int

    /// Library id of the slide on the TV.
    var currentSlideId: String? {
        slideIds.indices.contains(index) ? slideIds[index] : nil
    }

    /// From this phone's own slideshow player; nil when it plays none.
    init?(playbackSlideshowId: UUID?, slideIds: [String], index: Int) {
        guard let playbackSlideshowId, !slideIds.isEmpty else { return nil }
        self.slideshowId = playbackSlideshowId
        self.slideIds = slideIds
        self.index = min(max(0, index), slideIds.count - 1)
    }

    /// From the director's report; nil unless a slideshow is on program there
    /// and the report carries its slides (an older build sends none).
    init?(snapshot: ShowLiveSnapshot?) {
        guard let snapshot, !snapshot.isBlackout, snapshot.liveKind == .slideshow,
              let id = snapshot.liveItemId.flatMap(UUID.init(uuidString:)),
              let state = snapshot.slideshow, !state.slideIds.isEmpty,
              state.slideIds.indices.contains(state.index) else { return nil }
        self.slideshowId = id
        self.slideIds = state.slideIds
        self.index = state.index
    }

    /// Where a step of `delta` slides lands on a remote's strip, or nil at an end.
    /// The director applies its own Loop rule; this only stops a remote sending a
    /// step that cannot move.
    func canStep(by delta: Int, loops: Bool) -> Bool {
        guard delta != 0, slideIds.count > 1 else { return false }
        return loops || slideIds.indices.contains(index + delta)
    }
}
