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

    /// Posted when `lastFrame` is updated (home Camera tile freeze-frame).
    static let lastFrameDidChangeNotification = Notification.Name(
        "CameraManager.lastFrameDidChange"
    )

    /// Whether the capture session is currently running.
    private(set) var isSessionRunning = false

    /// Whether the user has granted camera permission.
    private(set) var cameraPermissionGranted = false

    /// Last still from the live preview — shown on the home Camera tile when not LIVE.
    private(set) var lastFrame: UIImage?

    /// Shared capture session used by phone and external preview layers.
    var captureSession: AVCaptureSession {
        if _captureSession == nil {
            _captureSession = AVCaptureSession()
        }
        return _captureSession ?? AVCaptureSession()
    }

    private let sessionQueue = DispatchQueue(label: "com.eclipseapp.ios.camera.session")
    private var _captureSession: AVCaptureSession?
    private var videoDevice: AVCaptureDevice?
    private let logger = Logger(subsystem: "com.eclipseapp.ios", category: "Camera")
    /// Soft cap so digital zoom stays usable (device max can be extreme).
    private let preferredMaxZoom: CGFloat = 6
    private let lastFrameURL: URL = {
        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("CameraLastFrame.jpg")
    }()

    private init() {
        if let image = UIImage(contentsOfFile: lastFrameURL.path) {
            lastFrame = image
        }
    }

    // MARK: - Last Frame

    /// Remembers a freeze-frame for the home Camera tile (memory + disk).
    func saveLastFrame(_ image: UIImage) {
        lastFrame = image
        NotificationCenter.default.post(name: Self.lastFrameDidChangeNotification, object: self)
        let url = lastFrameURL
        DispatchQueue.global(qos: .utility).async {
            guard let data = image.jpegData(compressionQuality: 0.85) else { return }
            try? data.write(to: url, options: .atomic)
        }
    }

    /// Snapshots `preview` (if possible) and stores it as the last frame.
    @discardableResult
    func captureLastFrame(from preview: CameraPreviewView?) -> Bool {
        guard let preview, let image = preview.snapshotImage() else { return false }
        saveLastFrame(image)
        return true
    }

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
                        self?.videoDevice = videoDevice
                    }
                } catch {
                    self?.logger.error(
                        "Could not create video device input: \(error.localizedDescription)"
                    )
                }
            } else if self?.videoDevice == nil {
                self?.videoDevice = (session.inputs.first as? AVCaptureDeviceInput)?.device
            }

            session.commitConfiguration()
            if let completion {
                DispatchQueue.main.async(execute: completion)
            }
        }
    }

    // MARK: - Zoom

    /// Current video zoom factor (1 = no zoom).
    var zoomFactor: CGFloat {
        videoDevice?.videoZoomFactor ?? 1
    }

    /// Minimum zoom supported by the active camera.
    var minZoomFactor: CGFloat {
        videoDevice?.minAvailableVideoZoomFactor ?? 1
    }

    /// Maximum zoom used by pinch (capped for quality).
    var maxZoomFactor: CGFloat {
        guard let device = videoDevice else { return 1 }
        return min(device.maxAvailableVideoZoomFactor, preferredMaxZoom)
    }

    /// Sets device zoom; affects phone preview and AirPlay together.
    func setZoomFactor(_ factor: CGFloat) {
        sessionQueue.async { [weak self] in
            guard let self, let device = self.videoDevice else { return }
            let clamped = min(max(factor, self.minZoomFactor), self.maxZoomFactor)
            guard abs(device.videoZoomFactor - clamped) > 0.001 else { return }
            do {
                try device.lockForConfiguration()
                device.videoZoomFactor = clamped
                device.unlockForConfiguration()
            } catch {
                self.logger.error(
                    "Zoom failed: \(error.localizedDescription)"
                )
            }
        }
    }

    /// Resets zoom to 1×.
    func resetZoom() {
        setZoomFactor(minZoomFactor)
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
    ///
    /// Completion runs after `startRunning` returns on the session queue so preview
    /// layers attach to a live session (avoids a blank first frame / missing connection).
    func prepareAndStart(completion: @escaping () -> Void) {
        configureSession { [weak self] in
            guard let self else {
                DispatchQueue.main.async(execute: completion)
                return
            }
            let session = self.captureSession
            self.sessionQueue.async {
                if !session.isRunning {
                    session.startRunning()
                }
                let isRunning = session.isRunning
                DispatchQueue.main.async {
                    self.isSessionRunning = isRunning
                    completion()
                }
            }
        }
    }

    /// Stops the capture session if currently running.
    func stopSession() {
        let session = captureSession

        sessionQueue.async { [weak self, session] in
            guard session.isRunning else { return }
            session.stopRunning()
            // Reset zoom so the next session starts at 1×.
            if let device = self?.videoDevice {
                do {
                    try device.lockForConfiguration()
                    device.videoZoomFactor = device.minAvailableVideoZoomFactor
                    device.unlockForConfiguration()
                } catch {
                    // Best-effort reset.
                }
            }
            DispatchQueue.main.async {
                self?.isSessionRunning = false
            }
        }
    }
}
