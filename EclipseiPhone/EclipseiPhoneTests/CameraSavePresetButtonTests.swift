//
//  CameraSavePresetButtonTests.swift
//  EclipseiPhoneTests
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import Foundation
import Testing
@testable import EclipseiPhone

/// The header Save button shows only while a frame is on the camera and Camera was
/// opened from a Show (the preset tile needs a Show to go into).
struct CameraSavePresetButtonTests {

    @Test func showsWithFrameOnCameraFromAShow() {
        #expect(CameraLiveViewController.showsSavePresetButton(
            hasDestinationShow: true, selectedFrameId: UUID()
        ))
    }

    @Test func hiddenWithNoFrameOnCamera() {
        #expect(!CameraLiveViewController.showsSavePresetButton(
            hasDestinationShow: true, selectedFrameId: nil
        ))
    }

    @Test func hiddenWithoutAShow() {
        #expect(!CameraLiveViewController.showsSavePresetButton(
            hasDestinationShow: false, selectedFrameId: UUID()
        ))
    }
}
