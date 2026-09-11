//
//  CameraLiveChromeTests.swift
//  EclipseiPhoneTests
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import Foundation
import Testing
import UIKit
@testable import EclipseiPhone

@MainActor
struct CameraLiveChromeTests {

    @Test func liveBadgeIsOnlyForLiveCameraFeed() {
        #expect(CameraLiveViewController.showsLiveBadge(isCameraLive: true))
        #expect(CameraLiveViewController.showsLiveBadge(isCameraLive: false) == false)
    }

    /// The feed can be the output with nobody watching it, so Practice Mode gets
    /// its own pill rather than claiming an audience with red LIVE.
    @Test func practiceFeedGetsAPracticePillNotLive() {
        #expect(
            CameraLiveBadgeState.resolve(
                isCameraLive: true, hasProgramOutput: false
            ) == .practice
        )
    }

    @Test func aWatchedFeedGetsTheLivePill() {
        #expect(
            CameraLiveBadgeState.resolve(
                isCameraLive: true, hasProgramOutput: true
            ) == .live
        )
    }

    @Test func aParkedCutawayHasNoPillEitherWay() {
        #expect(
            CameraLiveBadgeState.resolve(
                isCameraLive: false, hasProgramOutput: true
            ) == .hidden
        )
        #expect(
            CameraLiveBadgeState.resolve(
                isCameraLive: false, hasProgramOutput: false
            ) == .hidden
        )
    }

    @Test func tapHintShowsWhenCameraIsNotLive() {
        #expect(CameraLiveViewController.showsTapToGoLiveHint(isCameraLive: false))
        #expect(CameraLiveViewController.showsTapToGoLiveHint(isCameraLive: true) == false)
    }

    @Test func liveOutputThumbStaysVisibleWhileCameraIsLive() {
        #expect(CameraLiveViewController.showsLiveOutputThumb(isConnected: true))
        #expect(
            CameraLiveViewController.showsLiveOutputThumb(isConnected: false) == false
        )
    }

    @Test func openedCameraShowsCenteredHintAndHidesLiveBadge() {
        let mgr = ExternalDisplayManager.shared
        endCameraIfNeeded(mgr)

        let vc = CameraLiveViewController()
        vc.loadViewIfNeeded()
        vc.view.bounds = CGRect(x: 0, y: 0, width: 390, height: 844)
        vc.view.layoutIfNeeded()
        vc.refreshLiveChrome()

        #expect(vc.goLiveButton.isHidden)
        #expect(vc.tapToGoLiveHintView.isHidden == false)
        #expect(
            vc.tapToGoLiveHintView.accessibilityLabel == String(localized: "Go LIVE")
        )
        let panel = vc.panelView.convert(vc.panelView.bounds, to: vc.view)
        #expect(panel.width > 1)
        #expect(vc.tapToGoLiveHintView.bounds.width > 1)
        #expect(abs(vc.tapToGoLiveHintView.center.x - panel.midX) < 1)
        #expect(abs(vc.tapToGoLiveHintView.center.y - panel.midY) < 1)
    }

    @Test func cutawayParkHidesLiveBadgeAndShowsHint() {
        let mgr = ExternalDisplayManager.shared
        endCameraIfNeeded(mgr)

        mgr.presentCamera()
        #expect(mgr.isCameraLive)
        #expect(CameraLiveViewController.showsLiveBadge(isCameraLive: mgr.isCameraLive))
        #expect(
            CameraLiveViewController.showsTapToGoLiveHint(isCameraLive: mgr.isCameraLive)
            == false
        )

        mgr.parkCameraOnStill(
            PresentationSource.image(
                URL(fileURLWithPath: "/tmp/cutaway.jpg"),
                fill: true
            ),
            kind: .cutaway(UUID())
        )
        #expect(mgr.isCameraLive == false)
        #expect(
            CameraLiveViewController.showsLiveBadge(isCameraLive: mgr.isCameraLive)
            == false
        )
        #expect(CameraLiveViewController.showsTapToGoLiveHint(isCameraLive: mgr.isCameraLive))

        endCameraIfNeeded(mgr)
    }

    @Test func recordingTimerPillIsCenteredInCameraPreviewNotTheApp() {
        let vc = CameraLiveViewController()
        vc.loadViewIfNeeded()
        vc.view.bounds = CGRect(x: 0, y: 0, width: 844, height: 390)
        vc.view.layoutIfNeeded()

        // Letterbox the preview so app-center and preview-center differ.
        vc.panelView.frame = CGRect(x: 20, y: 0, width: 560, height: 390)
        vc.recordingTimerLabel.text = "1:23"
        vc.recordingTimerPillView.isHidden = false
        vc.layoutTopChromeInPanel()

        let panel = vc.panelView.convert(vc.panelView.bounds, to: vc.view)
        #expect(abs(panel.midX - vc.view.bounds.midX) > 10)
        #expect(abs(vc.recordingTimerPillView.center.x - panel.midX) < 1)
        #expect(abs(vc.recordingTimerPillView.center.x - vc.view.bounds.midX) > 10)
        #expect(panel.contains(vc.recordingTimerPillView.center))
        #expect(vc.recordingTimerPillView.backgroundColor != nil)
        #expect(
            abs(
                vc.recordingTimerPillView.layer.cornerRadius
                    - vc.recordingTimerPillView.bounds.height / 2
            ) < 0.5
        )
        #expect(vc.recordingTimerLabel.superview === vc.recordingTimerPillView)
    }

    @Test func photoShutterSitsBesideRecordInVerticalDock() {
        let shutter = CGRect(x: 159, y: 740, width: 72, height: 72)
        let photo = CameraLiveViewController.photoButtonFrame(
            shutterFrame: shutter,
            dockEdge: .bottom
        )
        #expect(photo.width == CameraLiveViewController.photoSize)
        #expect(photo.height == CameraLiveViewController.photoSize)
        #expect(photo.intersects(shutter) == false)
        #expect(
            abs(
                photo.maxX + CameraLiveViewController.shutterPairGap - shutter.minX
            ) < 0.5
        )
        #expect(abs(photo.midY - shutter.midY) < 0.5)
    }

    /// Clockwise turn: the row's leading end lands at the top, so Photo is above.
    @Test func photoShutterSitsAboveRecordInLeftDock() {
        let shutter = CGRect(x: 12, y: 159, width: 72, height: 72)
        let photo = CameraLiveViewController.photoButtonFrame(
            shutterFrame: shutter,
            dockEdge: .left
        )
        #expect(photo.intersects(shutter) == false)
        #expect(
            abs(
                photo.maxY + CameraLiveViewController.shutterPairGap - shutter.minY
            ) < 0.5
        )
        #expect(abs(photo.midX - shutter.midX) < 0.5)
    }

    /// Counterclockwise turn: the row's leading end lands at the bottom, so Photo
    /// is below — the same side of the thumb it was on in portrait.
    @Test func photoShutterSitsBelowRecordInRightDock() {
        let shutter = CGRect(x: 760, y: 159, width: 72, height: 72)
        let photo = CameraLiveViewController.photoButtonFrame(
            shutterFrame: shutter,
            dockEdge: .right
        )
        #expect(photo.intersects(shutter) == false)
        #expect(
            abs(
                shutter.maxY + CameraLiveViewController.shutterPairGap - photo.minY
            ) < 0.5
        )
        #expect(abs(photo.midX - shutter.midX) < 0.5)
    }

    @Test func portraitHoldDocksAtTheBottomWhateverTheSceneSays() {
        #expect(
            CameraLiveViewController.captureDockEdge(
                isPortraitLayout: true, interfaceOrientation: .landscapeLeft
            ) == .bottom
        )
        #expect(
            CameraLiveViewController.captureDockEdge(
                isPortraitLayout: true, interfaceOrientation: .portrait
            ) == .bottom
        )
    }

    /// Home indicator on the right means the phone turned counterclockwise and the
    /// portrait bottom edge is now on the right; on the left it is the mirror.
    @Test func landscapeDockFollowsTheTurn() {
        #expect(
            CameraLiveViewController.captureDockEdge(
                isPortraitLayout: false, interfaceOrientation: .landscapeRight
            ) == .right
        )
        #expect(
            CameraLiveViewController.captureDockEdge(
                isPortraitLayout: false, interfaceOrientation: .landscapeLeft
            ) == .left
        )
    }

    /// iPad multitasking can hand a landscape layout a portrait scene orientation;
    /// the dock keeps the trailing column rather than guessing a turn.
    @Test func landscapeLayoutWithoutALandscapeSceneKeepsTheRightDock() {
        #expect(
            CameraLiveViewController.captureDockEdge(
                isPortraitLayout: false, interfaceOrientation: .portrait
            ) == .right
        )
        #expect(
            CameraLiveViewController.captureDockEdge(
                isPortraitLayout: false, interfaceOrientation: .unknown
            ) == .right
        )
    }

    @Test func captureDockShowsSeparatePhotoAndRecordButtons() {
        let vc = CameraLiveViewController()
        vc.loadViewIfNeeded()
        vc.view.bounds = CGRect(x: 0, y: 0, width: 390, height: 844)
        vc.view.layoutIfNeeded()
        vc.refreshLiveChrome()

        #expect(vc.photoButton.superview === vc.view)
        #expect(vc.shutterButton.superview === vc.view)
        #expect(vc.photoButton.accessibilityLabel == "Take Photo")
        #expect(vc.shutterButton.accessibilityLabel == "Record")
        #expect(vc.photoButton.frame.width == CameraLiveViewController.photoSize)
        #expect(vc.shutterButton.frame.width == CameraLiveViewController.shutterSize)
        #expect(vc.photoButton.frame.intersects(vc.shutterButton.frame) == false)
        #expect(vc.photoButton.accessibilityHint?.contains("recording") == true)
    }

    @Test func portraitHoldCropsLandscapeShowToSixteenByNine() {
        let bounds = CGRect(x: 0, y: 0, width: 390, height: 844)
        let dock = CameraLiveViewController.captureDockSpan(safeEdge: 34)
        let panel = CameraLiveViewController.phoneCameraPanelRect(
            in: bounds,
            aspect: 16.0 / 9.0,
            dockEdge: .bottom,
            dockSpan: dock
        )
        #expect(abs(panel.width / panel.height - 16.0 / 9.0) < 0.01)
        #expect(panel.maxY <= bounds.height - dock + 0.5)
        #expect(abs(panel.width - bounds.width) < 0.5)
    }

    @Test func landscapeHoldKeepsLandscapeShowPanelBesideRightDock() {
        let bounds = CGRect(x: 0, y: 0, width: 844, height: 390)
        let dock = CameraLiveViewController.captureDockSpan(safeEdge: 21)
        let panel = CameraLiveViewController.phoneCameraPanelRect(
            in: bounds,
            aspect: 16.0 / 9.0,
            dockEdge: .right,
            dockSpan: dock
        )
        #expect(abs(panel.width / panel.height - 16.0 / 9.0) < 0.01)
        #expect(panel.maxX <= bounds.width - dock + 0.5)
    }

    /// A left dock reserves its strip on the left; the panel is the same size,
    /// shifted over so the two never overlap.
    @Test func leftDockReservesTheLeadingStripForTheShutter() {
        let bounds = CGRect(x: 0, y: 0, width: 844, height: 390)
        let dock = CameraLiveViewController.captureDockSpan(safeEdge: 21)
        let left = CameraLiveViewController.phoneCameraPanelRect(
            in: bounds,
            aspect: 16.0 / 9.0,
            dockEdge: .left,
            dockSpan: dock
        )
        let right = CameraLiveViewController.phoneCameraPanelRect(
            in: bounds,
            aspect: 16.0 / 9.0,
            dockEdge: .right,
            dockSpan: dock
        )
        #expect(abs(left.width / left.height - 16.0 / 9.0) < 0.01)
        #expect(left.minX >= dock - 0.5)
        #expect(abs(left.size.width - right.size.width) < 0.5)
        #expect(abs(left.size.height - right.size.height) < 0.5)
        #expect(abs(left.minX - (bounds.width - right.maxX)) < 0.5)
    }

    @Test func landscapeShowAllowsPortraitCameraInterface() {
        ExternalOutputOrientationFixture.with(.landscape) {
            let vc = CameraLiveViewController()
            vc.loadViewIfNeeded()
            #expect(vc.supportedInterfaceOrientations.contains(.portrait))
            #expect(vc.supportedInterfaceOrientations.contains(.landscapeLeft))
        }
    }

    @Test func portraitCameraLayoutDocksShutterUnderSixteenByNinePanel() {
        ExternalOutputOrientationFixture.with(.landscape) {
            let vc = CameraLiveViewController()
            vc.loadViewIfNeeded()
            vc.view.bounds = CGRect(x: 0, y: 0, width: 390, height: 844)
            vc.view.layoutIfNeeded()
            vc.refreshLiveChrome()

            let panel = vc.panelView.frame
            #expect(abs(panel.width / panel.height - 16.0 / 9.0) < 0.02)
            #expect(vc.isPhoneCameraPortraitLayout)
            #expect(vc.shutterButton.frame.minY >= panel.maxY - 0.5)
            #expect(abs(vc.shutterButton.center.x - panel.midX) < 1)
            #expect(vc.frameButton.frame.maxX <= vc.photoButton.frame.minX)
            #expect(vc.photoButton.frame.maxX <= vc.shutterButton.frame.minX)
            #expect(vc.shutterButton.frame.maxX <= vc.flipButton.frame.minX)
        }
    }

    /// Landscape is the portrait row turned with the phone: Frame keeps Photo's
    /// side of record, Flip the other, and both land on the edge the turn produced.
    @Test func landscapeDockIsTheBottomRowTurnedWithThePhone() {
        ExternalOutputOrientationFixture.with(.landscape) {
            let vc = CameraLiveViewController()
            vc.loadViewIfNeeded()
            vc.view.bounds = CGRect(x: 0, y: 0, width: 844, height: 390)
            vc.view.layoutIfNeeded()
            vc.refreshLiveChrome()

            let panel = vc.panelView.frame
            let shutter = vc.shutterButton.frame
            #expect(vc.isPhoneCameraPortraitLayout == false)
            #expect(abs(shutter.midY - panel.midY) < 1)
            #expect(shutter.intersects(panel) == false)
            #expect(vc.photoButton.frame.intersects(shutter) == false)

            switch vc.captureDockEdge {
            case .right:
                #expect(shutter.minX >= panel.maxX - 0.5)
                #expect(vc.flipButton.frame.maxY <= shutter.minY)
                #expect(vc.photoButton.frame.minY >= shutter.maxY)
                #expect(vc.frameButton.frame.minY >= vc.photoButton.frame.maxY)
            case .left:
                #expect(shutter.maxX <= panel.minX + 0.5)
                #expect(vc.frameButton.frame.maxY <= vc.photoButton.frame.minY)
                #expect(vc.photoButton.frame.maxY <= shutter.minY)
                #expect(vc.flipButton.frame.minY >= shutter.maxY)
            case .bottom:
                Issue.record("landscape layout must not dock at the bottom")
            }
        }
    }

    private func endCameraIfNeeded(_ mgr: ExternalDisplayManager) {
        mgr.resumeCameraFromStillPark()
        if mgr.isCameraModeActive {
            mgr.stopCameraAndRestoreLibrary()
        }
    }
}
