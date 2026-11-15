//
//  MediaAspectRotationTests.swift
//  EclipseiPhoneTests
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import Testing
import UIKit
@testable import EclipseiPhone

struct MediaAspectRotationTests {

    @Test func rotatedClockwiseSwapsDimensions() {
        let image = solidImage(width: 20, height: 10)
        let rotated = MediaAspect.rotatedClockwise(image)
        #expect(rotated.size == CGSize(width: 10, height: 20))
        #expect(rotated.imageOrientation == .up)
    }

    @Test func rotatedCounterclockwiseSwapsDimensions() {
        let image = solidImage(width: 20, height: 10)
        let rotated = MediaAspect.rotatedCounterclockwise(image)
        #expect(rotated.size == CGSize(width: 10, height: 20))
        #expect(rotated.imageOrientation == .up)
    }

    @Test func fourClockwiseRotationsRestoreSize() {
        let image = solidImage(width: 20, height: 10)
        var current = image
        for _ in 0..<4 {
            current = MediaAspect.rotatedClockwise(current)
        }
        #expect(current.size == CGSize(width: 20, height: 10))
    }

    // MARK: - Centre crop (camera shutter matches the aspect-fill viewfinder)

    @Test func centerCropPortraitSensorToVerticalTrimsSides() {
        let image = solidImage(width: 360, height: 480) // upright 3:4 camera still
        let cropped = MediaAspect.centerCropped(image, toAspect: MediaAspect.vertical)
        #expect(cropped.size == CGSize(width: 270, height: 480))
    }

    @Test func centerCropLandscapeSensorToLandscapeTrimsTopAndBottom() {
        let image = solidImage(width: 480, height: 360) // 4:3 camera still
        let cropped = MediaAspect.centerCropped(image, toAspect: MediaAspect.landscape)
        #expect(cropped.size == CGSize(width: 480, height: 270))
    }

    @Test func centerCropLeavesMatchingImageAlone() {
        let image = solidImage(width: 90, height: 160)
        let cropped = MediaAspect.centerCropped(image, toAspect: MediaAspect.vertical)
        #expect(cropped.size == image.size)
    }

    @Test func centerCropToSquareStillWorks() {
        let image = solidImage(width: 40, height: 10)
        #expect(MediaAspect.centerCroppedToSquare(image).size == CGSize(width: 10, height: 10))
    }

    private func solidImage(width: CGFloat, height: CGFloat) -> UIImage {
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        format.opaque = false
        let size = CGSize(width: width, height: height)
        return UIGraphicsImageRenderer(size: size, format: format).image { ctx in
            UIColor.red.setFill()
            ctx.fill(CGRect(origin: .zero, size: size))
        }
    }
}
