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

    /// Keeps a recent upright still for the home Camera tile (preview-layer
    /// snapshots are unreliable and often black).
    func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        let now = CFAbsoluteTimeGetCurrent()
        guard now - lastSampleAt >= sampleInterval else { return }
        lastSampleAt = now
        guard let image = imageFromSampleBuffer(sampleBuffer) else { return }
        DispatchQueue.main.async { [weak self] in
            self?.latestSampleImage = image
        }
    }

    /// Converts a video sample into an upright still matching Display Mode.
    func imageFromSampleBuffer(_ sampleBuffer: CMSampleBuffer) -> UIImage? {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
            return nil
        }
        var ciImage = CIImage(cvPixelBuffer: pixelBuffer)
        // Sensor buffers are landscape; Vertical mode matches the 90° preview.
        if ExternalOutputSettings.isVerticalMode {
            ciImage = ciImage.oriented(.right)
        }
        guard let cgImage = ciContext.createCGImage(ciImage, from: ciImage.extent) else {
            return nil
        }
        return UIImage(cgImage: cgImage)
    }

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
        let context = CIContext(options: [.workingColorSpace: NSNull()])
        context.render(
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
