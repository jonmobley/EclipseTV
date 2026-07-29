//
//  CameraManager+LastFrame.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

@preconcurrency import AVFoundation
import CoreImage
import UIKit

// MARK: - Live Frame Sampling

extension CameraManager: AVCaptureVideoDataOutputSampleBufferDelegate {

    /// Fulfils pending still requests, and otherwise refreshes the throttled tile still
    /// (preview-layer snapshots are unreliable and often black).
    func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        if !stillRequests.isEmpty {
            let requests = stillRequests
            stillRequests.removeAll()
            let image = imageFromSampleBuffer(sampleBuffer)
            DispatchQueue.main.async { [weak self] in
                if let image { self?.latestSampleImage = image }
                for request in requests { request(image) }
            }
            return
        }

        let now = CFAbsoluteTimeGetCurrent()
        guard now - lastSampleAt >= sampleInterval else { return }
        lastSampleAt = now
        guard let image = imageFromSampleBuffer(
            sampleBuffer,
            maxPixelEdge: CameraManager.tileStillMaxEdge
        ) else { return }
        DispatchQueue.main.async { [weak self] in
            self?.latestSampleImage = image
        }
    }

    /// Converts the next camera sample into a full-resolution upright still.
    ///
    /// On demand rather than continuous: rendering every frame cost a full-resolution
    /// Core Image pass several times a second, and a shutter press wants the frame as it
    /// was pressed rather than a stale sample.
    /// - Parameters:
    ///   - timeout: Reports nil if no sample arrives within this window.
    ///   - completion: Called exactly once, on the main queue.
    func requestStill(
        timeout: TimeInterval = 0.6,
        completion: @escaping (UIImage?) -> Void
    ) {
        // The sample callback and the timeout both land on main, so one flag suffices.
        var hasFinished = false
        let finish: (UIImage?) -> Void = { image in
            guard !hasFinished else { return }
            hasFinished = true
            completion(image)
        }

        guard isSessionRunning else {
            DispatchQueue.main.async { finish(nil) }
            return
        }
        frameQueue.async { [weak self] in
            self?.stillRequests.append(finish)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + timeout) { finish(nil) }
    }

    /// Converts a video sample into an upright still matching Display Mode.
    /// - Parameter maxPixelEdge: Longest-edge ceiling, or nil for sensor resolution.
    func imageFromSampleBuffer(
        _ sampleBuffer: CMSampleBuffer,
        maxPixelEdge: CGFloat? = nil
    ) -> UIImage? {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
            return nil
        }
        var ciImage = CIImage(cvPixelBuffer: pixelBuffer)
        // Sensor buffers are landscape; Vertical mode matches the 90° preview.
        if ExternalOutputSettings.isVerticalMode {
            ciImage = ciImage.oriented(.right)
        }
        if let maxPixelEdge {
            let longest = max(ciImage.extent.width, ciImage.extent.height)
            if longest > maxPixelEdge {
                let scale = maxPixelEdge / longest
                ciImage = ciImage.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
            }
        }
        guard let cgImage = ciContext.createCGImage(ciImage, from: ciImage.extent) else {
            return nil
        }
        return UIImage(cgImage: cgImage)
    }

    /// Reused across `isNearlyBlack` calls — building a `CIContext` per call is one of
    /// the more expensive things in Core Image, and this runs on every freeze frame.
    private static let luminanceContext = CIContext(options: [.workingColorSpace: NSNull()])

    /// True when the image is effectively empty/black (failed preview snapshot).
    static func isNearlyBlack(_ image: UIImage) -> Bool {
        guard let ciImage = CIImage(image: image) else { return true }
        let extent = ciImage.extent
        guard extent.width > 1, extent.height > 1 else { return true }
        guard let filter = CIFilter(
            name: "CIAreaAverage",
            parameters: [
                kCIInputImageKey: ciImage,
                kCIInputExtentKey: CIVector(cgRect: extent)
            ]
        ),
        let output = filter.outputImage
        else {
            return true
        }

        var pixel = [UInt8](repeating: 0, count: 4)
        luminanceContext.render(
            output,
            toBitmap: &pixel,
            rowBytes: 4,
            bounds: CGRect(x: 0, y: 0, width: 1, height: 1),
            format: .RGBA8,
            colorSpace: nil
        )
        let luminance =
            0.299 * Double(pixel[0])
            + 0.587 * Double(pixel[1])
            + 0.114 * Double(pixel[2])
        return luminance < 14
    }
}
