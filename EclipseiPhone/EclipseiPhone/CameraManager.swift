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
final class CameraManager: NSObject {

    static let shared = CameraManager()

    /// Posted when `lastFrame` is updated (home Camera tile freeze-frame).
    static let lastFrameDidChangeNotification = Notification.Name(
        "CameraManager.lastFrameDidChange"
    )

    /// Posted on the main queue when `isSessionRunning` changes.
    static let sessionRunningDidChangeNotification = Notification.Name(
        "CameraManager.sessionRunningDidChange"
    )

    /// Whether the capture session is currently running.
    private(set) var isSessionRunning = false

    /// Whether the user has granted camera permission.
    private(set) var cameraPermissionGranted = false

    /// Last still from the live preview — shown on the home Camera tile when not LIVE.
    private(set) var lastFrame: UIImage?

    /// True while a caller wants the session running (home tile / fullscreen / AirPlay).
    private(set) var wantsSessionRunning = false

    /// Shared capture session used by phone and external preview layers.
    var captureSession: AVCaptureSession {
        if _captureSession == nil {
            _captureSession = AVCaptureSession()
        }
        return _captureSession ?? AVCaptureSession()
    }

    let sessionQueue = DispatchQueue(label: "com.eclipseapp.ios.camera.session")
    private var _captureSession: AVCaptureSession?
    var videoDevice: AVCaptureDevice?
    let logger = Logger(subsystem: "com.eclipseapp.ios", category: "Camera")
    /// Soft cap so digital zoom stays usable (device max can be extreme).
    let preferredMaxZoom: CGFloat = 6
    private let lastFrameURL: URL = {
        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("CameraLastFrame.jpg")
    }()

    /// Latest still from `AVCaptureVideoDataOutput` (home-tile freeze source).
    ///
    /// Downscaled to `tileStillMaxEdge`. Photo capture asks for its own
    /// full-resolution sample via `requestStill(timeout:completion:)`.
    var latestSampleImage: UIImage?
    /// Throttle sample→UIImage conversion while the session runs.
    var lastSampleAt: CFAbsoluteTime = 0
    /// Kept coarse on purpose: the tile shows the live preview layer while the session
    /// runs and only needs a bitmap when parking, so converting frames rapidly burned
    /// CPU for a still almost nothing read.
    let sampleInterval: CFAbsoluteTime = 1.5
    /// Longest-edge ceiling for the throttled tile still.
    static let tileStillMaxEdge: CGFloat = 1280
    /// One-shot full-resolution still requests awaiting the next sample.
    /// Access on `frameQueue`.
    var stillRequests: [(UIImage?) -> Void] = []
    private let videoDataOutput = AVCaptureVideoDataOutput()
    let frameQueue = DispatchQueue(label: "com.eclipseapp.ios.camera.frames")
    let ciContext = CIContext(options: [.useSoftwareRenderer: false])

    /// Movie file output for hold-to-record (attached lazily).
    let movieFileOutput = AVCaptureMovieFileOutput()
    /// Optional mic input added when recording with audio permission.
    var audioDeviceInput: AVCaptureDeviceInput?
    /// Whether a movie file is currently being written.
    private(set) var isRecording = false
    /// Completion invoked when `stopRecording` finishes writing/saving.
    var stopRecordingCompletion: ((Result<Void, Error>) -> Void)?

    /// One-shot waiter used when start is deferred until the app is active.
    var activeStartObserver: NSObjectProtocol?
    /// True after interruption / runtime-error observers are installed.
    var didInstallSessionRecovery = false

    /// Posted on the main queue when `isRecording` changes.
    static let recordingDidChangeNotification = Notification.Name(
        "CameraManager.recordingDidChange"
    )

    /// Updates `isRecording` and notifies observers (main queue).
    func publishRecording(_ recording: Bool) {
        if !Thread.isMainThread {
            DispatchQueue.main.async { [weak self] in
                self?.publishRecording(recording)
            }
            return
        }
        guard isRecording != recording else { return }
        isRecording = recording
        NotificationCenter.default.post(
            name: Self.recordingDidChangeNotification, object: self
        )
    }

