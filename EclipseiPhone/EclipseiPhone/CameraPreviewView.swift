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

    /// Syncs rotation from Display Mode + how the phone (camera body) is held.
    ///
    /// Landscape Left vs Right need 0° vs 180° — a fixed `0` for all Landscape made
    /// AirPlay go sideways/upside-down when the scene landed on the other side, and
    /// Flip to the front camera was worse because that sensor is mounted differently.
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

    override func layoutSubviews() {
        super.layoutSubviews()
        applyPreviewOrientation()
    }

    // MARK: - Rotation

    /// Angle for Display Mode previews from the phone window (not the AirPlay scene).
    static var displayModePreviewRotationAngle: CGFloat {
        if ExternalOutputSettings.isVerticalMode { return 90 }
        return phoneApplicationOrientation.cameraPreviewRotationAngle
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

    /// Applies horizon-level rotation once a connection exists.
    private func applyPreviewOrientation() {
        guard let connection = videoPreviewLayer.connection else { return }
        refreshRotationCoordinator()
        let angle = rotationCoordinator?.videoRotationAngleForHorizonLevelPreview
            ?? preferredVideoRotationAngle
        if connection.isVideoRotationAngleSupported(angle),
           connection.videoRotationAngle != angle {
            connection.videoRotationAngle = angle
        }
    }
}
