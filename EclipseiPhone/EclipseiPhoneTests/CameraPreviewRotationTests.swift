//
//  CameraPreviewRotationTests.swift
//  EclipseiPhoneTests
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import Foundation
import Testing
import UIKit
@testable import EclipseiPhone

struct CameraPreviewRotationTests {

    /// A portrait phone on a Landscape Show must rotate the sensor 90°, not 0°:
    /// the 16:9 panel is pinned separately, and fill gravity makes this an upright crop.
    /// Pinning the angle to the mode put program on its side.
    @Test func portraitHoldStaysUprightOnLandscapeOutput() {
        #expect(
            CameraPreviewView.programRotationAngle(phoneOrientation: .portrait) == 90
        )
        #expect(
            CameraPreviewView.programRotationAngle(
                phoneOrientation: .portraitUpsideDown
            ) == 270
        )
    }

    @Test func landscapeHoldStaysUprightOnVerticalOutput() {
        #expect(
            CameraPreviewView.programRotationAngle(phoneOrientation: .landscapeRight) == 0
        )
        #expect(
            CameraPreviewView.programRotationAngle(phoneOrientation: .landscapeLeft) == 180
        )
    }

    @Test func unknownHoldFallsBackToPortrait() {
        #expect(
            CameraPreviewView.programRotationAngle(phoneOrientation: .unknown) == 90
        )
    }

    @Test func frontCameraProgramIsNotMirrored() {
        #expect(
            CameraPreviewView.shouldMirrorPreview(
                isExternalDisplay: true,
                cameraPosition: .front
            ) == false
        )
        #expect(
            CameraPreviewView.shouldMirrorPreview(
                isExternalDisplay: false,
                cameraPosition: .front
            ) == true
        )
    }

    @Test func backCameraIsNeverMirrored() {
        #expect(
            CameraPreviewView.shouldMirrorPreview(
                isExternalDisplay: true,
                cameraPosition: .back
            ) == false
        )
        #expect(
            CameraPreviewView.shouldMirrorPreview(
                isExternalDisplay: false,
                cameraPosition: .back
            ) == false
        )
    }
}
