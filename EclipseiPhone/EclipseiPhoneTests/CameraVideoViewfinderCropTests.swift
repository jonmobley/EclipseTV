//
//  CameraVideoViewfinderCropTests.swift
//  EclipseiPhoneTests
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import AVFoundation
import Testing
import UIKit
@testable import EclipseiPhone

/// Recorded movies are trimmed to the shape the viewfinder shows (aspect-fill).
struct CameraVideoViewfinderCropTests {

    @Test func landscapeRecordingInVerticalTrimsToEvenNineBySixteen() throws {
        let rect = try #require(CameraFrameCompositor.videoCropRect(
            for: CGSize(width: 1920, height: 1080),
            aspect: MediaAspect.vertical
        ))
        #expect(rect.size == CGSize(width: 606, height: 1080))
        #expect(rect.minX == 657)
        #expect(rect.minY == 0)
    }

    @Test func uprightRecordingInVerticalIsLeftAlone() {
        #expect(CameraFrameCompositor.videoCropRect(
            for: CGSize(width: 1080, height: 1920),
            aspect: MediaAspect.vertical
        ) == nil)
    }

    @Test func fourByThreeInLandscapeTrimsTopAndBottom() throws {
        let rect = try #require(CameraFrameCompositor.videoCropRect(
            for: CGSize(width: 640, height: 480),
            aspect: MediaAspect.landscape
        ))
        #expect(rect == CGRect(x: 0, y: 60, width: 640, height: 360))
    }

    @Test func exportTrimsMovieToViewfinderShape() async throws {
        let source = try await Self.writeSolidMovie(width: 320, height: 240)
        defer { try? FileManager.default.removeItem(at: source) }

        let output = try await CameraFrameCompositor.exportViewfinderVideo(
            from: source,
            aspect: MediaAspect.vertical,
            frame: nil
        )
        let url = try #require(output)
        defer { try? FileManager.default.removeItem(at: url) }

        let size = try #require(await MediaAspect.videoDisplaySize(at: url))
        #expect(size == CGSize(width: 134, height: 240))
    }

    @Test func exportSkipsMovieThatAlreadyMatchesWithNoFrame() async throws {
        let source = try await Self.writeSolidMovie(width: 320, height: 180)
        defer { try? FileManager.default.removeItem(at: source) }

        let output = try await CameraFrameCompositor.exportViewfinderVideo(
            from: source,
            aspect: MediaAspect.landscape,
            frame: nil
        )
        #expect(output == nil)
    }

    // MARK: - Fixture

    /// A short solid-grey H.264 movie of the given size.
    private static func writeSolidMovie(width: Int, height: Int) async throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("ViewfinderCrop-\(UUID().uuidString).mov")
        let writer = try AVAssetWriter(outputURL: url, fileType: .mov)
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: width,
            AVVideoHeightKey: height,
        ])
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: input,
            sourcePixelBufferAttributes: [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
                kCVPixelBufferWidthKey as String: width,
                kCVPixelBufferHeightKey as String: height,
            ]
        )
        writer.add(input)
        writer.startWriting()
        writer.startSession(atSourceTime: .zero)
        for index in 0..<10 {
            while !input.isReadyForMoreMediaData {
                try await Task.sleep(nanoseconds: 5_000_000)
            }
            var buffer: CVPixelBuffer?
            CVPixelBufferCreate(
                nil, width, height, kCVPixelFormatType_32BGRA, nil, &buffer
            )
            let pixelBuffer = try #require(buffer)
            CVPixelBufferLockBaseAddress(pixelBuffer, [])
            if let base = CVPixelBufferGetBaseAddress(pixelBuffer) {
                memset(base, 0x80, CVPixelBufferGetDataSize(pixelBuffer))
            }
            CVPixelBufferUnlockBaseAddress(pixelBuffer, [])
            adaptor.append(
                pixelBuffer,
                withPresentationTime: CMTime(value: CMTimeValue(index), timescale: 30)
            )
        }
        input.markAsFinished()
        await writer.finishWriting()
        guard writer.status == .completed else {
            throw writer.error ?? CameraFrameCompositor.ExportError.compositionFailed
        }
        return url
    }
}
