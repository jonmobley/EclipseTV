//
//  CameraTileLivePlaceholderTests.swift
//  EclipseiPhoneTests
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import Testing
import UIKit
@testable import EclipseiPhone

@MainActor
struct CameraTileLivePlaceholderTests {

    @Test func liveCameraTileShowsCenteredIconInsteadOfFeed() {
        let mgr = ExternalDisplayManager.shared
        endCameraIfNeeded(mgr)
        mgr.presentCamera()
        #expect(mgr.isCameraLive)

        let cell = LibraryThumbnailCell(frame: CGRect(x: 0, y: 0, width: 160, height: 90))
        cell.configureCamera(isLive: true, lastFrame: nil, warmPreview: true)
        #expect(cell.placeholderIcon.isHidden == false)
        #expect(cell.placeholderIcon.image != nil)
        #expect(cell.cameraPreview == nil)
        #expect(cell.captionLabel.text == "Camera")

        endCameraIfNeeded(mgr)
    }

    @Test func lockedCameraTileUsesAmberStroke() {
        let cell = LibraryThumbnailCell(
            frame: CGRect(x: 0, y: 0, width: 160, height: 90)
        )
        cell.configureCamera(
            isLive: true,
            lastFrame: nil,
            warmPreview: false,
            isLocked: true
        )
        #expect(cell.cardView.layer.borderWidth == 3)
        #expect(cell.cardView.layer.borderColor == UIColor.systemOrange.cgColor)
        #expect(cell.accessibilityLabel == "Camera, live, locked")
    }

    @Test func liveCameraTileUsesRedStroke() {
        let cell = LibraryThumbnailCell(
            frame: CGRect(x: 0, y: 0, width: 160, height: 90)
        )
        cell.configureCamera(
            isLive: true,
            lastFrame: nil,
            warmPreview: false
        )
        #expect(cell.cardView.layer.borderWidth == 3)
        #expect(cell.cardView.layer.borderColor == UIColor.systemRed.cgColor)
        #expect(cell.accessibilityLabel == "Camera, live")
    }

    @Test func idleCameraTileHidesCenteredIconWithoutAStill() {
        let mgr = ExternalDisplayManager.shared
        endCameraIfNeeded(mgr)

        let cell = LibraryThumbnailCell(frame: CGRect(x: 0, y: 0, width: 160, height: 90))
        cell.configureCamera(isLive: false, lastFrame: nil, warmPreview: false)
        #expect(cell.placeholderIcon.isHidden)
    }

    private func endCameraIfNeeded(_ mgr: ExternalDisplayManager) {
        mgr.resumeCameraFromStillPark()
        if mgr.isCameraModeActive {
            mgr.stopCameraAndRestoreLibrary()
        }
    }
}
