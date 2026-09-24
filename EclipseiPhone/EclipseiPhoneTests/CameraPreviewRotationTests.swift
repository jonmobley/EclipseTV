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

    /// Front-lens frames reach the tap already flipped in sensor space, which reverses
    /// the sense of the rotation applied after. Rotating by the raw capture angle stood
    /// the hero and the panel mirror 180° out in a portrait hold.
    @Test func mirroredFrameTapReversesPortraitRotation() {
        #expect(
            CameraManager.frameTapRotationAngle(captureAngle: 90, isMirrored: true) == 270
        )
        #expect(
            CameraManager.frameTapRotationAngle(captureAngle: 270, isMirrored: true) == 90
        )
    }

    /// A flip commutes with 0° and 180°, which is why landscape holds always looked right.
    @Test func mirroredFrameTapLeavesLandscapeRotationAlone() {
        #expect(
            CameraManager.frameTapRotationAngle(captureAngle: 0, isMirrored: true) == 0
        )
        #expect(
            CameraManager.frameTapRotationAngle(captureAngle: 180, isMirrored: true) == 180
        )
    }

    @Test func unmirroredFrameTapKeepsCaptureAngle() {
        for angle in [0, 90, 180, 270] {
            #expect(
                CameraManager.frameTapRotationAngle(
                    captureAngle: angle,
                    isMirrored: false
                ) == angle
            )
        }
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
