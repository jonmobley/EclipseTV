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
        configureSession(completion: nil)
    }

    /// Configures on the session queue, then invokes `completion` on the main queue.
    func configureSession(completion: (() -> Void)?) {
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
                    if let completion {
                        DispatchQueue.main.async(execute: completion)
                    }
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
            if let completion {
                DispatchQueue.main.async(execute: completion)
            }
        }
    }

    // MARK: - Session Lifecycle

    /// Starts the capture session if not already running.
    func startSession() {
        let session = captureSession

        sessionQueue.async { [weak self, session] in
            guard !session.isRunning else {
                DispatchQueue.main.async { self?.isSessionRunning = true }
                return
            }
            session.startRunning()
            let isRunning = session.isRunning
            DispatchQueue.main.async {
                self?.isSessionRunning = isRunning
            }
        }
    }

    /// Configures (if needed), starts capture, then runs `completion` on the main queue.
    func prepareAndStart(completion: @escaping () -> Void) {
        configureSession { [weak self] in
            self?.startSession()
            // Allow the session a tick to publish frames before attaching UI.
            DispatchQueue.main.async(execute: completion)
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
