//
//  CameraManager+Flip.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

@preconcurrency import AVFoundation
import UIKit

// MARK: - Front / Back Camera

extension CameraManager {

    /// True when both front and back wide cameras exist (Flip is usable).
    var canFlipCamera: Bool {
        Self.device(at: .back) != nil && Self.device(at: .front) != nil
    }

    /// Switches between the back and front wide-angle cameras.
    ///
    /// No-op while recording (can't rebuild inputs mid-movie). Completion runs on
    /// the main queue.
    func flipCamera(completion: (() -> Void)? = nil) {
        let next: AVCaptureDevice.Position = cameraPosition == .front ? .back : .front
        switchToCamera(position: next, completion: completion)
    }

    /// Activates the wide-angle camera at `position`.
    func switchToCamera(
        position: AVCaptureDevice.Position,
        completion: (() -> Void)? = nil
    ) {
        let finish: () -> Void = {
            DispatchQueue.main.async { completion?() }
        }
        // UI gate — session queue re-checks `movieFileOutput` for a start race.
        guard !isRecording else {
            finish()
            return
        }
        guard let device = Self.device(at: position) else {
            logger.error("No wide-angle camera at \(String(describing: position))")
            finish()
            return
        }

        sessionQueue.async { [weak self] in
            guard let self else {
                finish()
                return
            }
            // Flipping mid-movie would tear out the writer’s video input.
            guard !self.movieFileOutput.isRecording else {
                self.logger.notice("Ignoring flip — recording in progress")
                finish()
                return
            }
            self.replaceVideoInputLocked(with: device, position: position)
            finish()
        }
    }

    /// Swaps the session's video input, putting the old lens back if the swap fails.
    private func replaceVideoInputLocked(
        with device: AVCaptureDevice,
        position: AVCaptureDevice.Position
    ) {
        let session = captureSession
        session.beginConfiguration()
        defer { session.commitConfiguration() }

        var removed: [AVCaptureDeviceInput] = []
        for input in session.inputs {
            guard let deviceInput = input as? AVCaptureDeviceInput,
                  deviceInput.device.hasMediaType(.video) else { continue }
            session.removeInput(deviceInput)
            removed.append(deviceInput)
        }

        do {
            let input = try AVCaptureDeviceInput(device: device)
            guard session.canAddInput(input) else {
                logger.error("Cannot add \(String(describing: position)) camera")
                restoreVideoInputsLocked(removed)
                return
            }
            session.addInput(input)
            videoDevice = device
            applyVideoMirroringLocked(for: position)
            refreshCaptureRotationCoordinator()
            publishCameraPosition(position)
            resetZoom()
        } catch {
            logger.error("Flip camera failed: \(error.localizedDescription)")
            restoreVideoInputsLocked(removed)
        }
    }

    /// Re-adds the lens a failed swap removed.
    ///
    /// Without this the session runs with no video input at all: preview goes black and
    /// stills / recording stay broken, because `configureSession` skips re-adding video
    /// whenever `session.inputs` is non-empty (a mic input alone satisfies that).
    private func restoreVideoInputsLocked(_ inputs: [AVCaptureDeviceInput]) {
        for input in inputs where captureSession.canAddInput(input) {
            captureSession.addInput(input)
            videoDevice = input.device
            applyVideoMirroringLocked(for: input.device.position)
            refreshCaptureRotationCoordinator()
            publishCameraPosition(input.device.position)
            return
        }
    }

    /// Mirrors front-camera video on data / movie connections so stills, the phone
    /// viewfinder tap, and recordings match the mirrored phone preview.
    /// AirPlay’s preview layer is unmirrored separately so program text reads correctly.
    func applyVideoMirroringLocked(for position: AVCaptureDevice.Position) {
        let mirror = position == .front
        for output in captureSession.outputs {
            guard let connection = output.connection(with: .video),
                  connection.isVideoMirroringSupported else { continue }
            connection.automaticallyAdjustsVideoMirroring = false
            connection.isVideoMirrored = mirror
        }
    }

    /// Wide-angle camera at `position`, if present.
    static func device(at position: AVCaptureDevice.Position) -> AVCaptureDevice? {
        AVCaptureDevice.default(
            .builtInWideAngleCamera,
            for: .video,
            position: position
        )
    }
}
