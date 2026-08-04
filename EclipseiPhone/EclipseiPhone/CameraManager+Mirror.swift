//
//  CameraManager+Mirror.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import AVFoundation

/// Weak handle so a torn-down mirror view is never kept alive by the frame tap.
struct WeakFrameMirror {
    weak var view: CameraMirrorView?
}

// MARK: - Frame Mirrors

extension CameraManager {

    /// Registers `view` for full-rate frames until `removeFrameMirror(_:)`.
    func addFrameMirror(_ view: CameraMirrorView) {
        frameQueue.async { [weak self] in
            guard let self else { return }
            frameMirrors.removeAll { $0.view == nil || $0.view === view }
            frameMirrors.append(WeakFrameMirror(view: view))
        }
    }

    /// Stops delivering frames to `view`.
    func removeFrameMirror(_ view: CameraMirrorView) {
        frameQueue.async { [weak self, weak view] in
            guard let self else { return }
            frameMirrors.removeAll { $0.view == nil || $0.view === view }
        }
    }

    /// Hands `sampleBuffer` to every registered mirror. Call on `frameQueue`.
    func broadcastToFrameMirrors(_ sampleBuffer: CMSampleBuffer) {
        guard !frameMirrors.isEmpty else { return }
        var didLoseMirror = false
        for box in frameMirrors {
            guard let view = box.view else {
                didLoseMirror = true
                continue
            }
            view.enqueue(sampleBuffer)
        }
        if didLoseMirror {
            frameMirrors.removeAll { $0.view == nil }
        }
    }
}
