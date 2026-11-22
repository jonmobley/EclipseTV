//
//  CameraOperatorModeTests.swift
//  EclipseiPhoneTests
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import CoreImage
import EclipsePhoneCameraProtocol
import Foundation
import Testing
@testable import EclipseiPhone

/// Camera Mode rules that decide what the Mac sees and what the volunteer reads.
@MainActor
struct CameraOperatorModeTests {

    // MARK: - Mac picture shape

    @Test func landscapeFeedKeepsEitherLandscapeHold() {
        #expect(MacProgramCompositor.lockedAngle(0, lastAccepted: 0, isVertical: false) == 0)
        #expect(MacProgramCompositor.lockedAngle(180, lastAccepted: 0, isVertical: false) == 180)
    }

    @Test func turningUprightKeepsTheLastLandscapeAngle() {
        #expect(MacProgramCompositor.lockedAngle(90, lastAccepted: 180, isVertical: false) == 180)
        #expect(MacProgramCompositor.lockedAngle(270, lastAccepted: 0, isVertical: false) == 0)
    }

    @Test func verticalFeedOnlyTakesUprightAngles() {
        #expect(MacProgramCompositor.lockedAngle(270, lastAccepted: 90, isVertical: true) == 270)
        #expect(MacProgramCompositor.lockedAngle(0, lastAccepted: 270, isVertical: true) == 270)
        #expect(MacProgramCompositor.lockedAngle(180, lastAccepted: 0, isVertical: true) == 90)
    }

    @Test func anglesWrapAround() {
        #expect(MacProgramCompositor.lockedAngle(-180, lastAccepted: 0, isVertical: false) == 180)
        #expect(MacProgramCompositor.lockedAngle(360, lastAccepted: 180, isVertical: false) == 0)
    }

    @Test func clockwiseTurnsMapToImageOrientations() {
        #expect(MacProgramCompositor.orientation(forClockwiseDegrees: 0) == .up)
        #expect(MacProgramCompositor.orientation(forClockwiseDegrees: 90) == .right)
        #expect(MacProgramCompositor.orientation(forClockwiseDegrees: 180) == .down)
        #expect(MacProgramCompositor.orientation(forClockwiseDegrees: 270) == .left)
    }

    // MARK: - Volunteer wording

    @Test func liveHidesTheConnectCard() {
        #expect(CameraOperatorChromeText.cardMessage(for: .live) == nil)
        #expect(CameraOperatorChromeText.pill(for: .live).title == "● Live on Mac")
    }

    @Test func notConnectedExplainsWhereTheQRCodeIs() {
        let message = CameraOperatorChromeText.cardMessage(for: .notConnected)
        #expect(message?.contains("Phone Camera") == true)
    }

    @Test func failureShowsItsReason() {
        #expect(CameraOperatorChromeText.cardMessage(for: .failed("Mac is asleep")) == "Mac is asleep")
    }

    // MARK: - Reconnecting

    @Test func refusedLinkAsksForANewScan() {
        let refused = PhoneCameraAPIError.badStatus.errorDescription ?? ""
        #expect(CameraOperatorMode.isRejectedLink(refused))
    }

    @Test func networkDropIsRetried() {
        let dropped = PhoneCameraAPIError.unreachableMac.errorDescription ?? ""
        #expect(!CameraOperatorMode.isRejectedLink(dropped))
        #expect(!CameraOperatorMode.isRejectedLink("Disconnected from Mac"))
    }

    // MARK: - Which Macs are allowed

    @Test func localNetworkMacsAreAllowed() {
        for host in ["192.168.1.20", "10.0.0.5", "172.20.1.1", "169.254.3.4", "Studio-Mac.local", "fe80::1", "[fd12::5]"] {
            #expect(CameraModeLinkPolicy.isLocalNetworkHost(host), "\(host)")
        }
    }

    @Test func internetHostsAreRefused() {
        for host in ["8.8.8.8", "172.32.0.1", "example.com", "evil.local.example.com", "2001:db8::1", "999.1.1.1"] {
            #expect(!CameraModeLinkPolicy.isLocalNetworkHost(host), "\(host)")
        }
    }

    @Test func linksAreCheckedByTheirMacAddress() {
        #expect(CameraModeLinkPolicy.isAllowed("eclipse://phone-camera?h=192.168.1.20&p=7880&t=abc"))
        #expect(!CameraModeLinkPolicy.isAllowed("eclipse://phone-camera?h=203.0.113.9&p=7880&t=abc"))
        #expect(!CameraModeLinkPolicy.isAllowed("not a link"))
    }
}
