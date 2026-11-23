//
//  CameraManager+MacFeed.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import AVFoundation

// MARK: - Mac Feed

extension CameraManager {

    /// Sends this frame to the Mac while Camera Mode is streaming.
    ///
    /// Same frame tap the hero and full-screen previews use, so the Mac gets
    /// this camera (zoom, flip and all) rather than a second capture session.
    /// Call on `frameQueue`.
    /// - Parameter sampleBuffer: Frame from the video data output.
    func feedMacProgramIfNeeded(_ sampleBuffer: CMSampleBuffer) {
        let compositor = MacProgramCompositor.shared
        guard compositor.isStreaming else { return }
        compositor.render(
            sampleBuffer,
            rotationDegrees: frameTapRotationAngle(),
            isMirrored: isFrameTapMirrored
        )
    }
}
