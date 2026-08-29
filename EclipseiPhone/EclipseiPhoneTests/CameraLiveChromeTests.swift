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

    private func endCameraIfNeeded(_ mgr: ExternalDisplayManager) {
        mgr.resumeCameraFromStillPark()
        if mgr.isCameraModeActive {
            mgr.stopCameraAndRestoreLibrary()
        }
    }
}
