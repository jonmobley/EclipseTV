//
//  LivePollTap.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import Foundation

/// What a tap on a Live Poll card does.
enum LivePollTapAction: Equatable {
    /// This card's room is already on the projector: re-sync chrome and cues.
    case refreshProjector
    /// This card owns a room that nothing is showing: put `/present` back up.
    case presentRoom
    /// No room for this card: open one and go live on it.
    case start
}

/// Tap rule for a Live Poll card.
///
/// A poll card goes live on the first tap, like every other card in a Show.
/// Practice is a rehearsal action in the card's ⋯ menu, so a tap always means
/// "put this on the projector" — including on a deck that is only rehearsing,
/// which is how Practice is left for the real thing.
enum LivePollTap {

    /// - Parameters:
    ///   - ownsRoom: This card owns the active QuestPoll room.
    ///   - roomIsOnProgram: A QuestPoll page is on the projector.
    static func action(ownsRoom: Bool, roomIsOnProgram: Bool) -> LivePollTapAction {
        guard ownsRoom else { return .start }
        return roomIsOnProgram ? .refreshProjector : .presentRoom
    }
}
