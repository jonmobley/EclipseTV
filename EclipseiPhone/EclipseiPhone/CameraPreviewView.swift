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

    /// Capture-connection angle: 90° fills an upright Vertical (9:16) panel;
    /// 0° fills Landscape (16:9). AirPlay still applies view rotation for a
    /// portrait-mounted TV — every preview layer uses the same angle.
    var preferredVideoRotationAngle: CGFloat = 0 {
        didSet {
            guard preferredVideoRotationAngle != oldValue else { return }
            applyPreviewOrientation()
        }
    }

    /// Binds this view to `session` and sets video gravity.
    func attach(session: AVCaptureSession,
                videoGravity: AVLayerVideoGravity = .resizeAspect) {
        videoPreviewLayer.session = session
        videoPreviewLayer.videoGravity = videoGravity
        backgroundColor = .black
        applyPreviewOrientation()
    }

    /// Detaches from any capture session.
    func detach() {
        videoPreviewLayer.session = nil
    }

    /// Syncs `preferredVideoRotationAngle` from the current Display Mode.
    func syncDisplayModeOrientation() {
        preferredVideoRotationAngle =
            ExternalOutputSettings.isVerticalMode ? 90 : 0
        applyPreviewOrientation()
    }

    /// Still of the current preview (for home-tile freeze after camera stops).
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

    /// Applies the preferred capture-connection rotation once a connection exists.
    private func applyPreviewOrientation() {
        guard let connection = videoPreviewLayer.connection else { return }
        let angle = preferredVideoRotationAngle
        if connection.isVideoRotationAngleSupported(angle),
           connection.videoRotationAngle != angle {
            connection.videoRotationAngle = angle
        }
    }
}