    private override init() {
        super.init()
        if let image = UIImage(contentsOfFile: lastFrameURL.path),
           !Self.isNearlyBlack(image) {
            lastFrame = image
        } else {
            try? FileManager.default.removeItem(at: lastFrameURL)
        }
        installSessionRecoveryIfNeeded()
    }

    // MARK: - Last Frame

    /// Remembers a freeze-frame for the home Camera tile (memory + disk).
    func saveLastFrame(_ image: UIImage) {
        guard !Self.isNearlyBlack(image) else { return }
        lastFrame = image
        NotificationCenter.default.post(name: Self.lastFrameDidChangeNotification, object: self)
        let url = lastFrameURL
        DispatchQueue.global(qos: .utility).async {
            guard let data = image.jpegData(compressionQuality: 0.85) else { return }
            try? data.write(to: url, options: .atomic)
        }
    }

    /// Stores the latest camera sample (preferred) or a non-black preview snapshot.
    ///
    /// Since tile stills are sampled coarsely, this also asks for a fresh frame and
    /// upgrades `lastFrame` if one arrives before the session stops.
    @discardableResult
    func captureLastFrame(from preview: CameraPreviewView?) -> Bool {
        requestStill { [weak self] still in
            guard let self, let still, !Self.isNearlyBlack(still) else { return }
            self.saveLastFrame(still)
        }
        if let image = latestSampleImage, !Self.isNearlyBlack(image) {
            saveLastFrame(image)
            return true
        }
        guard let preview,
              let image = preview.snapshotImage(),
              !Self.isNearlyBlack(image)
        else {
            return false
        }
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

            self?.attachVideoDataOutput(to: session)

            session.commitConfiguration()
            if let completion {
                DispatchQueue.main.async(execute: completion)
            }
        }
    }

    /// Adds a frame tap so home-tile freezes use real camera samples.
    private func attachVideoDataOutput(to session: AVCaptureSession) {
        guard !session.outputs.contains(videoDataOutput) else { return }
        videoDataOutput.alwaysDiscardsLateVideoFrames = true
        videoDataOutput.videoSettings = [
            kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32BGRA)
        ]
        videoDataOutput.setSampleBufferDelegate(self, queue: frameQueue)
        guard session.canAddOutput(videoDataOutput) else {
            logger.error("Could not add camera video data output")
            return
        }
        session.addOutput(videoDataOutput)
    }

    // MARK: - Session Lifecycle

    /// Publishes `isSessionRunning` on the main queue.
    /// - Parameter running: Whether the capture session is running.
    func publishSessionRunning(_ running: Bool) {
        if !Thread.isMainThread {
            DispatchQueue.main.async { [weak self] in
                self?.publishSessionRunning(running)
            }
            return
        }
        guard isSessionRunning != running else { return }
        isSessionRunning = running
        NotificationCenter.default.post(
            name: Self.sessionRunningDidChangeNotification,
            object: self
        )
    }

    /// Starts the capture session if not already running.
    func startSession() {
        wantsSessionRunning = true
        startCaptureIfPossible(attempt: 0, completion: {})
    }

    /// Configures (if needed), starts capture, then runs `completion` on the main queue.
    ///
    /// Defers `startRunning` until the app is active and retries briefly when the
    /// capture server is not ready yet (common on cold launch).
    func prepareAndStart(completion: @escaping () -> Void) {
        wantsSessionRunning = true
        installSessionRecoveryIfNeeded()
        configureSession { [weak self] in
            guard let self else {
                DispatchQueue.main.async(execute: completion)
                return
            }
            self.startCaptureIfPossible(attempt: 0, completion: completion)
        }
    }

    /// Stops the capture session if currently running.
    func stopSession() {
        wantsSessionRunning = false
        clearActiveStartWait()
        let session = captureSession

        sessionQueue.async { [weak self, session] in
            guard session.isRunning else {
                self?.publishSessionRunning(false)
                return
            }
            session.stopRunning()
            if let device = self?.videoDevice {
                do {
                    try device.lockForConfiguration()
                    device.videoZoomFactor = device.minAvailableVideoZoomFactor
                    device.unlockForConfiguration()
                } catch {
                    // Best-effort reset.
                }
            }
            self?.publishSessionRunning(false)
        }
    }
}
