//
//  QuestPollSessionStore.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import Foundation
import LivePollKit

/// In-memory host session for a Live Poll card (not persisted across launch).
@MainActor
final class QuestPollSessionStore {
    static let shared = QuestPollSessionStore()

    static let didChangeNotification = Notification.Name(
        "QuestPollSessionStore.didChange"
    )

    private(set) var session: LivePollSession?
    /// ShowLivePoll.id owning the live room, when started from a card.
    private(set) var membershipId: UUID?
    /// Deck length from the card, picker, or session payload.
    private(set) var questionCount = 1
    /// True while a ribbon cue is sending host commands.
    private(set) var isControlInFlight = false
    /// Membership whose Practice preview is in the hero (no room).
    private(set) var practiceMembershipId: UUID?
    /// Last store mutation that posted `didChangeNotification`.
    private(set) var lastChange: QuestPollSessionChange = .session

    /// Replaces the active room after create or control.
    @discardableResult
    func adopt(
        _ session: LivePollSession,
        questionCount: Int? = nil,
        membershipId: UUID? = nil
    ) -> QuestPollSessionChange {
        let before = snapshot
        self.session = session
        if let membershipId {
            self.membershipId = membershipId
        }
        practiceMembershipId = nil
        if let questionCount {
            self.questionCount = max(questionCount, 1)
        } else if session.questionCount > 0 {
            self.questionCount = max(session.questionCount, 1)
        }
        return commitChange(from: before)
    }

    /// Marks a card as practicing in the hero without a Live Poll room.
    @discardableResult
    func setPracticeMembershipId(_ id: UUID?) -> QuestPollSessionChange {
        let before = snapshot
        practiceMembershipId = id
        return commitChange(from: before)
    }

    /// Clears the room when the operator signs out, ends, or removes the card.
    @discardableResult
    func clear() -> QuestPollSessionChange {
        let before = snapshot
        session = nil
        membershipId = nil
        practiceMembershipId = nil
        questionCount = 1
        isControlInFlight = false
        return commitChange(from: before)
    }

    /// Marks a host-control round-trip so ribbon taps do not stack.
    func setControlInFlight(_ inFlight: Bool) {
        isControlInFlight = inFlight
    }

    /// Ribbon index for the current room, or 0 when idle.
    var ribbonIndex: Int {
        guard let session else { return 0 }
        return QuestPollRibbon.currentIndex(
            phase: session.phase,
            questionIndex: session.questionIndex,
            questionCount: questionCount
        )
    }

    /// Join / Question/Results thumbs for the current deck.
    var ribbonItems: [QuestPollRibbonItem] {
        QuestPollRibbon.items(questionCount: questionCount)
    }

    /// Tile secondary line: join code and live response count.
    var tileSubtitle: String? {
        guard let session else { return nil }
        let votes = session.answeredCount
        if votes > 0 {
            return "\(session.code) · \(votes) response\(votes == 1 ? "" : "s")"
        }
        return session.code
    }

    /// Current session fields used to classify UI updates.
    var snapshot: QuestPollSessionSnapshot {
        QuestPollSessionSnapshot(
            session: session,
            membershipId: membershipId,
            questionCount: questionCount,
            practiceMembershipId: practiceMembershipId
        )
    }

    private func commitChange(
        from before: QuestPollSessionSnapshot
    ) -> QuestPollSessionChange {
        let change = QuestPollSessionChange.classify(from: before, to: snapshot)
        guard change != .none else { return .none }
        lastChange = change
        NotificationCenter.default.post(name: Self.didChangeNotification, object: nil)
        return change
    }
}
