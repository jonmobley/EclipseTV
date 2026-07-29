//
//  CameraManager+Recording.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

@preconcurrency import AVFoundation
import Photos
import UIKit

// MARK: - Photo / Video Capture

extension CameraManager: AVCaptureFileOutputRecordingDelegate {

    // MARK: - Photo

    /// Saves the latest camera sample to Photos.
    func capturePhotoToLibrary(completion: @escaping (Result<Void, Error>) -> Void) {
        guard let image = latestSampleImage ?? lastFrame else {
            completion(.failure(CaptureError.noFrame))
            return
        }
        saveImageToPhotos(image, completion: completion)
    }

    // MARK: - Video

    /// Starts recording to a temp file (mic audio when authorized).
    func startRecording(completion: @escaping (Result<Void, Error>) -> Void) {
        Task { @MainActor in
            await self.ensureMicrophoneIfPossible()
            // Read the Display Mode on the main actor; `CameraPreviewView` derives its own
            // connection angle the same way, so the movie matches what the user sees.
            let rotationAngle: CGFloat = ExternalOutputSettings.isVerticalMode ? 90 : 0
            self.beginRecording(rotationAngle: rotationAngle, completion: completion)
        }
    }

    private func beginRecording(
        rotationAngle: CGFloat,
        completion: @escaping (Result<Void, Error>) -> Void
    ) {
        sessionQueue.async { [weak self] in
            guard let self else { return }
            do {
                try self.prepareMovieOutputLocked(rotationAngle: rotationAngle)
            } catch {
                DispatchQueue.main.async { completion(.failure(error)) }
                return
            }
            guard !self.movieFileOutput.isRecording else {
                DispatchQueue.main.async { completion(.success(())) }
                return
            }
            let url = FileManager.default.temporaryDirectory
                .appendingPathComponent("EclipseCapture-\(UUID().uuidString).mov")
            self.movieFileOutput.startRecording(to: url, recordingDelegate: self)
            DispatchQueue.main.async {
                self.publishRecording(true)
                completion(.success(()))
            }
        }
    }

    /// Stops the active recording and saves it to Photos.
    func stopRecording(completion: ((Result<Void, Error>) -> Void)? = nil) {
        sessionQueue.async { [weak self] in
            guard let self else { return }
            guard self.movieFileOutput.isRecording else {
                DispatchQueue.main.async { completion?(.success(())) }
                return
            }
            self.stopRecordingCompletion = completion
            self.movieFileOutput.stopRecording()
        }
    }

    // MARK: - AVCaptureFileOutputRecordingDelegate

    func fileOutput(
        _ output: AVCaptureFileOutput,
        didFinishRecordingTo outputFileURL: URL,
        from connections: [AVCaptureConnection],
        error: Error?
    ) {
        let finish: (Result<Void, Error>) -> Void = { [weak self] result in
            DispatchQueue.main.async {
                self?.publishRecording(false)
                let completion = self?.stopRecordingCompletion
                self?.stopRecordingCompletion = nil
                completion?(result)
            }
            try? FileManager.default.removeItem(at: outputFileURL)
        }

        if let error {
            finish(.failure(error))
            return
        }

        saveVideoToPhotos(outputFileURL, completion: finish)
    }

    // MARK: - Private

    private func ensureMicrophoneIfPossible() async {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            break
        case .notDetermined:
            _ = await AVCaptureDevice.requestAccess(for: .audio)
        default:
            break
        }
    }

    private func prepareMovieOutputLocked(rotationAngle: CGFloat) throws {
        let session = captureSession
        session.beginConfiguration()
        defer { session.commitConfiguration() }

        if !session.outputs.contains(movieFileOutput) {
            guard session.canAddOutput(movieFileOutput) else {
                throw CaptureError.cannotAddMovieOutput
            }
            session.addOutput(movieFileOutput)
        }

        // The movie connection defaults to the sensor's native orientation, which lands
        // sideways in Photos whenever the preview is rotated.
        if let videoConnection = movieFileOutput.connection(with: .video),
           videoConnection.isVideoRotationAngleSupported(rotationAngle) {
            videoConnection.videoRotationAngle = rotationAngle
        }

        let micAuthorized =
            AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
        if micAuthorized, audioDeviceInput == nil,
           let mic = AVCaptureDevice.default(for: .audio) {
            do {
                let input = try AVCaptureDeviceInput(device: mic)
                if session.canAddInput(input) {
                    session.addInput(input)
                    audioDeviceInput = input
                }
            } catch {
                logger.error("Mic input failed: \(error.localizedDescription)")
            }
        }
    }

    private func saveImageToPhotos(
        _ image: UIImage,
        completion: @escaping (Result<Void, Error>) -> Void
    ) {
        requestPhotoAddAccess { granted in
            guard granted else {
                completion(.failure(CaptureError.photosDenied))
                return
            }
            PHPhotoLibrary.shared().performChanges({
                PHAssetChangeRequest.creationRequestForAsset(from: image)
            }, completionHandler: { ok, error in
                DispatchQueue.main.async {
                    if ok {
                        completion(.success(()))
                    } else {
                        completion(.failure(error ?? CaptureError.saveFailed))
                    }
                }
            })
        }
    }

    private func saveVideoToPhotos(
        _ fileURL: URL,
        completion: @escaping (Result<Void, Error>) -> Void
    ) {
        requestPhotoAddAccess { granted in
            guard granted else {
                completion(.failure(CaptureError.photosDenied))
                return
            }
            PHPhotoLibrary.shared().performChanges({
                PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: fileURL)
            }, completionHandler: { ok, error in
                if ok {
                    completion(.success(()))
                } else {
                    completion(.failure(error ?? CaptureError.saveFailed))
                }
            })
        }
    }

    private func requestPhotoAddAccess(completion: @escaping (Bool) -> Void) {
        let status = PHPhotoLibrary.authorizationStatus(for: .addOnly)
        switch status {
        case .authorized, .limited:
            completion(true)
        case .notDetermined:
            PHPhotoLibrary.requestAuthorization(for: .addOnly) { newStatus in
                completion(newStatus == .authorized || newStatus == .limited)
            }
        default:
            completion(false)
        }
    }

    /// Capture failures surfaced to the camera UI.
    enum CaptureError: LocalizedError {
        case noFrame
        case cannotAddMovieOutput
        case photosDenied
        case saveFailed

        var errorDescription: String? {
            switch self {
            case .noFrame:
                return "No camera frame is ready yet."
            case .cannotAddMovieOutput:
                return "Could not start video recording."
            case .photosDenied:
                return "Allow Photos access to save captures."
            case .saveFailed:
                return "Could not save to Photos."
            }
        }
    }
}
