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
    private let ownKey = ShowLiveInviteProof.key(forAccountSecret: Data(repeating: 1, count: 32))

    @Test func sameAccountAnswerIsAccepted() {
        let challenge = ShowLiveInviteProof.newChallenge()
        let answer = ShowLiveInviteProof.answer(challenge: challenge, showId: showId, nonce: "n1", key: ownKey)
        #expect(ShowLiveInviteProof.isValid(proof: answer, challenge: challenge, showId: showId, nonce: "n1", key: ownKey))
    }

    @Test func otherAccountIsRefused() {
        let challenge = ShowLiveInviteProof.newChallenge()
        let stranger = ShowLiveInviteProof.key(forAccountSecret: Data(repeating: 2, count: 32))
        let answer = ShowLiveInviteProof.answer(challenge: challenge, showId: showId, nonce: "n1", key: stranger)
        #expect(!ShowLiveInviteProof.isValid(proof: answer, challenge: challenge, showId: showId, nonce: "n1", key: ownKey))
    }

    @Test func missingOrMalformedProofIsRefused() {
        let challenge = ShowLiveInviteProof.newChallenge()
        #expect(!ShowLiveInviteProof.isValid(proof: nil, challenge: challenge, showId: showId, nonce: "n1", key: ownKey))
        #expect(!ShowLiveInviteProof.isValid(proof: "zz", challenge: challenge, showId: showId, nonce: "n1", key: ownKey))
        #expect(!ShowLiveInviteProof.isValid(proof: "abc", challenge: challenge, showId: showId, nonce: "n1", key: ownKey))
    }

    @Test func answerForAnOldChallengeOrOtherShowIsRefused() {
        let old = ShowLiveInviteProof.newChallenge()
        let answer = ShowLiveInviteProof.answer(challenge: old, showId: showId, nonce: "n1", key: ownKey)
        #expect(!ShowLiveInviteProof.isValid(
            proof: answer, challenge: ShowLiveInviteProof.newChallenge(), showId: showId, nonce: "n1", key: ownKey
        ))
        #expect(!ShowLiveInviteProof.isValid(proof: answer, challenge: old, showId: UUID(), nonce: "n1", key: ownKey))
    }

    @Test func proofIsTiedToItsNonce() {
        let challenge = ShowLiveInviteProof.newChallenge()
        let answer = ShowLiveInviteProof.answer(challenge: challenge, showId: showId, nonce: "n1", key: ownKey)
        #expect(!ShowLiveInviteProof.isValid(proof: answer, challenge: challenge, showId: showId, nonce: "n2", key: ownKey))
        #expect(!ShowLiveInviteProof.isValid(proof: answer, challenge: challenge, showId: showId, nonce: nil, key: ownKey))
    }

    @Test func onlyRealNoncesAreWellFormed() {
        #expect(ShowLiveInviteProof.isWellFormedNonce(ShowLiveInviteProof.newChallenge()))
        #expect(!ShowLiveInviteProof.isWellFormedNonce(""))
        #expect(!ShowLiveInviteProof.isWellFormedNonce(String(repeating: "a", count: 5000)))
        #expect(!ShowLiveInviteProof.isWellFormedNonce(String(repeating: "z", count: 32)))
    }

    @Test func challengesAreFreshEachTime() {
        let first = ShowLiveInviteProof.newChallenge()
        #expect(first.count == 32)
        #expect(first != ShowLiveInviteProof.newChallenge())
    }

    @Test func invitationCarriesTheProof() throws {
        let invite = ShowLiveInvitation(showId: showId, userHash: "0011223344556677", proof: "ab12", nonce: "n1")
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
