//
//  CameraVideoStabilizationTests.swift
//  EclipseiPhoneTests
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import AVFoundation
import Testing
@testable import EclipseiPhone

struct CameraVideoStabilizationTests {

    @Test func liveCandidatesPreferPreviewOptimizedThenAuto() {
        let modes = CameraVideoStabilization.candidates(
            for: .live,
            lowLatencyAvailable: false
        )
        #expect(modes == [.previewOptimized, .auto])
    }

    @Test func liveCandidatesInsertLowLatencyWhenAvailable() {
        let modes = CameraVideoStabilization.candidates(
            for: .live,
            lowLatencyAvailable: true
        )
        #expect(modes == [.previewOptimized, .lowLatency, .auto])
    }

    @Test func recordingCandidatesPreferStandardThenAuto() {
        let modes = CameraVideoStabilization.candidates(
            for: .recording,
            lowLatencyAvailable: true
        )
        #expect(modes == [.standard, .auto])
    }

    @Test func livePrefersPreviewOptimizedOverLaterFallbacks() {
        let mode = CameraVideoStabilization.preferredMode(
            for: .live,
            lowLatencyAvailable: true
        ) { _ in true }
        #expect(mode == .previewOptimized)
    }

    @Test func liveFallsBackToLowLatencyWhenPreviewOptimizedIsUnsupported() {
        let mode = CameraVideoStabilization.preferredMode(
            for: .live,
            lowLatencyAvailable: true
        ) { $0 != .previewOptimized }
        #expect(mode == .lowLatency)
    }

    @Test func liveFallsBackToAutoWhenOnlyAutoIsSupported() {
        let mode = CameraVideoStabilization.preferredMode(
            for: .live,
            lowLatencyAvailable: false
        ) { $0 == .auto }
        #expect(mode == .auto)
    }

    @Test func liveTurnsOffWhenNothingIsSupported() {
        let mode = CameraVideoStabilization.preferredMode(
            for: .live,
            lowLatencyAvailable: true
        ) { _ in false }
        #expect(mode == .off)
    }

    @Test func recordingPrefersStandardOverAuto() {
        let mode = CameraVideoStabilization.preferredMode(
            for: .recording,
            lowLatencyAvailable: true
        ) { _ in true }
        #expect(mode == .standard)
    }

    @Test func recordingFallsBackToAutoWhenStandardIsUnsupported() {
        let mode = CameraVideoStabilization.preferredMode(
            for: .recording
        ) { $0 == .auto }
        #expect(mode == .auto)
    }

    @Test func captureModeMapsPreviewOptimizedAndStandard() {
        #expect(
            CameraVideoStabilization.captureMode(for: .previewOptimized)
                == .previewOptimized
        )
        #expect(CameraVideoStabilization.captureMode(for: .standard) == .standard)
        #expect(CameraVideoStabilization.captureMode(for: .auto) == .auto)
        #expect(CameraVideoStabilization.captureMode(for: .off) == .off)
    }

    @Test func captureModeMapsLowLatencyWhenTheOSSupportsIt() {
        if #available(iOS 26.0, *) {
            #expect(
                CameraVideoStabilization.captureMode(for: .lowLatency) == .lowLatency
            )
        } else {
            #expect(CameraVideoStabilization.captureMode(for: .lowLatency) == nil)
        }
    }
}
