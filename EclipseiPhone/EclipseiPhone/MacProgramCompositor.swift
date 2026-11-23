//
//  MacProgramCompositor.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import CoreImage
import CoreMedia
import CoreVideo
import EclipsePhoneCameraClient
import UIKit

// MARK: - MacProgramCompositor

/// Draws the camera picture the Mac receives in Camera Mode.
///
/// The TV gets the camera, the selected frame and parked stills as separate
/// layers it stacks itself. The Mac receives one video stream, so each camera
/// frame is drawn here with the same look the TV shows: the selected frame on
/// top, or the parked still (Background / quick-change picture) in place of the
/// camera. The front lens is un-mirrored, like the TV, so text reads correctly.
///
/// Thread safety: `render` runs on `CameraManager.frameQueue`; `start`, `stop`
/// and `update` come from the main thread. Shared state sits behind `lock`.
final class MacProgramCompositor: @unchecked Sendable {

    // MARK: - Types

    /// What the Mac should show besides the live camera.
    struct Program {
        /// Selected camera frame (transparent PNG), drawn over the camera.
        var overlay: CIImage?
        /// Parked still that replaces the camera, or nil for the camera.
        var still: CIImage?
        /// Output size in pixels (16:9 or 9:16, per Display Mode).
        var outputSize: CGSize
    }

    // MARK: - Properties

    static let shared = MacProgramCompositor()

    private let lock = NSLock()
    private var feed: PhoneCameraFrameFeed?
    private var program = Program(overlay: nil, still: nil, outputSize: CGSize(width: 1920, height: 1080))
    private var lastAcceptedAngle = 0
    private let context = CIContext(options: [.useSoftwareRenderer: false, .cacheIntermediates: false])
    private var pool: CVPixelBufferPool?
    private var poolSize: CGSize = .zero

    // MARK: - Public Interface

    /// True while frames are being sent to a Mac (cheap check per frame).
    var isStreaming: Bool {
        lock.lock()
        let current = feed
        lock.unlock()
        return current?.isStreaming ?? false
    }

    /// Starts drawing frames into `feed`.
    /// - Parameter feed: The Mac stream's frame input.
    func start(feed: PhoneCameraFrameFeed) {
        lock.lock()
        self.feed = feed
        lock.unlock()
    }

    /// Stops drawing; later frames are ignored.
    func stop() {
        lock.lock()
        feed = nil
        lock.unlock()
    }

    /// Replaces what is drawn over or instead of the camera.
    /// - Parameter program: The new frame / still / size.
    func update(_ program: Program) {
        lock.lock()
        self.program = program
        lock.unlock()
    }

    /// Draws one camera frame for the Mac and sends it.
    /// - Parameters:
    ///   - sampleBuffer: Frame-tap buffer in the sensor's own orientation.
    ///   - rotationDegrees: Clockwise turn that stands the frame upright.
    ///   - isMirrored: True for front-lens buffers (flipped left to right).
    func render(_ sampleBuffer: CMSampleBuffer, rotationDegrees: Int, isMirrored: Bool) {
        lock.lock()
        let target = feed
        let current = program
        let isVertical = current.outputSize.height > current.outputSize.width
        let angle = Self.lockedAngle(rotationDegrees, lastAccepted: lastAcceptedAngle, isVertical: isVertical)
        lastAcceptedAngle = angle
        lock.unlock()
        guard let target, target.isStreaming,
              let pixels = CMSampleBufferGetImageBuffer(sampleBuffer),
              let output = makeOutputBuffer(size: current.outputSize) else { return }
        let camera = Self.uprightCamera(CIImage(cvPixelBuffer: pixels), degrees: angle, isMirrored: isMirrored)
        let image = Self.compose(camera: camera, program: current)
        context.render(image, to: output, bounds: CGRect(origin: .zero, size: current.outputSize), colorSpace: nil)
        target.push(output, rotationDegrees: 0, timestamp: CMSampleBufferGetPresentationTimeStamp(sampleBuffer))
    }

    // MARK: - Pure Helpers

