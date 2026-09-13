//
//  ShowProgram.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import Foundation

/// The one item or tool that owns live output.
///
/// Program is a single value on purpose. The state behind it is spread over
/// independent stores — `ExternalDisplayManager`, `SlideshowPlaybackController`,
/// `TVLibraryStore.currentId`, `CountdownController`, `QuestPollSessionStore`, and
/// the Show tool flags — and every go-live path is supposed to clear the others.
/// While each tile answered "am I live?" from its own store, excluding only the
/// kinds that predicate's author remembered, one missed teardown put the red live
/// stroke on two thumbnails at once. Resolving one winner (`ShowProgramResolver`)
/// and asking each tile whether it matches makes that impossible to express.
struct ShowProgram: Equatable {

    /// What kind of content or tool is live.
    let kind: ShowLiveItemKind

    /// Member id that is live, or nil for a global tool (Camera, Background,
    /// Screensaver, Blackout).
    let itemId: String?

    /// Creates a resolved program value.
    init(kind: ShowLiveItemKind, itemId: String? = nil) {
        self.kind = kind
        self.itemId = itemId
    }
}

// MARK: - Director Snapshot

extension ShowProgram {

    /// Program mirrored from the director, or nil when nothing is live there.
    ///
    /// A blackout resolves to no program so a follow phone's grid shows no red
    /// stroke, matching what the director's own grid paints while black is up.
    init?(snapshot: ShowLiveSnapshot) {
        guard !snapshot.isBlackout, let kind = snapshot.liveKind else { return nil }
        self.init(kind: kind, itemId: snapshot.liveItemId)
    }
}

// MARK: - Grid Matching

extension ShowProgram {

    /// Whether `item`'s tile is the one that is live.
    ///
    /// Blackout matches nothing: it is header chrome, not a card.
    func matches(_ item: ShowGridItem) -> Bool {
        switch item {
        case .slideshow(let show):
            return kind == .slideshow && itemId == show.id.uuidString
        case .livePoll(let poll):
            return kind == .livePoll && itemId == poll.id.uuidString
        case .countdown(let countdown):
            return kind == .countdown && itemId == countdown.id.uuidString
        case .media(let media):
            return kind == .media && itemId == media.id
        case .website(let page):
            return kind == .web && itemId == page.id.uuidString
        case .pdf(let doc):
            return kind == .pdf && itemId == doc.id.uuidString
        case .screensaver:
            return kind == .screensaver
        case .logo:
            return kind == .logo
        case .camera:
            return kind == .camera
        case .unresolved, .add:
            return false
        }
    }
}
