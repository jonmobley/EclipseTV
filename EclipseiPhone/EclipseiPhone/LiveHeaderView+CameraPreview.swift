//
//  LiveHeaderView+CameraPreview.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import UIKit

// MARK: - In-App Live Camera Preview

extension LiveHeaderView {

    /// True while the hero is mirroring the live camera feed.
    var isCameraPreviewActive: Bool { cameraPreview?.isMirroring == true }

    /// Fallback if the mirror's first frame never arrives.
    private static let mirrorFirstFrameTimeout: TimeInterval = 0.35

    /// Shows the live camera in the hero via the frame-tap mirror.
    ///
    /// AirPlay keeps the session's one `AVCaptureVideoPreviewLayer`, so the phone
    /// hero renders here instead — same frames, no competition for the connection.
    func showCameraPreview() {
        titleLabel.isHidden = true
        if isCameraPreviewActive {
            layoutCameraPreviewIfNeeded()
            setStaticPreviewHidden(true)
            bringCameraPreviewChromeToFront()
            return
        }
        clearWebPreview(parking: true)
        clearScreensaverPreview()
        ensureCameraPreviewHost()
        guard let host = cameraPreviewHost, let preview = cameraPreview else { return }
        preview.videoGravity = CameraPreviewView.programVideoGravity
        preview.onFirstFrame = { [weak self] in
            self?.setStaticPreviewHidden(true)
        }
        host.isHidden = false
        preview.startMirroring()
        layoutCameraPreviewIfNeeded()
        bringCameraPreviewChromeToFront()
        DispatchQueue.main.asyncAfter(
            deadline: .now() + Self.mirrorFirstFrameTimeout
        ) { [weak self] in
            guard let self, self.isCameraPreviewActive else { return }
            self.setStaticPreviewHidden(true)
        }
    }

    /// Stops the in-hero camera mirror.
    func clearCameraPreview() {
        cameraPreview?.onFirstFrame = nil
        cameraPreview?.stopMirroring()
        cameraPreviewHost?.isHidden = true
        setStaticPreviewHidden(false)
    }

    /// Rotates sensor frames to match Display Mode after layout / lens flip.
    func layoutCameraPreviewIfNeeded() {
        guard let host = cameraPreviewHost, let preview = cameraPreview,
              !host.isHidden
        else {
            return
        }
        let degrees = Double(
            CameraManager.shared.quantizedRotationAngle(
                CameraPreviewView.displayModePreviewRotationAngle
            )
        )
        PresentationViewController.applyRotatedLayout(
            to: preview,
            in: host,
            scale: 1,
            rotationDegrees: degrees
        )
    }

    // MARK: - Private

    /// Creates the camera-preview host once, pinned under LIVE chrome.
    private func ensureCameraPreviewHost() {
        if cameraPreviewHost != nil { return }
        let host = UIView()
        host.backgroundColor = .black
        host.clipsToBounds = true
        host.isUserInteractionEnabled = false
        host.translatesAutoresizingMaskIntoConstraints = false
        host.isHidden = true
        insertSubview(host, at: 0)
        NSLayoutConstraint.activate([
            host.topAnchor.constraint(equalTo: topAnchor),
            host.bottomAnchor.constraint(equalTo: bottomAnchor),
            host.leadingAnchor.constraint(equalTo: leadingAnchor),
            host.trailingAnchor.constraint(equalTo: trailingAnchor)
        ])
        let preview = CameraMirrorView()
        preview.translatesAutoresizingMaskIntoConstraints = true
        host.addSubview(preview)
        cameraPreviewHost = host
        cameraPreview = preview
    }

    /// Keeps LIVE chrome above the embedded camera mirror.
    private func bringCameraPreviewChromeToFront() {
        if let host = cameraPreviewHost {
            insertSubview(host, at: 0)
        }
        bringWebPreviewChromeToFront()
    }
}
