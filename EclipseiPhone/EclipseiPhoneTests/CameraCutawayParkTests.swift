//
//  CameraCutawayParkTests.swift
//  EclipseiPhoneTests
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import Foundation
import Testing
import AVFoundation
@testable import EclipseiPhone

@MainActor
struct CameraCutawayParkTests {

    @Test func presentCameraGoesLiveWithoutDisplay() {
        let mgr = ExternalDisplayManager.shared
        endCameraIfNeeded(mgr)

        mgr.presentCamera()
        #expect(mgr.isCameraModeActive == true)
        #expect(mgr.isCameraLive == true)

        endCameraIfNeeded(mgr)
        #expect(mgr.isCameraModeActive == false)
        #expect(mgr.isCameraLive == false)
    }

    @Test func disconnectedParkMarksCutawayActive() {
        let mgr = ExternalDisplayManager.shared
        endCameraIfNeeded(mgr)

        mgr.presentCamera()
        let source = PresentationSource.image(
            URL(fileURLWithPath: "/tmp/cutaway.jpg"),
            fill: true
        )
        mgr.parkCameraOnStill(source, kind: .cutaway(UUID()))
        #expect(mgr.isCameraParkedOnStill == true)
        #expect(mgr.isCameraModeActive == true)
        #expect(mgr.isCameraLive == false)

        mgr.resumeCameraFromStillPark()
        #expect(mgr.isCameraParkedOnStill == false)
        #expect(mgr.isCameraLive == true)

        endCameraIfNeeded(mgr)
    }

    @Test func commitBackgroundParkEndsCameraAndLeavesBackgroundOnProgram() {
        let mgr = ExternalDisplayManager.shared
        endCameraIfNeeded(mgr)

        mgr.presentCamera()
        guard let source = LogoStore.shared.presentationSource else {
            return
        }
        mgr.parkCameraOnStill(source, kind: .background)
        #expect(mgr.isCameraParkedOnStill == true)
        #expect(mgr.isCameraModeActive == true)
        #expect(mgr.isCameraTileLive == false)

        mgr.commitCameraParkToBackground()
        #expect(mgr.isCameraParkedOnStill == false)
        #expect(mgr.isCameraModeActive == false)
        #expect(mgr.isShowingBackgroundStill == true)

        endCameraIfNeeded(mgr)
    }

    @Test func parkedQuickChangeStillKeepsCameraTileLive() {
        let mgr = ExternalDisplayManager.shared
        endCameraIfNeeded(mgr)

        mgr.presentCamera()
        let id = UUID()
        mgr.parkCameraOnStill(
            PresentationSource.image(
                URL(fileURLWithPath: "/tmp/cutaway.jpg"),
                fill: true
            ),
            kind: .cutaway(id)
        )
        #expect(mgr.isParkedOnQuickChangeStill == true)
        #expect(mgr.isCameraTileLive == true)
        #expect(mgr.isCameraLive == false)

        endCameraIfNeeded(mgr)
    }

    @Test func airPlayDropDoesNotLeaveCameraAsReconnectSource() {
        let mgr = ExternalDisplayManager.shared
        endCameraIfNeeded(mgr)

        mgr.presentCamera()
        #expect(mgr.isCameraModeActive == true)
        mgr.dropCameraOverlayAfterDisconnect()
        #expect(mgr.isCameraModeActive == false)
        #expect(mgr.isCameraLive == false)

        mgr.presentCamera()
        #expect(mgr.isCameraLive == true)
        endCameraIfNeeded(mgr)
    }

    @Test func stageTapDoesNotEndLiveCamera() {
        let mgr = ExternalDisplayManager.shared
        endCameraIfNeeded(mgr)

        mgr.presentCamera()
        #expect(mgr.isCameraLive == true)

        let vc = CameraLiveViewController()
        vc.loadViewIfNeeded()
        vc.toggleAirPlayLive()
        #expect(mgr.isCameraLive == true)
        #expect(mgr.isCameraModeActive == true)

        endCameraIfNeeded(mgr)
    }

    @Test func programPreviewFillsTheDisplayModePanel() {
        #expect(CameraPreviewView.programVideoGravity == .resizeAspectFill)
    }

    private func endCameraIfNeeded(_ mgr: ExternalDisplayManager) {
        mgr.resumeCameraFromStillPark()
        if mgr.isCameraModeActive {
            mgr.stopCameraAndRestoreLibrary()
        }
    }
}
