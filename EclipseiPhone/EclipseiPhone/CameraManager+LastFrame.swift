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

    /// Feeds any live mirrors, fulfils pending still requests, and otherwise refreshes
    /// the throttled tile still (preview-layer snapshots are unreliable and often black).
    func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        // Ahead of the still-request return below: a mirror needs every frame.
        broadcastToFrameMirrors(sampleBuffer)

        if !stillRequests.isEmpty {
            let requests = stillRequests
            stillRequests.removeAll()
            // Rendered per request rather than once: the sizes differ, and deliberately
            // not stored in `latestSampleImage`, which must stay tile-sized.
            let images = requests.map {
                imageFromSampleBuffer(sampleBuffer, maxPixelEdge: $0.maxPixelEdge)
            }
            DispatchQueue.main.async {
                for (request, image) in zip(requests, images) { request.deliver(image) }
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

    /// Converts the next camera sample into an upright still.
    ///
    /// On demand rather than continuous: rendering every frame cost a full-resolution
    /// Core Image pass several times a second, and a shutter press wants the frame as it
    /// was pressed rather than a stale sample.
    /// - Parameters:
    ///   - maxPixelEdge: Longest-edge ceiling, or nil for sensor resolution.
    ///   - timeout: Reports nil if no sample arrives within this window.
    ///   - completion: Called exactly once, on the main queue.
    func requestStill(
        maxPixelEdge: CGFloat? = nil,
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
            self?.stillRequests.append((maxPixelEdge: maxPixelEdge, deliver: finish))
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + timeout) { finish(nil) }
    }

    /// Converts a video sample into an upright still matching the live preview.
    /// - Parameter maxPixelEdge: Longest-edge ceiling, or nil for sensor resolution.
    func imageFromSampleBuffer(
        _ sampleBuffer: CMSampleBuffer,
        maxPixelEdge: CGFloat? = nil
    ) -> UIImage? {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
            return nil
        }
        var ciImage = CIImage(cvPixelBuffer: pixelBuffer)
        // Prefer the lens coordinator — Vertical≠always-90°. Newer front sensors are
        // portrait-mounted and report 0°; forcing 90° left a landscape home-tile freeze.
        ciImage = applyHorizonCaptureOrientation(to: ciImage)
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

    /// Rebuilds the capture-angle coordinator when the active lens changes.
    func refreshCaptureRotationCoordinator() {
        guard let device = videoDevice else {
            captureRotationCoordinator = nil
            return
        }
        if captureRotationCoordinator?.device === device { return }
        captureRotationCoordinator = AVCaptureDevice.RotationCoordinator(
            device: device,
            previewLayer: nil
        )
    }

    /// Horizon-level angle for stills and movie output (matches live preview uprightness).
    func horizonLevelCaptureRotationAngle() -> CGFloat {
        refreshCaptureRotationCoordinator()
        return captureRotationCoordinator?.videoRotationAngleForHorizonLevelCapture
            ?? CameraPreviewView.displayModePreviewRotationAngle
    }

    /// Applies the active lens’s horizon capture angle to a sensor-space still.
    func applyHorizonCaptureOrientation(to ciImage: CIImage) -> CIImage {
        switch quantizedRotationAngle(horizonLevelCaptureRotationAngle()) {
        case 90:
            return ciImage.oriented(.right)
        case 180:
            return ciImage.oriented(.down)
        case 270:
            return ciImage.oriented(.left)
        default:
            return ciImage
        }
    }

    /// Snaps a coordinator angle to 0 / 90 / 180 / 270.
    func quantizedRotationAngle(_ angle: CGFloat) -> Int {
        let stepped = Int((angle / 90).rounded()) * 90
        let normalized = ((stepped % 360) + 360) % 360
        return normalized
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
