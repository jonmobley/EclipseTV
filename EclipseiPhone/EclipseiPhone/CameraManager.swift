//
//  CameraManager.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

@preconcurrency import AVFoundation
import UIKit
import os.log

/// Manages a shared camera `AVCaptureSession` for phone preview and AirPlay.
///
/// Session work runs on a dedicated queue. Multiple `CameraPreviewView`s can attach
/// to the same session. Starts on the back camera; Flip switches front/back.
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

    /// Posted on the main queue when Flip switches front ↔ back.
    ///
    /// Preview-layer connections are rebuilt on input swap — listeners must re-apply
    /// rotation / mirroring so AirPlay does not stay on the previous lens’s angle.
    static let cameraPositionDidChangeNotification = Notification.Name(
        "CameraManager.cameraPositionDidChange"
    )

    /// Posted on the main queue when the lens horizon capture angle changes (phone turned).
    ///
    /// Frame-tap mirrors rotate their view by hand, so they need this even when the UI
    /// they sit in is orientation-locked and never lays out for the turn.
    static let captureRotationAngleDidChangeNotification = Notification.Name(
        "CameraManager.captureRotationAngleDidChange"
    )

    /// Whether the capture session is currently running.
    private(set) var isSessionRunning = false

    /// Whether the user has granted camera permission.
    private(set) var cameraPermissionGranted = false

    /// Active lens — back by default; Flip toggles front.
    private(set) var cameraPosition: AVCaptureDevice.Position = .back

    /// Updates `cameraPosition` on the main queue (Flip / configure).
    func publishCameraPosition(_ position: AVCaptureDevice.Position) {
        if !Thread.isMainThread {
            DispatchQueue.main.async { [weak self] in
                self?.publishCameraPosition(position)
            }
            return
        }
        guard position == .front || position == .back else { return }
        let changed = cameraPosition != position
        cameraPosition = position
        guard changed else { return }
        NotificationCenter.default.post(
            name: Self.cameraPositionDidChangeNotification,
            object: self
        )
    }

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
    /// Per-lens horizon angles for stills / movies (front sensors are often portrait-native).
    var captureRotationCoordinator: AVCaptureDevice.RotationCoordinator?
    /// KVO on the coordinator's capture angle, feeding `captureRotationAngleDidChangeNotification`.
    var captureRotationObservation: NSKeyValueObservation?
    let logger = Logger(subsystem: "com.eclipseapp.ios", category: "Camera")
    /// Soft cap so digital zoom stays usable (device max can be extreme).
    let preferredMaxZoom: CGFloat = 6
    private let lastFrameURL: URL = {
        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("CameraLastFrame.jpg")
    }()

    /// Latest still from `AVCaptureVideoDataOutput` (home-tile freeze source).
    ///
    /// Always downscaled to `tileStillMaxEdge`, so it is never a valid source for a
    /// saved photo. Photo capture renders its own full-resolution sample instead.
    var latestSampleImage: UIImage?
    /// Throttle sample→UIImage conversion while the session runs.
    var lastSampleAt: CFAbsoluteTime = 0
    /// Kept coarse on purpose: the tile shows the live preview layer while the session
    /// runs and only needs a bitmap when parking, so converting frames rapidly burned
    /// CPU for a still almost nothing read.
    let sampleInterval: CFAbsoluteTime = 1.5
    /// Longest-edge ceiling for the throttled tile still.
    static let tileStillMaxEdge: CGFloat = 1280
    /// One-shot still requests awaiting the next sample, each with the longest-edge
    /// ceiling it asked for (nil meaning sensor resolution). Access on `frameQueue`.
    var stillRequests: [(maxPixelEdge: CGFloat?, deliver: (UIImage?) -> Void)] = []
    private let videoDataOutput = AVCaptureVideoDataOutput()
    let frameQueue = DispatchQueue(label: "com.eclipseapp.ios.camera.frames")
    /// Views rendering the live feed from the frame tap. Mutated and read on `frameQueue`.
    ///
    /// The session drives one `AVCaptureVideoPreviewLayer` at a time, so a second live
    /// view (the phone panel while AirPlay holds the preview) is served from here.
    var frameMirrors: [WeakFrameMirror] = []
    let ciContext = CIContext(options: [.useSoftwareRenderer: false])

    /// Movie file output for tap-to-record (attached lazily).
    let movieFileOutput = AVCaptureMovieFileOutput()
    /// Optional mic input added when recording with audio permission.
    var audioDeviceInput: AVCaptureDeviceInput?
    /// Whether a movie file is currently being written.
    private(set) var isRecording = false
    /// Completion invoked when `stopRecording` finishes writing/saving.
    /// Success includes a local preview file URL when one was kept for in-app review.
    var stopRecordingCompletion: ((Result<URL?, Error>) -> Void)?
    /// When true, `fileOutput` stops the capture session after the movie file is closed
    /// (background / lock — never tear the session down mid-write).
    var stopSessionWhenRecordingFinishes = false
    /// True after `stopRecording()` until `fileOutput` runs — blocks a second stop.
    var isStoppingRecording = false
    /// Latest in-app review movie URL after a background/system stop (consumed by UI).
    private(set) var lastInAppVideoPreviewURL: URL?

    /// Stores a Caches preview URL for the camera UI to pick up after a system stop.
    func rememberInAppVideoPreview(_ url: URL?) {
        if !Thread.isMainThread {
            DispatchQueue.main.async { [weak self] in
                self?.rememberInAppVideoPreview(url)
            }
            return
        }
        lastInAppVideoPreviewURL = url
    }

    /// Takes and clears `lastInAppVideoPreviewURL` (main queue).
    func consumeInAppVideoPreviewURL() -> URL? {
        let url = lastInAppVideoPreviewURL
        lastInAppVideoPreviewURL = nil
        return url
    }

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
    /// upgrades `lastFrame` if one arrives before the session stops. Tile-sized on
    /// purpose: `saveLastFrame` re-encodes whatever it is handed to disk, and a tile
    /// has no use for sensor resolution.
    @discardableResult
    func captureLastFrame(from preview: CameraPreviewView?) -> Bool {
        requestStill(maxPixelEdge: Self.tileStillMaxEdge) { [weak self] still in
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
                guard let videoDevice = Self.device(at: .back) else {
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
            let position = self?.videoDevice?.position ?? .back
            if position == .front || position == .back {
                self?.applyVideoMirroringLocked(for: position)
            }
            self?.refreshCaptureRotationCoordinator()

            session.commitConfiguration()
            if position == .front || position == .back {
                self?.publishCameraPosition(position)
            }
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
    ///
    /// An in-flight movie is closed out first and the session stops once its file is
    /// written. `stopRunning` mid-write truncates the recording, and callers arrive here
    /// from paths that never ask whether one is running — the external display tearing
    /// down camera mode, the close destination, a blackout.
    func stopSession() {
        wantsSessionRunning = false
        clearActiveStartWait()

        sessionQueue.async { [weak self] in
            guard let self else { return }
            if self.deferSessionStopUntilRecordingFinishesLocked() { return }
            guard self.captureSession.isRunning else {
                self.publishSessionRunning(false)
                return
            }
            self.captureSession.stopRunning()
            self.resetZoomToMinimumLocked()
            self.publishSessionRunning(false)
        }
    }
}
