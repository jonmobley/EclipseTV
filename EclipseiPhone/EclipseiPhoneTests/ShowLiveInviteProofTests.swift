//
//  ShowLiveInviteProofTests.swift
//  EclipseiPhoneTests
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import Foundation
import Testing
@testable import EclipseiPhone

/// A nearby device that only read the director's broadcast must not be able
/// to join Show Live, and bad numbers from a peer must not crash the director
/// (AUDIT_2026-11-02 P-3).
struct ShowLiveInviteProofTests {

    private let showId = UUID()
    private let ownKey = ShowLiveInviteProof.key(forRecordName: "_owner-record")

    @Test func sameAccountAnswerIsAccepted() {
        let challenge = ShowLiveInviteProof.newChallenge()
        let answer = ShowLiveInviteProof.answer(challenge: challenge, showId: showId, key: ownKey)
        #expect(ShowLiveInviteProof.isValid(proof: answer, challenge: challenge, showId: showId, key: ownKey))
    }

    @Test func otherAccountIsRefused() {
        let challenge = ShowLiveInviteProof.newChallenge()
        let stranger = ShowLiveInviteProof.key(forRecordName: "_someone-else")
        let answer = ShowLiveInviteProof.answer(challenge: challenge, showId: showId, key: stranger)
        #expect(!ShowLiveInviteProof.isValid(proof: answer, challenge: challenge, showId: showId, key: ownKey))
    }

    @Test func missingOrMalformedProofIsRefused() {
        let challenge = ShowLiveInviteProof.newChallenge()
        #expect(!ShowLiveInviteProof.isValid(proof: nil, challenge: challenge, showId: showId, key: ownKey))
        #expect(!ShowLiveInviteProof.isValid(proof: "zz", challenge: challenge, showId: showId, key: ownKey))
        #expect(!ShowLiveInviteProof.isValid(proof: "abc", challenge: challenge, showId: showId, key: ownKey))
    }

    @Test func answerForAnOldChallengeOrOtherShowIsRefused() {
        let old = ShowLiveInviteProof.newChallenge()
        let answer = ShowLiveInviteProof.answer(challenge: old, showId: showId, key: ownKey)
        #expect(!ShowLiveInviteProof.isValid(
            proof: answer, challenge: ShowLiveInviteProof.newChallenge(), showId: showId, key: ownKey
        ))
        #expect(!ShowLiveInviteProof.isValid(proof: answer, challenge: old, showId: UUID(), key: ownKey))
    }

    @Test func challengesAreFreshEachTime() {
        let first = ShowLiveInviteProof.newChallenge()
        #expect(first.count == 32)
        #expect(first != ShowLiveInviteProof.newChallenge())
    }

    @Test func invitationCarriesTheProof() throws {
        let invite = ShowLiveInvitation(showId: showId, userHash: "0011223344556677", proof: "ab12")
        let decoded = try JSONDecoder().decode(
            ShowLiveInvitation.self, from: JSONEncoder().encode(invite)
        )
        #expect(decoded == invite)
    }

    @Test func remoteCountdownSecondsNeverTrap() {
        #expect(ShowLiveRouting.wholeSeconds(nil) == nil)
        #expect(ShowLiveRouting.wholeSeconds(.nan) == nil)
        #expect(ShowLiveRouting.wholeSeconds(.infinity) == nil)
        #expect(ShowLiveRouting.wholeSeconds(-5) == nil)
        #expect(ShowLiveRouting.wholeSeconds(0.5) == nil)
        #expect(ShowLiveRouting.wholeSeconds(1e30) == ShowLiveRouting.maximumRemoteCountdownSeconds)
        #expect(ShowLiveRouting.wholeSeconds(90.7) == 90)
    }
}
