//
//  WebThumbnailAspectTests.swift
//  EclipseiPhoneTests
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//
//  YouTube's fallback poster (`hqdefault`) is 4:3 with black bars above and below a
//  16:9 picture. Cropped from the top like a web page, the card kept the top bar
//  and lost the bottom of the frame. Video posters crop from the middle.
//

import Testing
import UIKit
@testable import EclipseiPhone

@MainActor
struct WebThumbnailAspectTests {

    /// 480×360 with 45 px black bars top and bottom around a red 16:9 picture.
    private func letterboxedPoster() -> UIImage {
        let size = CGSize(width: 480, height: 360)
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        format.opaque = true
        return UIGraphicsImageRenderer(size: size, format: format).image { context in
            UIColor.black.setFill()
            context.fill(CGRect(origin: .zero, size: size))
            UIColor.red.setFill()
            context.fill(CGRect(x: 0, y: 45, width: 480, height: 270))
        }
    }

    /// Red component of the pixel at (x, y), in image pixels.
    private func red(at point: CGPoint, in image: UIImage) throws -> UInt8 {
        let cgImage = try #require(image.cgImage)
        var pixel = [UInt8](repeating: 0, count: 4)
        let context = try #require(CGContext(
            data: &pixel, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        // CoreGraphics draws bottom-up; flip y so `point` is measured from the top.
        let flippedY = CGFloat(cgImage.height) - point.y - 1
        context.draw(cgImage, in: CGRect(
            x: -point.x, y: -flippedY,
            width: CGFloat(cgImage.width), height: CGFloat(cgImage.height)
        ))
        return pixel[0]
    }

    @Test func centeredCropDropsBothLetterboxBars() throws {
        let cropped = ExternalOutputOrientationFixture.with(.landscape) {
            WebThumbnailAspect.croppedToDisplayAspect(letterboxedPoster(), centered: true)
        }
        let height = cropped.size.height * cropped.scale
        #expect(abs(height - 270) <= 1)
        let top = try red(at: CGPoint(x: 240, y: 2), in: cropped)
        let bottom = try red(at: CGPoint(x: 240, y: height - 3), in: cropped)
        #expect(top > 200)
        #expect(bottom > 200)
    }

    /// Web pages still keep their top: that is what the TV shows first.
    @Test func pageCropKeepsTheTop() throws {
        let cropped = ExternalOutputOrientationFixture.with(.landscape) {
            WebThumbnailAspect.croppedToDisplayAspect(letterboxedPoster())
        }
        let top = try red(at: CGPoint(x: 240, y: 2), in: cropped)
        #expect(top < 40)
    }

    /// HLS playlists have no frames to grab, so a file poster is never attempted.
    @Test func filePostersSkipHLSPlaylists() throws {
        let mp4 = try #require(URL(string: "https://example.com/clip.mp4?token=1"))
        let hls = try #require(URL(string: "https://example.com/live/index.m3u8"))
        #expect(WebVideoPosterFetcher.canSampleFile(mp4))
        #expect(!WebVideoPosterFetcher.canSampleFile(hls))
    }

    /// A server that never answers must give up at the deadline and free the slot,
    /// not wait for the network timeout (about a minute) behind the cancel.
    @Test func stalledFilePosterGivesUpAtTheDeadline() async throws {
        // Non-routable address: the connection neither succeeds nor fails quickly.
        let url = try #require(URL(string: "http://10.255.255.1/clip.mp4"))
        let start = Date()
        let image = await WebVideoPosterFetcher.poster(at: url, timeout: 0.5)
        #expect(image == nil)
        #expect(Date().timeIntervalSince(start) < 5)
    }
}
