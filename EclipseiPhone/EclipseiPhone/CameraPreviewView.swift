//
//  CameraPreviewView.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import UIKit
import AVFoundation

/// UIView whose backing layer is an `AVCaptureVideoPreviewLayer`.
///
/// Multiple instances can share the same `AVCaptureSession` (phone + AirPlay).
/// Sized with frames / `applyRotatedLayout` — do not pin with Auto Layout.
final class CameraPreviewView: UIView {

    override class var layerClass: AnyClass {
        AVCaptureVideoPreviewLayer.self
    }

    var videoPreviewLayer: AVCaptureVideoPreviewLayer {
        layer as! AVCaptureVideoPreviewLayer
    }

    /// Gravity for the Display Mode panel (phone viewfinder and AirPlay).
    ///
    /// Fill, not fit: the panel is already 16:9 / 9:16. Fit letterboxes the 4:3
    /// sensor on Landscape AirPlay while the phone crops, so program wouldn't match.
    static let programVideoGravity: AVLayerVideoGravity = .resizeAspectFill

    /// Fallback when `RotationCoordinator` has no device yet.
    ///
    /// Prefer `syncDisplayModeOrientation()` / `syncPhoneViewerOrientation(_:)` —
    /// live capture uses the coordinator so front/back and landscape Left/Right stay upright.
    var preferredVideoRotationAngle: CGFloat = 0 {
        didSet {
            guard preferredVideoRotationAngle != oldValue else { return }
            applyPreviewOrientation()
        }
    }

    private var rotationCoordinator: AVCaptureDevice.RotationCoordinator?
    private var rotationObservations: [NSKeyValueObservation] = []

    deinit {
        invalidateRotationObservations()
    }

    /// Binds this view to `session` and sets video gravity.
    ///
    /// Re-assigning a session the layer already holds restarts it, and a restarted
    /// layer shows its black background until it paints again.
    func attach(session: AVCaptureSession,
                videoGravity: AVLayerVideoGravity = .resizeAspect) {
        if videoPreviewLayer.session !== session {
            videoPreviewLayer.session = session
        }
        videoPreviewLayer.videoGravity = videoGravity
        backgroundColor = .black
        refreshRotationCoordinator()
        applyPreviewOrientation()
    }

    /// Detaches from any capture session.
    func detach() {
        invalidateRotationObservations()
        rotationCoordinator = nil
        videoPreviewLayer.session = nil
    }

    /// Syncs program rotation so subjects stay upright however the phone is held.
    ///
    /// The panel *shape* is pinned to Display Mode by `applyRotatedLayout`; only the
    /// sensor angle follows the hold. A portrait phone on a Landscape Show is an upright
    /// 16:9 crop (same framing as the phone panel) rather than a sideways full frame.
    func syncDisplayModeOrientation() {
        preferredVideoRotationAngle = Self.programFallbackRotationAngle
        refreshRotationCoordinator()
        applyPreviewOrientation()
    }

    /// Upright relative to how the phone is held — home Camera tile only.
    func syncPhoneViewerOrientation(_ orientation: UIInterfaceOrientation) {
        preferredVideoRotationAngle = orientation.cameraPreviewRotationAngle
        refreshRotationCoordinator()
        applyPreviewOrientation()
    }

    /// Fallback still of the preview hierarchy. Prefer `CameraManager`'s sample
    /// buffer — `AVCaptureVideoPreviewLayer` often renders black here.
    func snapshotImage() -> UIImage? {
        guard bounds.width > 1, bounds.height > 1 else { return nil }
        let format = UIGraphicsImageRendererFormat.default()
        format.opaque = true
        format.scale = window?.screen.scale ?? UIScreen.main.scale
        let renderer = UIGraphicsImageRenderer(bounds: bounds, format: format)
        return renderer.image { _ in
            drawHierarchy(in: bounds, afterScreenUpdates: false)
        }
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        applyPreviewOrientation()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        applyPreviewOrientation()
    }

    // MARK: - Rotation

    /// Program sensor angle when no lens coordinator is available yet.
    ///
    /// Derived from how the phone app is held. The live path prefers the coordinator's
    /// horizon-level capture angle, which also knows about portrait-mounted sensors.
    static var programFallbackRotationAngle: CGFloat {
        programRotationAngle(phoneOrientation: phoneApplicationOrientation)
    }

