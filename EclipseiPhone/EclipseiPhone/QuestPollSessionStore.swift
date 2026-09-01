//
//  QuestPollSessionStore.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import Foundation

/// In-memory host session for a Live Poll card (not persisted across launch).
@MainActor
final class QuestPollSessionStore {
    static let shared = QuestPollSessionStore()

    static let didChangeNotification = Notification.Name(
        "QuestPollSessionStore.didChange"
    )

    private(set) var session: QuestPollSession?
    /// ShowLivePoll.id owning the live room, when started from a card.
    private(set) var membershipId: UUID?
    /// Deck length from the card, picker, or session payload.
    private(set) var questionCount = 1
    /// True while a ribbon cue is sending start / results / next / prev / end.
    private(set) var isControlInFlight = false
    /// Membership whose Practice preview is in the hero (no room).
    private(set) var practiceMembershipId: UUID?

    /// Replaces the active room after create or control.
    func adopt(
        _ session: QuestPollSession,
        questionCount: Int? = nil,
        membershipId: UUID? = nil
    ) {
        self.session = session
        if let membershipId {
            self.membershipId = membershipId
        }
        practiceMembershipId = nil
        if let questionCount {
            self.questionCount = max(questionCount, 1)
        } else if let resolved = session.resolvedQuestionCount {
            self.questionCount = max(resolved, 1)
        }
        notifyChanged()
    }

    /// Marks a card as practicing in the hero without a QuestPoll room.
    func setPracticeMembershipId(_ id: UUID?) {
        practiceMembershipId = id
        notifyChanged()
    }

    /// Clears the room when the operator unlinks, ends, or removes the card.
    func clear() {
        session = nil
        membershipId = nil
        practiceMembershipId = nil
        questionCount = 1
        isControlInFlight = false
        notifyChanged()
    }

    /// Marks a host-control round-trip so ribbon taps do not stack.
    func setControlInFlight(_ inFlight: Bool) {
        isControlInFlight = inFlight
    }

    /// Ribbon index for the current room, or 0 when idle.
    var ribbonIndex: Int {
        guard let session else { return 0 }
        return QuestPollRibbon.currentIndex(
            status: session.status,
            questionIndex: session.questionIndex,
            questionCount: questionCount
        )
    }

    /// Join / Question/Results thumbs for the current deck.
    var ribbonItems: [QuestPollRibbonItem] {
        QuestPollRibbon.items(questionCount: questionCount)
    }

    /// Tile secondary line: join code and live vote count.
    var tileSubtitle: String? {
        guard let session else { return nil }
        let votes = session.voteCount
        if votes > 0 {
            return "\(session.code) · \(votes) vote\(votes == 1 ? "" : "s")"
        }
        return session.code
    }

    private func notifyChanged() {
        NotificationCenter.default.post(name: Self.didChangeNotification, object: nil)
    }
}
