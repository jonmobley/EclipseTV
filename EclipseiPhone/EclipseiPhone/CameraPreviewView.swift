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

    override func layoutSubviews() {
        super.layoutSubviews()
        applyPreviewOrientation()
    }

    /// Keeps the capture connection upright for phone + AirPlay panels.
    private func applyPreviewOrientation() {
        guard let connection = videoPreviewLayer.connection else { return }
        // 0° = upright portrait. Phone stage and TV logical panel are upright
        // before any Vertical TV rotation transform is applied on the view.
        let angle: CGFloat = 0
        if connection.isVideoRotationAngleSupported(angle),
           connection.videoRotationAngle != angle {
            connection.videoRotationAngle = angle
        }
    }
}