    /// Sensor angle that stands subjects upright for `phoneOrientation`.
    ///
    /// Display Mode does not enter into it: the panel shape is pinned separately, and
    /// fill gravity turns a cross-axis hold into an upright crop. Pinning the angle to
    /// the mode instead left program sideways whenever the hold did not match.
    static func programRotationAngle(phoneOrientation: UIInterfaceOrientation) -> CGFloat {
        phoneOrientation.cameraPreviewRotationAngle
    }

    /// Interface orientation of the phone app window (camera body), not the TV.
    static var phoneApplicationOrientation: UIInterfaceOrientation {
        let orientation = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first { $0.session.role == .windowApplication }?
            .interfaceOrientation
        guard let orientation, orientation != .unknown else {
            return ExternalOutputSettings.preferredPhoneOrientation
        }
        return orientation
    }

    private func refreshRotationCoordinator() {
        guard let device = activeVideoDevice else {
            invalidateRotationObservations()
            rotationCoordinator = nil
            return
        }
        if rotationCoordinator?.device === device { return }
        invalidateRotationObservations()
        let coordinator = AVCaptureDevice.RotationCoordinator(
            device: device,
            previewLayer: videoPreviewLayer
        )
        rotationCoordinator = coordinator
        // Both angles: the phone reads the preview angle, program reads the capture
        // angle, and the TV must re-rotate when the phone turns even though its own
        // window never does.
        rotationObservations = [
            coordinator.observe(
                \.videoRotationAngleForHorizonLevelPreview,
                options: [.new]
            ) { [weak self] _, _ in
                self?.applyPreviewOrientation()
            },
            coordinator.observe(
                \.videoRotationAngleForHorizonLevelCapture,
                options: [.new]
            ) { [weak self] _, _ in
                self?.applyPreviewOrientation()
            }
        ]
    }

    private func invalidateRotationObservations() {
        rotationObservations.forEach { $0.invalidate() }
        rotationObservations.removeAll()
    }

    private var activeVideoDevice: AVCaptureDevice? {
        videoPreviewLayer.session?
            .inputs
            .compactMap { $0 as? AVCaptureDeviceInput }
            .map(\.device)
            .first { $0.hasMediaType(.video) }
    }

    /// Front-camera program is unmirrored so shirts, signs, and slides read correctly.
    /// The phone tile / viewfinder keep the familiar selfie mirror.
    static func shouldMirrorPreview(
        isExternalDisplay: Bool,
        cameraPosition: AVCaptureDevice.Position
    ) -> Bool {
        guard cameraPosition == .front else { return false }
        return !isExternalDisplay
    }

    /// Applies horizon-level rotation once a connection exists.
    private func applyPreviewOrientation() {
        guard let connection = videoPreviewLayer.connection else { return }
        refreshRotationCoordinator()
        applyPreviewMirroring(to: connection)
        let angle = programPreviewRotationAngle
        if connection.isVideoRotationAngleSupported(angle),
           connection.videoRotationAngle != angle {
            connection.videoRotationAngle = angle
        }
    }

    /// Preview layers auto-mirror the front lens; program must opt out.
    private func applyPreviewMirroring(to connection: AVCaptureConnection) {
        guard connection.isVideoMirroringSupported else { return }
        let mirror = Self.shouldMirrorPreview(
            isExternalDisplay: isHostedOnExternalDisplay,
            cameraPosition: activeVideoDevice?.position
                ?? CameraManager.shared.cameraPosition
        )
        connection.automaticallyAdjustsVideoMirroring = false
        connection.isVideoMirrored = mirror
    }

    /// Phone layers rotate relative to their own window; the TV layer's window never
    /// turns, so program uses the gravity-based capture angle instead — the same one
    /// stills, recordings, and the phone-side frame mirror already use.
    private var programPreviewRotationAngle: CGFloat {
        if isHostedOnExternalDisplay {
            return rotationCoordinator?.videoRotationAngleForHorizonLevelCapture
                ?? preferredVideoRotationAngle
        }
        return rotationCoordinator?.videoRotationAngleForHorizonLevelPreview
            ?? preferredVideoRotationAngle
    }

    private var isHostedOnExternalDisplay: Bool {
        guard let role = window?.windowScene?.session.role else { return false }
        return ExternalDisplayManager.isExternalDisplayRole(role)
    }
}
