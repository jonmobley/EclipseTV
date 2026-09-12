//
//  VideoCropFrameRateTests.swift
//  EclipseiPhoneTests
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import Testing
import AVFoundation
@testable import EclipseiPhone

struct VideoCropFrameRateTests {

    @Test func exactTrackCadenceIsCopiedVerbatim() {
        let ntsc = CMTime(value: 1001, timescale: 24000)
        let result = VideoCropExporter.outputFrameDuration(
            nominalFrameRate: 23.976, minFrameDuration: ntsc
        )
        // Copied, not recomputed: 23.976 must not quantise to a flat 24.
        #expect(result == ntsc)
    }

    @Test func highFrameRateSourcesKeepTheirRate() {
        for fps: Int32 in [48, 60, 120, 240] {
            let cadence = CMTime(value: 1, timescale: fps)
            let result = VideoCropExporter.outputFrameDuration(
                nominalFrameRate: Float(fps), minFrameDuration: cadence
            )
            #expect(result == cadence)
        }
    }

    @Test func nominalRateIsUsedWhenTrackCadenceIsMissing() {
        let result = VideoCropExporter.outputFrameDuration(
            nominalFrameRate: 60, minFrameDuration: .invalid
        )
        #expect(abs(result.seconds - 1.0 / 60.0) < 0.0005)
    }

    @Test func indefiniteCadenceFallsThroughToNominal() {
        let result = VideoCropExporter.outputFrameDuration(
            nominalFrameRate: 25, minFrameDuration: .indefinite
        )
        #expect(abs(result.seconds - 1.0 / 25.0) < 0.0005)
    }

    @Test func noUsableMetadataLandsOnThirtyFps() {
        let result = VideoCropExporter.outputFrameDuration(
            nominalFrameRate: 0, minFrameDuration: .zero
        )
        #expect(result == VideoCropExporter.fallbackFrameDuration)
        #expect(abs(result.seconds - 1.0 / 30.0) < 0.0005)
    }

    @Test func implausibleRatesAreNotPreserved() {
        // 6000 fps from a corrupt header should not become the export cadence.
        let bogus = CMTime(value: 1, timescale: 6000)
        let result = VideoCropExporter.outputFrameDuration(
            nominalFrameRate: 30, minFrameDuration: bogus
        )
        #expect(abs(result.seconds - 1.0 / 30.0) < 0.0005)

        let bothBogus = VideoCropExporter.outputFrameDuration(
            nominalFrameRate: 100_000, minFrameDuration: bogus
        )
        #expect(bothBogus == VideoCropExporter.fallbackFrameDuration)
    }

    @Test func negativeCadenceIsRejected() {
        let result = VideoCropExporter.outputFrameDuration(
            nominalFrameRate: 30, minFrameDuration: CMTime(value: -1, timescale: 30)
        )
        #expect(abs(result.seconds - 1.0 / 30.0) < 0.0005)
    }
}
