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
    ///
    /// Across a lens swap the gate drops frames, then claims the first one after the
    /// commit. That frame goes to main, where the previews retarget and enqueue it in
    /// one pass — see `CameraFrameMirrorGate`.
    func broadcastToFrameMirrors(_ sampleBuffer: CMSampleBuffer) {
        frameMirrors.removeAll { $0.view == nil }
        switch withFrameMirrorGate({ $0.action() }) {
        case .drop:
            return
        case .deliver:
            for box in frameMirrors {
                box.view?.enqueue(sampleBuffer)
            }
        case .retarget(let generation):
            // Snapshot here: `frameMirrors` is frame-queue state and must not be
            // read from main.
            let views = frameMirrors.compactMap(\.view)
            DispatchQueue.main.async { [weak self] in
                self?.retargetFrameMirrors(
                    views, with: sampleBuffer, generation: generation
                )
            }
        }
    }

    // MARK: - Lens Swap Gate

    /// Drops mirror frames from here until the swap has retargeted. Session queue.
    func pauseFrameMirrors() {
        withFrameMirrorGate { $0.pause() }
    }

    /// The swap committed. Arms the gate to claim the next frame, or — with no
    /// frames coming — publishes the lens and reopens right away.
    func releaseFrameMirrorsAfterSwap(sessionRunning: Bool) {
        guard sessionRunning else {
            withFrameMirrorGate { $0.open() }
            publishCameraPosition(videoDevice?.position ?? cameraPosition)
            return
        }
        withFrameMirrorGate { $0.awaitFrame() }
    }

    // MARK: - Private

    /// Main thread: publish the lens, rotate the previews, then show the frame.
    ///
    /// Publishing first lets `cameraPositionDidChangeNotification` observers (AirPlay,
    /// flip chrome) run before the notification the mirrors retarget on, and every
    /// step lands in this one main pass so the new turn never shows the old picture.
    private func retargetFrameMirrors(
        _ views: [CameraMirrorView],
        with sampleBuffer: CMSampleBuffer,
        generation: Int
    ) {
        publishCameraPosition(videoDevice?.position ?? cameraPosition)
        NotificationCenter.default.post(
            name: CameraManager.previewRotationNeedsApplyNotification,
            object: self
        )
        // A newer swap paused the gate while this frame was in flight — drop it.
        guard withFrameMirrorGate({ $0.resume(generation: generation) }) else { return }
        for view in views {
            view.enqueue(sampleBuffer)
        }
    }

    private func withFrameMirrorGate<T>(_ body: (inout CameraFrameMirrorGate) -> T) -> T {
        frameMirrorGateLock.lock()
        defer { frameMirrorGateLock.unlock() }
        return body(&frameMirrorGate)
    }
}
