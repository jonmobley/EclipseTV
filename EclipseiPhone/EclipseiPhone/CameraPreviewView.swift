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
    }

    /// Detaches from any capture session.
    func detach() {
        videoPreviewLayer.session = nil
    }
}
