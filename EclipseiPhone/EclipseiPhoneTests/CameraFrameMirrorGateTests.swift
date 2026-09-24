//
//  CameraFrameMirrorGateTests.swift
//  EclipseiPhoneTests
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import Testing
@testable import EclipseiPhone

struct CameraFrameMirrorGateTests {

    @Test func openGateDeliversEveryFrame() {
        var gate = CameraFrameMirrorGate()
        #expect(gate.action() == .deliver)
        #expect(gate.action() == .deliver)
    }

    /// Frames from the outgoing lens, and the new lens before the retarget, must
    /// not reach the mirrors — those are the frames that drew at the old angle.
    @Test func swapDropsFramesUntilCommitThenClaimsExactlyOne() {
        var gate = CameraFrameMirrorGate()
        gate.pause()
        #expect(gate.action() == .drop)
        #expect(gate.action() == .drop)

        gate.awaitFrame()
        #expect(gate.action() == .retarget(generation: 1))
        // Frames landing while main is retargeting are dropped, not queued.
        #expect(gate.action() == .drop)

        let resumed = gate.resume(generation: 1)
        #expect(resumed)
        #expect(gate.action() == .deliver)
    }

    /// A second Flip while the first is still retargeting on main: the first
    /// resume must not reopen the gate for the second swap's frames.
    @Test func staleResumeIsRefusedAfterANewerSwapPaused() {
        var gate = CameraFrameMirrorGate()
        gate.pause()
        gate.awaitFrame()
        #expect(gate.action() == .retarget(generation: 1))

        gate.pause()
        let staleResumed = gate.resume(generation: 1)
        #expect(staleResumed == false)
        #expect(gate.action() == .drop)

        gate.awaitFrame()
        #expect(gate.action() == .retarget(generation: 2))
        let resumed = gate.resume(generation: 2)
        #expect(resumed)
        #expect(gate.action() == .deliver)
    }

    /// A stopped session sends no frame to retarget on, so the gate opens at once
    /// instead of leaving the next start dropping frames.
    @Test func openReleasesAPausedGateWithoutAFrame() {
        var gate = CameraFrameMirrorGate()
        gate.pause()
        gate.open()
        #expect(gate.action() == .deliver)
    }

    @Test func awaitFrameOnlyFollowsAPause() {
        var gate = CameraFrameMirrorGate()
        gate.awaitFrame()
        #expect(gate.action() == .deliver)
    }
}
