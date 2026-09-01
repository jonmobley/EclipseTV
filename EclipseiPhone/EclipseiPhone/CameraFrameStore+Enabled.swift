//
//  CameraFrameStore+Enabled.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import Foundation

// MARK: - Camera Ribbon Membership

extension CameraFrameStore {

    /// Frames the user pinned onto the camera overlay ribbon (current mode).
    var enabledFrames: [CameraFrame] {
        let ids = enabledIds
        return frames.filter { ids.contains($0.id) }
    }

    /// Whether `id` appears as a camera ribbon thumbnail.
    func isEnabled(_ id: UUID) -> Bool {
        enabledIds.contains(id)
    }

    /// Pins or unpins a frame on the camera ribbon. Does not make it live.
    ///
    /// Unpinning the live frame clears the overlay.
    func toggleEnabled(_ id: UUID) {
        guard frames.contains(where: { $0.id == id }) else { return }
        let mode = ExternalOutputSettings.orientation
        var ids = enabledIds
        if ids.contains(id) {
            ids.remove(id)
            clearLiveIfSelected(id)
        } else {
            ids.insert(id)
        }
        persistEnabledIds(ids, for: mode)
        NotificationCenter.default.post(name: Self.didChangeNotification, object: self)
        guard !EclipseSyncController.shared.isApplyingRemote else { return }
        markSettingsNeedsUpload(orientation: mode)
        EclipseSyncController.shared.backend.scheduleCameraSettingsSave(orientation: mode)
    }

    /// Pins a newly imported frame onto the current-mode ribbon.
    func insertEnabled(_ id: UUID) {
        let mode = ExternalOutputSettings.orientation
        var ids = enabledIds
        guard ids.insert(id).inserted else { return }
        persistEnabledIds(ids, for: mode)
    }

    /// Drops `id` from that mode’s ribbon set.
    func removeEnabled(_ id: UUID, orientation: ExternalOutputOrientation) {
        var ids = enabledIds(for: orientation)
        guard ids.remove(id) != nil else { return }
        persistEnabledIds(ids, for: orientation)
    }

    // MARK: - Persistence

    private var enabledIds: Set<UUID> {
        enabledIds(for: ExternalOutputSettings.orientation)
    }

    private func persistEnabledIds(
        _ ids: Set<UUID>,
        for orientation: ExternalOutputOrientation
    ) {
        UserDefaults.standard.set(
            ids.map(\.uuidString).sorted(),
            forKey: enabledDefaultsKey(for: orientation)
        )
    }

    private func enabledDefaultsKey(for orientation: ExternalOutputOrientation) -> String {
        "EclipseTV.camera.enabledFrameIds.\(orientation.rawValue)"
    }
}
