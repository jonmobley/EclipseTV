//
//  VideoFormatSummaryTests.swift
//  EclipseiPhoneTests
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import Testing
import AVFoundation
@testable import EclipseiPhone

struct VideoFormatSummaryTests {

    // MARK: - Frame rate text

    @Test func ntscRatesReadAsTheWholeNumberPeopleExpect() {
        #expect(VideoFormatSummary.frameRateText(23.976) == "24")
        #expect(VideoFormatSummary.frameRateText(29.97) == "30")
        #expect(VideoFormatSummary.frameRateText(59.94) == "60")
    }

    @Test func wholeRatesHaveNoDecimalPoint() {
        #expect(VideoFormatSummary.frameRateText(24) == "24")
        #expect(VideoFormatSummary.frameRateText(30) == "30")
        #expect(VideoFormatSummary.frameRateText(240) == "240")
    }

    @Test func genuinelyFractionalRatesKeepADecimal() {
        #expect(VideoFormatSummary.frameRateText(23.5) == "23.5")
        #expect(VideoFormatSummary.frameRateText(12.3) == "12.3")
    }

    // MARK: - Frame rate source

    @Test func nominalRateIsPreferredWhenBelievable() {
        let rate = VideoFormatSummary.frameRate(
            nominalFrameRate: 60, minFrameDuration: CMTime(value: 1, timescale: 30)
        )
        #expect(rate == 60)
    }

    @Test func trackCadenceCoversAMissingNominalRate() {
        let rate = VideoFormatSummary.frameRate(
            nominalFrameRate: 0, minFrameDuration: CMTime(value: 1, timescale: 120)
        )
        #expect(rate != nil)
        #expect(abs((rate ?? 0) - 120) < 0.001)
    }

    @Test func unbelievableMetadataReportsNoRate() {
        #expect(VideoFormatSummary.frameRate(
            nominalFrameRate: 0, minFrameDuration: .invalid
        ) == nil)
        #expect(VideoFormatSummary.frameRate(
            nominalFrameRate: 100_000, minFrameDuration: CMTime(value: 1, timescale: 6000)
        ) == nil)
        #expect(VideoFormatSummary.frameRate(
            nominalFrameRate: 0, minFrameDuration: .zero
        ) == nil)
    }

    // MARK: - Description

    @Test func describesSizeAndRateTogether() {
        let text = VideoFormatSummary.describe(
            .init(displaySize: CGSize(width: 1080, height: 1920), framesPerSecond: 60)
        )
        #expect(text.contains("1080 × 1920"))
        #expect(text.contains("60 fps"))
    }

    @Test func omitsTheRateWhenItIsUnknown() {
        let text = VideoFormatSummary.describe(
            .init(displaySize: CGSize(width: 1920, height: 1080), framesPerSecond: nil)
        )
        #expect(text == "1920 × 1080")
    }

    @Test func omitsTheSizeWhenItIsUnknown() {
        let text = VideoFormatSummary.describe(
            .init(displaySize: .zero, framesPerSecond: 30)
        )
        #expect(text == "30 fps")
    }

    @Test func nothingKnownDescribesAsEmpty() {
        let text = VideoFormatSummary.describe(
            .init(displaySize: .zero, framesPerSecond: nil)
        )
        #expect(text.isEmpty)
    }

    @Test func missingFileHasNoSummary() async {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("missing-format-clip.mov")
        try? FileManager.default.removeItem(at: url)
        let info = await VideoFormatSummary.load(from: url)
        #expect(info == nil)
    }
}
