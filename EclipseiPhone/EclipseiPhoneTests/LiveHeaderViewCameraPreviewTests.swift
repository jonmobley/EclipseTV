//
//  LiveHeaderViewCameraPreviewTests.swift
//  EclipseiPhoneTests
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import Testing
import UIKit
@testable import EclipseiPhone

@MainActor
struct LiveHeaderViewCameraPreviewTests {

    @Test func showCameraPreviewMirrorsFeedAndHidesGlyph() {
        let header = makeHeader()
        header.configureOverlay(
            title: "Camera",
            systemImage: "camera.fill",
            fillColor: UIColor(white: 0.12, alpha: 1),
            showsLiveBadge: true
        )
        #expect(header.placeholderIcon.isHidden == false)
        #expect(header.titleLabel.isHidden == false)

        header.showCameraPreview()
        #expect(header.isCameraPreviewActive)
        #expect(header.cameraPreviewHost?.isHidden == false)
        #expect(header.titleLabel.isHidden)
        #expect(header.liveBadge.isHidden == false)

        header.clearCameraPreview()
        #expect(header.isCameraPreviewActive == false)
        #expect(header.cameraPreviewHost?.isHidden == true)
    }

    @Test func overlayWithoutKeepClearsCameraPreview() {
        let header = makeHeader()
        header.showCameraPreview()
        #expect(header.isCameraPreviewActive)

        header.configureOverlay(
            title: "Blackout",
            systemImage: "moon.fill",
            fillColor: .black
        )
        #expect(header.isCameraPreviewActive == false)
    }

    @Test func overlayKeepCameraPreviewLeavesMirrorRunning() {
        let header = makeHeader()
        header.showCameraPreview()
        header.configureOverlay(
            title: "Camera",
            systemImage: "camera.fill",
            fillColor: UIColor(white: 0.12, alpha: 1),
            keepCameraPreview: true
        )
        #expect(header.isCameraPreviewActive)
        #expect(header.titleLabel.isHidden)
    }

    /// The Camera overlay glyph is not the live feed — Practice Mode must call
    /// `showCameraPreview()` after configure, same as the web hero path.
    @Test func cameraOverlayDoesNotStartTheMirrorByItself() {
        let header = makeHeader()
        header.configureOverlay(
            title: "Camera",
            systemImage: "camera.fill",
            fillColor: UIColor(white: 0.12, alpha: 1)
        )
        #expect(header.isCameraPreviewActive == false)
        #expect(header.placeholderIcon.isHidden == false)
    }

    private func makeHeader() -> LiveHeaderView {
        LiveHeaderView(frame: CGRect(x: 0, y: 0, width: 320, height: 180))
    }
}
