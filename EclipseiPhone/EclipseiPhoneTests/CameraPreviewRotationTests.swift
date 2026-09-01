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

    @Test func landscapeOutputIgnoresPortraitHold() {
        #expect(
            CameraPreviewView.programRotationAngle(
                isVerticalMode: false,
                phoneOrientation: .portrait
            ) == 0
        )
        #expect(
            CameraPreviewView.programRotationAngle(
                isVerticalMode: false,
                phoneOrientation: .portraitUpsideDown
            ) == 0
        )
    }

    @Test func verticalOutputIgnoresLandscapeHold() {
        #expect(
            CameraPreviewView.programRotationAngle(
                isVerticalMode: true,
                phoneOrientation: .landscapeRight
            ) == 90
        )
        #expect(
            CameraPreviewView.programRotationAngle(
                isVerticalMode: true,
                phoneOrientation: .landscapeLeft
            ) == 90
        )
    }

    @Test func sameAxisFlipStaysInDisplayMode() {
        #expect(
            CameraPreviewView.programRotationAngle(
                isVerticalMode: false,
                phoneOrientation: .landscapeRight
            ) == 0
        )
        #expect(
            CameraPreviewView.programRotationAngle(
                isVerticalMode: false,
                phoneOrientation: .landscapeLeft
            ) == 180
        )
        #expect(
            CameraPreviewView.programRotationAngle(
                isVerticalMode: true,
                phoneOrientation: .portrait
            ) == 90
        )
        #expect(
            CameraPreviewView.programRotationAngle(
                isVerticalMode: true,
                phoneOrientation: .portraitUpsideDown
            ) == 270
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
