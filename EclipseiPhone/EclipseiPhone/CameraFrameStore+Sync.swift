//
//  CameraFrameStore+Sync.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import Foundation

// MARK: - CloudKit upload acknowledgements

extension CameraFrameStore {

    private static let syncedFrameIdsKey = "EclipseTV.camera.syncedFrameIds"
    private static let syncedSettingsKey =
        "EclipseTV.camera.syncedSettingsOrientations"

    /// Frames the server has not acknowledged — bootstrap must not re-insert the rest.
    var frameIdsNeedingUpload: [UUID] {
        allFramesForSync
            .map(\.id)
            .filter { !syncedFrameIdStrings.contains($0.uuidString) }
    }

    /// Display Modes whose ribbon settings still need a first successful save.
    var settingsOrientationsNeedingUpload: [ExternalOutputOrientation] {
        ExternalOutputOrientation.allCases.filter {
            !syncedSettingsOrientationStrings.contains($0.rawValue)
        }
    }

    /// Records that CloudKit accepted this frame's upload (or it arrived remotely).
    func markFrameSynced(id: UUID) {
        var ids = syncedFrameIdStrings
        guard ids.insert(id.uuidString).inserted else { return }
        UserDefaults.standard.set(Array(ids), forKey: Self.syncedFrameIdsKey)
    }

    /// Marks `id` dirty so the next bootstrap will upload the PNG again.
    func markFrameNeedsUpload(id: UUID) {
        var ids = syncedFrameIdStrings
        guard ids.remove(id.uuidString) != nil else { return }
        UserDefaults.standard.set(Array(ids), forKey: Self.syncedFrameIdsKey)
    }

    /// Records that CloudKit accepted ribbon settings for `orientation`.
    func markSettingsSynced(orientation: ExternalOutputOrientation) {
        var raw = syncedSettingsOrientationStrings
        guard raw.insert(orientation.rawValue).inserted else { return }
        UserDefaults.standard.set(Array(raw), forKey: Self.syncedSettingsKey)
    }

    /// Marks ribbon settings dirty for `orientation`.
    func markSettingsNeedsUpload(orientation: ExternalOutputOrientation) {
        var raw = syncedSettingsOrientationStrings
        guard raw.remove(orientation.rawValue) != nil else { return }
        UserDefaults.standard.set(Array(raw), forKey: Self.syncedSettingsKey)
    }

    /// Parses `eclipse.cameraSettings.<Orientation>` and marks that mode synced.
    func markSettingsSynced(recordName: String) {
        let prefix = "eclipse.cameraSettings."
        guard recordName.hasPrefix(prefix) else { return }
        let raw = String(recordName.dropFirst(prefix.count))
        markSettingsSynced(
            orientation: ExternalOutputOrientation.resolved(fromStored: raw)
        )
    }

    /// Marks every frame and both Display Modes dirty (zone recreate / re-push).
    func markAllNeedsUpload() {
        for id in allFramesForSync.map(\.id) {
            markFrameNeedsUpload(id: id)
        }
        for orientation in ExternalOutputOrientation.allCases {
            markSettingsNeedsUpload(orientation: orientation)
        }
    }

    private var syncedFrameIdStrings: Set<String> {
        Set(UserDefaults.standard.stringArray(forKey: Self.syncedFrameIdsKey) ?? [])
    }

    private var syncedSettingsOrientationStrings: Set<String> {
        Set(UserDefaults.standard.stringArray(forKey: Self.syncedSettingsKey) ?? [])
    }
}