    /// Keeps the Mac picture in the Display Mode shape when the phone turns.
    ///
    /// A landscape feed accepts only 0° / 180° (either landscape hold); turning
    /// the phone upright keeps the last landscape angle instead of sending a
    /// sideways picture. Vertical works the same with 90° / 270°.
    /// - Parameters:
    ///   - degrees: Upright angle for the phone's current hold.
    ///   - lastAccepted: Angle used for the previous frame.
    ///   - isVertical: True when the output is 9:16.
    /// - Returns: The angle to draw with.
    static func lockedAngle(_ degrees: Int, lastAccepted: Int, isVertical: Bool) -> Int {
        let normalized = ((degrees % 360) + 360) % 360
        let fitsShape = isVertical ? (normalized == 90 || normalized == 270) : (normalized == 0 || normalized == 180)
        if fitsShape { return normalized }
        let lastFits = isVertical ? (lastAccepted == 90 || lastAccepted == 270) : (lastAccepted == 0 || lastAccepted == 180)
        if lastFits { return lastAccepted }
        return isVertical ? 90 : 0
    }

    /// Image orientation that applies a clockwise turn of `degrees`.
    /// - Parameter degrees: 0, 90, 180 or 270.
    /// - Returns: Matching `CGImagePropertyOrientation`.
    static func orientation(forClockwiseDegrees degrees: Int) -> CGImagePropertyOrientation {
        switch ((degrees % 360) + 360) % 360 {
        case 90: return .right
        case 180: return .down
        case 270: return .left
        default: return .up
        }
    }

    // MARK: - Private Helpers

    /// Stands the camera frame upright and undoes the front-lens mirror.
    private static func uprightCamera(_ image: CIImage, degrees: Int, isMirrored: Bool) -> CIImage {
        var upright = image.oriented(orientation(forClockwiseDegrees: degrees))
        if isMirrored {
            upright = upright.oriented(.upMirrored)
        }
        return upright.transformed(by: CGAffineTransform(
            translationX: -upright.extent.minX,
            y: -upright.extent.minY
        ))
    }

    /// Camera (filled) or still (fitted on black), then the frame on top.
    private static func compose(camera: CIImage, program: Program) -> CIImage {
        let bounds = CGRect(origin: .zero, size: program.outputSize)
        let black = CIImage(color: .black).cropped(to: bounds)
        let base: CIImage
        if let still = program.still {
            base = place(still, in: bounds, fill: false).composited(over: black)
        } else {
            base = place(camera, in: bounds, fill: true).composited(over: black)
        }
        guard let overlay = program.overlay else { return base.cropped(to: bounds) }
        return place(overlay, in: bounds, fill: false).composited(over: base).cropped(to: bounds)
    }

    /// Scales and centres `image` to fill or fit `bounds`.
    private static func place(_ image: CIImage, in bounds: CGRect, fill: Bool) -> CIImage {
        let extent = image.extent
        guard extent.width > 0, extent.height > 0 else { return image }
        let scaleX = bounds.width / extent.width
        let scaleY = bounds.height / extent.height
        let scale = fill ? max(scaleX, scaleY) : min(scaleX, scaleY)
        let width = extent.width * scale
        let height = extent.height * scale
        let transform = CGAffineTransform(translationX: -extent.minX, y: -extent.minY)
            .concatenating(CGAffineTransform(scaleX: scale, y: scale))
            .concatenating(CGAffineTransform(
                translationX: (bounds.width - width) / 2,
                y: (bounds.height - height) / 2
            ))
        return image.transformed(by: transform)
    }

    /// Hands out a reusable output buffer of `size` (frame queue only).
    private func makeOutputBuffer(size: CGSize) -> CVPixelBuffer? {
        if pool == nil || poolSize != size {
            let attributes: [String: Any] = [
                kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_420YpCbCr8BiPlanarFullRange),
                kCVPixelBufferWidthKey as String: Int(size.width),
                kCVPixelBufferHeightKey as String: Int(size.height),
                kCVPixelBufferIOSurfacePropertiesKey as String: [:] as [String: Any]
            ]
            var created: CVPixelBufferPool?
            CVPixelBufferPoolCreate(nil, nil, attributes as CFDictionary, &created)
            pool = created
            poolSize = size
        }
        guard let pool else { return nil }
        var buffer: CVPixelBuffer?
        CVPixelBufferPoolCreatePixelBuffer(nil, pool, &buffer)
        return buffer
    }
}
