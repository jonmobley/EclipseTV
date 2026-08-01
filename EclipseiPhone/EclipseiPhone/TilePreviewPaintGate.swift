//
//  TilePreviewPaintGate.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import AVFoundation
import UIKit

/// Waits until a camera preview layer is plausibly painting, then fires once.
///
/// `AVCaptureVideoPreviewLayer` publishes no "has content" flag, so this watches the
/// two things that are observable: the capture connection going active, and display
/// refreshes committing after that. The Camera tile used to uncover its live feed on a
/// fixed delay, which cannot tell "painting" from "main thread busy" — and an
/// unpainted layer shows its black background, which is what blinked.
final class TilePreviewPaintGate {

    private let preview: CameraPreviewView
    private let framesRequired: Int
    private let deadline: CFAbsoluteTime
    private var handler: (() -> Void)?
    private var displayLink: CADisplayLink?
    private var activeFrames = 0

    /// Starts watching immediately.
    /// - Parameters:
    ///   - preview: The layer-backed view to watch.
    ///   - framesRequired: Committed display frames needed once the connection is active.
    ///   - timeout: Fires anyway after this long, rather than sitting on a stale still.
    ///   - handler: Called at most once, on the main queue, unless `cancel()` comes first.
    init(
        preview: CameraPreviewView,
        framesRequired: Int = 3,
        timeout: CFAbsoluteTime = 1,
        handler: @escaping () -> Void
    ) {
        self.preview = preview
        self.framesRequired = framesRequired
        self.deadline = CFAbsoluteTimeGetCurrent() + timeout
        self.handler = handler

        let link = CADisplayLink(target: self, selector: #selector(step))
        link.add(to: .main, forMode: .common)
        displayLink = link
    }

    /// Stops watching without firing.
    func cancel() {
        finish(fire: false)
    }

    // MARK: - Private

    @objc private func step() {
        guard CFAbsoluteTimeGetCurrent() < deadline else {
            finish(fire: true)
            return
        }
        guard CameraManager.shared.isSessionRunning,
              preview.videoPreviewLayer.connection?.isActive == true
        else {
            activeFrames = 0
            return
        }
        activeFrames += 1
        guard activeFrames >= framesRequired else { return }
        finish(fire: true)
    }

    private func finish(fire: Bool) {
        // The display link retains this object, so invalidate before handing off.
        displayLink?.invalidate()
        displayLink = nil
        let pending = handler
        handler = nil
        if fire { pending?() }
    }
}
