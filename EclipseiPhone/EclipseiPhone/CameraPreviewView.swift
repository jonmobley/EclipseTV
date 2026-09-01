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
    private var rotationObservation: NSKeyValueObservation?

    deinit {
        rotationObservation?.invalidate()
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
        rotationObservation?.invalidate()
        rotationObservation = nil
        rotationCoordinator = nil
        videoPreviewLayer.session = nil
    }

    /// Syncs rotation from Display Mode. Program does not follow how the iPad is held.
    ///
    /// Landscape Left vs Right (same axis as Landscape mode) still need 0° vs 180°
    /// so AirPlay is not upside-down when the camera UI lands on the other side.
    func syncDisplayModeOrientation() {
        preferredVideoRotationAngle = Self.displayModePreviewRotationAngle
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

    /// Angle for the AirPlay / Display Mode panel — pinned to Vertical or Landscape.
    ///
    /// Thumbnail-page live camera leaves the iPad free to rotate; program stays in
    /// the configured output mode so a Vertical stage does not become Landscape
    /// (and vice versa) when the operator turns the tablet.
    static var displayModePreviewRotationAngle: CGFloat {
        programRotationAngle(
            isVerticalMode: ExternalOutputSettings.isVerticalMode,
            phoneOrientation: phoneApplicationOrientation
        )
    }

    /// Program sensor angle for Display Mode, ignoring a mismatched phone hold.
    static func programRotationAngle(
        isVerticalMode: Bool,
        phoneOrientation: UIInterfaceOrientation
    ) -> CGFloat {
        if isVerticalMode {
            if phoneOrientation.isPortrait {
                return phoneOrientation.cameraPreviewRotationAngle
            }
            return UIInterfaceOrientation.portrait.cameraPreviewRotationAngle
        }
        if phoneOrientation.isLandscape {
            return phoneOrientation.cameraPreviewRotationAngle
        }
        return UIInterfaceOrientation.landscapeRight.cameraPreviewRotationAngle
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
            rotationObservation?.invalidate()
            rotationObservation = nil
            rotationCoordinator = nil
            return
        }
        if rotationCoordinator?.device === device { return }
        rotationObservation?.invalidate()
        let coordinator = AVCaptureDevice.RotationCoordinator(
            device: device,
            previewLayer: videoPreviewLayer
        )
        rotationCoordinator = coordinator
        rotationObservation = coordinator.observe(
            \.videoRotationAngleForHorizonLevelPreview,
            options: [.new]
        ) { [weak self] _, _ in
            self?.applyPreviewOrientation()
        }
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

    /// AirPlay stays on Display Mode. The preview-layer coordinator follows gravity
    /// and would reorient program when the iPad turns on the thumbnail page.
    private var programPreviewRotationAngle: CGFloat {
        if isHostedOnExternalDisplay {
            return preferredVideoRotationAngle
        }
        return rotationCoordinator?.videoRotationAngleForHorizonLevelPreview
            ?? preferredVideoRotationAngle
    }

    private var isHostedOnExternalDisplay: Bool {
        guard let role = window?.windowScene?.session.role else { return false }
        return ExternalDisplayManager.isExternalDisplayRole(role)
    }
}
