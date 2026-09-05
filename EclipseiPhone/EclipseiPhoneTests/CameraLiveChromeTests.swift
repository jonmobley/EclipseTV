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
        #expect(vc.tapToGoLiveHintView.accessibilityLabel == "Tap screen to go LIVE")
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
            isVertical: true
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

    @Test func photoShutterSitsAboveRecordInLandscapeDock() {
        let shutter = CGRect(x: 760, y: 159, width: 72, height: 72)
        let photo = CameraLiveViewController.photoButtonFrame(
            shutterFrame: shutter,
            isVertical: false
        )
        #expect(photo.intersects(shutter) == false)
        #expect(
            abs(
                photo.maxY + CameraLiveViewController.shutterPairGap - shutter.minY
            ) < 0.5
        )
        #expect(abs(photo.midX - shutter.midX) < 0.5)
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
        let dock = CameraLiveViewController.captureDockSpan(safeTrailing: 34)
        let panel = CameraLiveViewController.phoneCameraPanelRect(
            in: bounds,
            aspect: 16.0 / 9.0,
            dockOnBottom: true,
            dockSpan: dock
        )
        #expect(abs(panel.width / panel.height - 16.0 / 9.0) < 0.01)
        #expect(panel.maxY <= bounds.height - dock + 0.5)
        #expect(abs(panel.width - bounds.width) < 0.5)
    }

    @Test func landscapeHoldKeepsLandscapeShowPanelBesideTrailingDock() {
        let bounds = CGRect(x: 0, y: 0, width: 844, height: 390)
        let dock = CameraLiveViewController.captureDockSpan(safeTrailing: 21)
        let panel = CameraLiveViewController.phoneCameraPanelRect(
            in: bounds,
            aspect: 16.0 / 9.0,
            dockOnBottom: false,
            dockSpan: dock
        )
        #expect(abs(panel.width / panel.height - 16.0 / 9.0) < 0.01)
        #expect(panel.maxX <= bounds.width - dock + 0.5)
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
        }
    }

    private func endCameraIfNeeded(_ mgr: ExternalDisplayManager) {
        mgr.resumeCameraFromStillPark()
        if mgr.isCameraModeActive {
            mgr.stopCameraAndRestoreLibrary()
        }
    }
}
