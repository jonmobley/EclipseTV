//
//  VideoTrimTests.swift
//  EclipseiPhoneTests
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import AVFoundation
import XCTest
@testable import EclipseiPhone

final class VideoTrimRangeTests: XCTestCase {

    func testStartsAsWholeVideo() {
        let range = VideoTrimRange(duration: 30)
        XCTAssertEqual(range.start, 0)
        XCTAssertEqual(range.end, 30)
        XCTAssertTrue(range.isFullLength)
    }

    func testHandlesCannotCrossOrLeaveTheVideo() {
        var range = VideoTrimRange(duration: 10)
        range.setStart(-3)
        XCTAssertEqual(range.start, 0)
        range.setEnd(99)
        XCTAssertEqual(range.end, 10)

        range.setEnd(4)
        range.setStart(9)
        XCTAssertEqual(range.start, 4 - VideoTrimRange.minimumLength, accuracy: 0.0001)
        range.setEnd(0)
        XCTAssertEqual(range.end, range.start + VideoTrimRange.minimumLength, accuracy: 0.0001)
    }

    func testTinyMoveCountsAsUntrimmed() {
        var range = VideoTrimRange(duration: 10)
        range.setStart(0.02)
        XCTAssertTrue(range.isFullLength)
        range.setStart(0.5)
        XCTAssertFalse(range.isFullLength)
        range.reset()
        XCTAssertTrue(range.isFullLength)
    }

    func testVideoShorterThanMinimumStaysWhole() {
        var range = VideoTrimRange(duration: 0.3)
        range.setStart(0.2)
        XCTAssertEqual(range.start, 0)
        XCTAssertEqual(range.end, 0.3, accuracy: 0.0001)
    }

    func testBadDurationIsSafe() {
        var range = VideoTrimRange(duration: .nan)
        XCTAssertEqual(range.duration, 0)
        range.setEnd(.infinity)
        XCTAssertEqual(range.end, 0)
        XCTAssertEqual(range.fraction(of: 5), 0)
    }

    func testFractionRoundTrip() {
        let range = VideoTrimRange(duration: 20)
        XCTAssertEqual(range.fraction(of: 5), 0.25, accuracy: 0.0001)
        XCTAssertEqual(range.time(atFraction: 0.75), 15, accuracy: 0.0001)
        XCTAssertEqual(range.time(atFraction: 2), 20)
    }

    func testLabels() {
        XCTAssertEqual(VideoTrimRange.label(7.44), "0:07.4")
        XCTAssertEqual(VideoTrimRange.label(62), "1:02.0")
        XCTAssertEqual(VideoTrimRange.label(3605), "1:00:05.0")
        XCTAssertEqual(VideoTrimRange.label(59.96), "1:00.0")
        XCTAssertEqual(VideoTrimRange.label(-1), "0:00.0")
    }
}

@MainActor
final class VideoTrimBarViewTests: XCTestCase {

    func testGrabsNearestHandle() {
        var range = VideoTrimRange(duration: 10)
        range.setStart(2)
        range.setEnd(8)
        let bar = VideoTrimBarView(range: range)
        bar.frame = CGRect(x: 0, y: 0, width: 336, height: 56)
        let startX = bar.x(for: 2)
        let endX = bar.x(for: 8)
        XCTAssertEqual(bar.edge(atX: startX - 5), .start)
        XCTAssertEqual(bar.edge(atX: endX + 5), .end)
        XCTAssertNil(bar.edge(atX: (startX + endX) / 2))
    }

    func testTimeMapsAcrossTrack() {
        let bar = VideoTrimBarView(range: VideoTrimRange(duration: 10))
        bar.frame = CGRect(x: 0, y: 0, width: 336, height: 56)
        XCTAssertEqual(bar.time(atX: bar.trackRect.minX), 0, accuracy: 0.0001)
        XCTAssertEqual(bar.time(atX: bar.trackRect.maxX), 10, accuracy: 0.0001)
        XCTAssertEqual(bar.time(atX: bar.trackRect.midX), 5, accuracy: 0.0001)
    }
}

final class VideoTrimExporterTests: XCTestCase {

    func testExportKeepsOnlyTheChosenPart() async throws {
        let source = try await Self.writeSampleVideo(seconds: 3)
        defer { try? FileManager.default.removeItem(at: source) }

        let trimmed = try await VideoTrimExporter.export(sourceURL: source, start: 1, end: 2.5)
        defer { try? FileManager.default.removeItem(at: trimmed) }

        let length = await VideoTrimExporter.durationSeconds(at: trimmed)
        XCTAssertEqual(length, 1.5, accuracy: 0.25)
        let tracks = try await AVURLAsset(url: trimmed).loadTracks(withMediaType: .video)
        XCTAssertEqual(tracks.count, 1)
    }

    func testRejectsEmptyRange() async {
        do {
            _ = try await VideoTrimExporter.export(
                sourceURL: URL(fileURLWithPath: "/nonexistent.mp4"), start: 2, end: 2
            )
            XCTFail("Expected an error")
        } catch {
            XCTAssertTrue(error is VideoTrimExporter.ExportError)
        }
    }

    /// Writes a small H.264 clip, one frame every 0.1 s.
    private static func writeSampleVideo(seconds: Int) async throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("trim-test-\(UUID().uuidString).mp4")
        let writer = try AVAssetWriter(outputURL: url, fileType: .mp4)
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: 64,
            AVVideoHeightKey: 64
        ])
        input.expectsMediaDataInRealTime = false
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: input,
            sourcePixelBufferAttributes: [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
                kCVPixelBufferWidthKey as String: 64,
                kCVPixelBufferHeightKey as String: 64
            ]
        )
        writer.add(input)
        XCTAssertTrue(writer.startWriting())
        writer.startSession(atSourceTime: .zero)

        let frames = seconds * 10
        for index in 0..<frames {
            while !input.isReadyForMoreMediaData {
                try await Task.sleep(nanoseconds: 5_000_000)
            }
            guard let pool = adaptor.pixelBufferPool else { break }
            var buffer: CVPixelBuffer?
            CVPixelBufferPoolCreatePixelBuffer(nil, pool, &buffer)
            guard let buffer else { break }
            CVPixelBufferLockBaseAddress(buffer, [])
            if let base = CVPixelBufferGetBaseAddress(buffer) {
                memset(base, Int32(index * 8 % 255), CVPixelBufferGetDataSize(buffer))
            }
            CVPixelBufferUnlockBaseAddress(buffer, [])
            adaptor.append(buffer, withPresentationTime: CMTime(value: CMTimeValue(index), timescale: 10))
        }
        input.markAsFinished()
        await writer.finishWriting()
        XCTAssertEqual(writer.status, .completed)
        return url
    }
}
