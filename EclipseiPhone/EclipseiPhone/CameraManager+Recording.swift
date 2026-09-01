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

    /// Saves a full-resolution still of the current frame to Photos.
    ///
    /// Deliberately has no fallback to `latestSampleImage` or `lastFrame`. Both are
    /// downscaled to `tileStillMaxEdge`, and `lastFrame` outlives the session that
    /// produced it, so falling back would quietly write a stale thumbnail to the user's
    /// library instead of the frame they pressed the shutter on. Reporting `noFrame`
    /// ("No camera frame is ready yet.") is the honest answer.
    ///
    /// On success the completion also receives the still for in-app review (so the
    /// camera UI never has to bounce the user out to Photos).
    func capturePhotoToLibrary(
        completion: @escaping (Result<UIImage, Error>) -> Void
    ) {
        requestStill { [weak self] still in
            // Frame store is main-actor; hop explicitly (callback is main-queue in
            // practice, but not typed as @MainActor for the concurrency checker).
            Task { @MainActor in
                guard let self else { return }
                guard let still else {
                    completion(.failure(CaptureError.noFrame))
                    return
                }
                let output = CameraFrameCompositor.stillWithFrameIfNeeded(still)
                self.saveImageToPhotos(output) { result in
                    switch result {
                    case .success:
                        completion(.success(output))
                    case .failure(let error):
                        completion(.failure(error))
                    }
                }
            }
        }
    }

    // MARK: - Video

    /// Starts recording to a temp file (mic audio when authorized).
    func startRecording(completion: @escaping (Result<Void, Error>) -> Void) {
        Task { @MainActor in
            await self.ensureMicrophoneIfPossible()
            // Same horizon capture angle as stills / live preview (front may be 0°).
            let rotationAngle = self.horizonLevelCaptureRotationAngle()
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
    ///
    /// Success may include a Caches copy of the movie for in-app review.
    func stopRecording(completion: ((Result<URL?, Error>) -> Void)? = nil) {
        sessionQueue.async { [weak self] in
            guard let self else { return }
            guard self.movieFileOutput.isRecording else {
            // The output can already be closed after an external teardown that
            // never ran the delegate. Re-publish so the record button, the flip
            // button, and the timer don't stay stuck in the recording state.
                self.isStoppingRecording = false
                DispatchQueue.main.async {
                    self.publishRecording(false)
                    completion?(.success(nil))
                }
                return
            }
            // Lock then background can both ask to stop — keep the newest completion.
            if let completion {
                self.stopRecordingCompletion = completion
            }
            guard !self.isStoppingRecording else { return }
            self.isStoppingRecording = true
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
        // File is closed — safe to tear down the session if background asked us to wait.
        sessionQueue.async { [weak self] in
            guard let self else { return }
            self.isStoppingRecording = false
            guard self.stopSessionWhenRecordingFinishes else { return }
            self.stopSessionWhenRecordingFinishes = false
            self.stopCaptureSessionLocked()
        }

        if let error {
            DispatchQueue.main.async { [weak self] in
                self?.publishRecording(false)
                let completion = self?.stopRecordingCompletion
                self?.stopRecordingCompletion = nil
                completion?(.failure(error))
            }
            try? FileManager.default.removeItem(at: outputFileURL)
            return
        }

        Task { [weak self] in
            await self?.finishRecording(rawFileURL: outputFileURL)
        }
    }

    /// Optionally burns the selected frame in, then saves Photos + Caches preview.
    private func finishRecording(rawFileURL: URL) async {
        // File is closed — clear the recording chrome before a possibly slow burn-in.
        await MainActor.run { self.publishRecording(false) }

        let framedURL = await CameraFrameCompositor.framedVideoURLIfNeeded(
            from: rawFileURL
        )
        let urlToSave = framedURL ?? rawFileURL
        // Keep a Caches copy for the in-app viewer before Photos ingest deletes the temp.
        let previewURL = Self.persistCapturePreview(from: urlToSave)
        // So lock/background stops (no UI completion) still feed the last-capture button.
        rememberInAppVideoPreview(previewURL)

        let saveResult = await saveVideoToPhotosAsync(urlToSave)
        await MainActor.run {
            let completion = self.stopRecordingCompletion
            self.stopRecordingCompletion = nil
            switch saveResult {
            case .success:
                completion?(.success(previewURL))
            case .failure(let error):
                if let previewURL {
                    // Drop the remembered URL with the file — otherwise Last Capture
                    // enables and opens a movie that is no longer on disk.
                    self.rememberInAppVideoPreview(nil)
                    try? FileManager.default.removeItem(at: previewURL)
                }
                completion?(.failure(error))
            }
        }
        try? FileManager.default.removeItem(at: rawFileURL)
        if let framedURL {
            try? FileManager.default.removeItem(at: framedURL)
        }
    }

    /// Async wrapper so Photos' Sendable completion never captures `CameraManager`.
    private func saveVideoToPhotosAsync(_ fileURL: URL) async -> Result<Void, Error> {
        await withCheckedContinuation { continuation in
            saveVideoToPhotos(fileURL) { result in
                continuation.resume(returning: result)
            }
        }
    }

    /// Copies `source` into Caches for in-app playback; nil if the copy fails.
    private static func persistCapturePreview(from source: URL) -> URL? {
        let dir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("CameraCaptures", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let dest = dir.appendingPathComponent("\(UUID().uuidString).mov")
        do {
            if FileManager.default.fileExists(atPath: dest.path) {
                try FileManager.default.removeItem(at: dest)
            }
            try FileManager.default.copyItem(at: source, to: dest)
            return dest
        } catch {
            return nil
        }
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
        if let videoConnection = movieFileOutput.connection(with: .video) {
            if videoConnection.isVideoRotationAngleSupported(rotationAngle) {
                videoConnection.videoRotationAngle = rotationAngle
            }
            // Front camera: match the mirrored preview (same as the frame tap).
            // Read the active device, not `cameraPosition` — that publishes to the main
            // queue, so a recording started right after a flip would see the old lens
            // and save an unmirrored selfie.
            if videoConnection.isVideoMirroringSupported {
                videoConnection.automaticallyAdjustsVideoMirroring = false
                videoConnection.isVideoMirrored = self.videoDevice?.position == .front
            }
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
