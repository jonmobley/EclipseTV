//
//  CameraVideoStabilization.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import AVFoundation

/// Handheld EIS for live program and recordings.
///
/// Live prefers preview-optimized (then low-latency on iOS 26+, then auto) so AirPlay
/// does not pick up cinematic latency. Recordings prefer standard, then auto. Cinematic
/// modes are never selected — extra delay and a tighter FOV are worse than residual
/// shake in a live room.
enum CameraVideoStabilization {

    /// Which capture connection is being configured.
    enum Role: Equatable {
        /// Preview layer and video-data-output (phone + AirPlay).
        case live
        /// Movie file output.
        case recording
    }

    /// Named modes so tests do not depend on iOS 26's `.lowLatency` case.
    enum Mode: Equatable {
        case previewOptimized
        case lowLatency
        case auto
        case standard
        case off
    }

    /// Modes tried in order for `role`. Never includes cinematic variants.
    static func candidates(
        for role: Role,
        lowLatencyAvailable: Bool
    ) -> [Mode] {
        switch role {
        case .live:
            var modes: [Mode] = [.previewOptimized]
            if lowLatencyAvailable {
                modes.append(.lowLatency)
            }
            modes.append(.auto)
            return modes
        case .recording:
            return [.standard, .auto]
        }
    }

    /// First candidate the hardware reports as supported, or `.off`.
    static func preferredMode(
        for role: Role,
        lowLatencyAvailable: Bool = Self.isLowLatencyAvailable,
        isSupported: (Mode) -> Bool
    ) -> Mode {
        candidates(for: role, lowLatencyAvailable: lowLatencyAvailable)
            .first(where: isSupported) ?? .off
    }

    /// Writes `preferredVideoStabilizationMode` when the connection can stabilize.
    static func apply(
        _ role: Role,
        to connection: AVCaptureConnection,
        format: AVCaptureDevice.Format?
    ) {
        guard connection.isVideoStabilizationSupported else { return }
        let chosen = preferredMode(for: role) { mode in
            isSupported(mode, by: format)
        }
        guard chosen != .off, let capture = captureMode(for: chosen) else { return }
        connection.preferredVideoStabilizationMode = capture
    }

    /// True when the running OS has `.lowLatency` (iOS 26+).
    static var isLowLatencyAvailable: Bool {
        if #available(iOS 26.0, *) { return true }
        return false
    }

    /// AVFoundation mode for `mode`, or `nil` when the SDK / OS cannot name it.
    static func captureMode(for mode: Mode) -> AVCaptureVideoStabilizationMode? {
        switch mode {
        case .previewOptimized:
            return .previewOptimized
        case .lowLatency:
            if #available(iOS 26.0, *) { return .lowLatency }
            return nil
        case .auto:
            return .auto
        case .standard:
            return .standard
        case .off:
            return .off
        }
    }

    // MARK: - Private

    private static func isSupported(
        _ mode: Mode,
        by format: AVCaptureDevice.Format?
    ) -> Bool {
        guard let capture = captureMode(for: mode), capture != .off else {
            return false
        }
        guard let format else { return true }
        return format.isVideoStabilizationModeSupported(capture)
    }
}
