//
//  CameraManager+Zoom.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import AVFoundation
import UIKit

// MARK: - Zoom

extension CameraManager {

    /// Current video zoom factor (1 = no zoom).
    var zoomFactor: CGFloat {
        videoDevice?.videoZoomFactor ?? 1
    }

    /// Minimum zoom supported by the active camera.
    var minZoomFactor: CGFloat {
        videoDevice?.minAvailableVideoZoomFactor ?? 1
    }

    /// Maximum zoom used by pinch (capped for quality).
    var maxZoomFactor: CGFloat {
        guard let device = videoDevice else { return 1 }
        return min(device.maxAvailableVideoZoomFactor, preferredMaxZoom)
    }

    /// Sets device zoom; affects phone preview and AirPlay together.
    /// - Parameter factor: Desired zoom factor, clamped to device limits.
    func setZoomFactor(_ factor: CGFloat) {
        sessionQueue.async { [weak self] in
            guard let self, let device = self.videoDevice else { return }
            let clamped = min(max(factor, self.minZoomFactor), self.maxZoomFactor)
            guard abs(device.videoZoomFactor - clamped) > 0.001 else { return }
            do {
                try device.lockForConfiguration()
                device.videoZoomFactor = clamped
                device.unlockForConfiguration()
            } catch {
                self.logger.error(
                    "Zoom failed: \(error.localizedDescription)"
                )
            }
        }
    }

    /// Resets zoom to 1×.
    func resetZoom() {
        setZoomFactor(minZoomFactor)
    }
}
