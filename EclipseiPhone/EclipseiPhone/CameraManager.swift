//
//  CameraManager.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

@preconcurrency import AVFoundation
import UIKit
import os.log

/// Manages a shared back-camera `AVCaptureSession` for phone preview and AirPlay.
///
/// Session work runs on a dedicated queue. Multiple `CameraPreviewView`s can attach
/// to the same session.
final class CameraManager {

    static let shared = CameraManager()

    /// Whether the capture session is currently running.
    private(set) var isSessionRunning = false

    /// Whether the user has granted camera permission.
    private(set) var cameraPermissionGranted = false

    /// Shared capture session used by phone and external preview layers.
    var captureSession: AVCaptureSession {
        if _captureSession == nil {
            _captureSession = AVCaptureSession()
        }
        return _captureSession ?? AVCaptureSession()
    }

    private let sessionQueue = DispatchQueue(label: "com.eclipseapp.ios.camera.session")
    private var _captureSession: AVCaptureSession?
    private let logger = Logger(subsystem: "com.eclipseapp.ios", category: "Camera")

    private init() {}

    // MARK: - Permissions

    /// Checks and requests camera permission if needed. Returns whether access is granted.
    @discardableResult
    func checkPermissions() async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            cameraPermissionGranted = true
        case .notDetermined:
            cameraPermissionGranted = await AVCaptureDevice.requestAccess(for: .video)
        default:
            cameraPermissionGranted = false
        }
        return cameraPermissionGranted
    }

    // MARK: - Session Configuration

    /// Configures the session with the back wide-angle camera. Safe to call repeatedly.
    func configureSession() {
        let session = captureSession

        sessionQueue.async { [weak self, session] in
            session.beginConfiguration()
            session.sessionPreset = .high

            if session.inputs.isEmpty {
                guard let videoDevice = AVCaptureDevice.default(
                    .builtInWideAngleCamera,
                    for: .video,
                    position: .back
                ) else {
                    self?.logger.error("No back wide-angle camera available")
                    session.commitConfiguration()
                    return
                }

                do {
                    let videoInput = try AVCaptureDeviceInput(device: videoDevice)
                    if session.canAddInput(videoInput) {
                        session.addInput(videoInput)
                    }
                } catch {
                    self?.logger.error(
                        "Could not create video device input: \(error.localizedDescription)"
                    )
                }
            }

            session.commitConfiguration()
        }
    }

    // MARK: - Session Lifecycle

    /// Starts the capture session if not already running.
    func startSession() {
        let session = captureSession

        sessionQueue.async { [weak self, session] in
            guard !session.isRunning else { return }
            session.startRunning()
            let isRunning = session.isRunning
            DispatchQueue.main.async {
                self?.isSessionRunning = isRunning
            }
        }
    }

    /// Stops the capture session if currently running.
    func stopSession() {
        let session = captureSession

        sessionQueue.async { [weak self, session] in
            guard session.isRunning else { return }
            session.stopRunning()
            DispatchQueue.main.async {
                self?.isSessionRunning = false
            }
        }
    }
}
