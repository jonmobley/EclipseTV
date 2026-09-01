//
//  CameraFrameStore.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import UIKit
import os.log

/// One user-uploaded PNG camera overlay frame for a single Display Mode.
struct CameraFrame: Equatable, Identifiable, Codable {
    let id: UUID
    let createdAt: Date
    /// Bumped when the user selects this frame; drives recent-first ordering.
    var lastUsedAt: Date
    /// Landscape and Vertical keep separate frame libraries.
    let orientation: ExternalOutputOrientation

    enum CodingKeys: String, CodingKey {
        case id, createdAt, lastUsedAt, orientation
    }

    init(
        id: UUID,
        createdAt: Date,
        lastUsedAt: Date,
        orientation: ExternalOutputOrientation
    ) {
        self.id = id
        self.createdAt = createdAt
        self.lastUsedAt = lastUsedAt
        self.orientation = orientation
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        createdAt = try c.decode(Date.self, forKey: .createdAt)
        // Pre-recents frames treat import time as last used.
        lastUsedAt = try c.decodeIfPresent(Date.self, forKey: .lastUsedAt) ?? createdAt
        // Legacy frames (no orientation) land in Landscape.
        let raw = try c.decodeIfPresent(String.self, forKey: .orientation)
        orientation = ExternalOutputOrientation.resolved(fromStored: raw)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(createdAt, forKey: .createdAt)
        try c.encode(lastUsedAt, forKey: .lastUsedAt)
        try c.encode(orientation.rawValue, forKey: .orientation)
    }
}

/// Persists PNG camera frames (with alpha) under Application Support.
///
/// Landscape and Vertical each have their own library and selection.
@MainActor
final class CameraFrameStore {

    static let shared = CameraFrameStore()

    /// Posted when the library or selection changes.
    static let didChangeNotification = Notification.Name("CameraFrameStore.didChange")

    /// Soft cap per Display Mode so storage stays bounded.
    static let maxFrameCount = 20

    private static let legacySelectedIdKey = "EclipseTV.camera.selectedFrameId"
    private static let indexFileName = "index.json"

    /// All frames on disk (both modes). Prefer `frames` for the active mode.
    private var allFrames: [CameraFrame] = []

    /// Frames for the current Display Mode, recently used first.
    var frames: [CameraFrame] {
        let mode = ExternalOutputSettings.orientation
        return allFrames
            .filter { $0.orientation == mode }
            .sorted {
                if $0.lastUsedAt != $1.lastUsedAt {
                    return $0.lastUsedAt > $1.lastUsedAt
                }
                return $0.createdAt > $1.createdAt
            }
    }

    /// Selected frame id for the current Display Mode, or `nil` for None.
    private(set) var selectedId: UUID?

    /// Image for the current mode’s selection (nil when None).
    var selectedImage: UIImage? {
        guard let selectedId else { return nil }
        return image(for: selectedId)
    }

    private let directory: URL
    private let indexURL: URL
    private let logger = Logger(subsystem: "com.eclipseapp.ios", category: "CameraFrame")

    private init() {
        let base = FileManager.default.urls(
            for: .applicationSupportDirectory, in: .userDomainMask
        )[0]
        directory = base.appendingPathComponent("CameraFrames", isDirectory: true)
        indexURL = directory.appendingPathComponent(Self.indexFileName)
        try? FileManager.default.createDirectory(
            at: directory, withIntermediateDirectories: true
        )
        loadIndex()
        migrateLegacySelectionIfNeeded()
        loadSelection(for: ExternalOutputSettings.orientation)
        NotificationCenter.default.addObserver(
            forName: ExternalOutputSettings.didChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.displayModeChanged()
            }
        }
    }

    // MARK: - Queries

    /// Loads the PNG for `id` from disk.
    func image(for id: UUID) -> UIImage? {
        UIImage(contentsOfFile: fileURL(for: id).path)
    }

    /// On-disk URL for a frame PNG.
    func fileURL(for id: UUID) -> URL {
        directory.appendingPathComponent("\(id.uuidString).png")
    }

    /// Remaining import slots for the current Display Mode.
    var remainingSlots: Int {
        max(0, Self.maxFrameCount - frames.count)
    }

    /// Frame ids stored for `orientation` (used by the ribbon enabled-set).
    func frameIds(in orientation: ExternalOutputOrientation) -> Set<UUID> {
        Set(allFrames.filter { $0.orientation == orientation }.map(\.id))
    }

    /// Turns off the live overlay when `id` is the current selection.
    func clearLiveIfSelected(_ id: UUID) {
        let mode = ExternalOutputSettings.orientation
        guard selectedId == id else { return }
        selectedId = nil
        setSelectedId(nil, for: mode)
    }

    // MARK: - Mutations

    /// Adds a PNG frame to the current Display Mode’s library.
    @discardableResult
    func add(_ image: UIImage) -> UUID? {
        let mode = ExternalOutputSettings.orientation
        guard frames.count < Self.maxFrameCount else {
            logger.error("Camera frame library full for \(mode.rawValue, privacy: .public)")
            return nil
        }
        let oriented = MediaAspect.normalized(image)
        guard let data = oriented.pngData() else {
            logger.error("Failed to encode camera frame PNG")
            return nil
        }
        let id = UUID()
        do {
            try data.write(to: fileURL(for: id), options: .atomic)
            let now = Date()
            let frame = CameraFrame(
                id: id,
                createdAt: now,
                lastUsedAt: now,
                orientation: mode
            )
            allFrames.insert(frame, at: 0)
            saveIndex()
            insertEnabled(id)
            NotificationCenter.default.post(name: Self.didChangeNotification, object: self)
            guard !EclipseSyncController.shared.isApplyingRemote else { return id }
            markSettingsNeedsUpload(orientation: mode)
            EclipseSyncController.shared.backend.scheduleCameraFrameSave(id: id)
            EclipseSyncController.shared.backend.scheduleCameraSettingsSave(
                orientation: mode
            )
            return id
        } catch {
            logger.error("Failed to write frame: \(error.localizedDescription)")
            return nil
        }
    }

    /// Removes a frame. Clears selection if it was selected in its mode.
    func remove(_ id: UUID) {
        guard let frame = allFrames.first(where: { $0.id == id }) else { return }
        allFrames.removeAll { $0.id == id }
        try? FileManager.default.removeItem(at: fileURL(for: id))
        if selectedIdKeyValue(for: frame.orientation) == id {
            setSelectedId(nil, for: frame.orientation)
        }
        if frame.orientation == ExternalOutputSettings.orientation {
            selectedId = selectedIdKeyValue(for: frame.orientation)
        }
        removeEnabled(id, orientation: frame.orientation)
        saveIndex()
        NotificationCenter.default.post(name: Self.didChangeNotification, object: self)
        guard !EclipseSyncController.shared.isApplyingRemote else { return }
        markFrameNeedsUpload(id: id)
        markSettingsNeedsUpload(orientation: frame.orientation)
        EclipseSyncController.shared.backend.scheduleCameraFrameDelete(id: id)
        EclipseSyncController.shared.backend.scheduleCameraSettingsSave(
            orientation: frame.orientation
        )
    }

    /// Rewrites `id`'s PNG rotated 90° clockwise.
    func rotateClockwise(_ id: UUID) {
        rewriteRotated(id, clockwise: true)
    }

    /// Rewrites `id`'s PNG rotated 90° counterclockwise.
    func rotateCounterclockwise(_ id: UUID) {
        rewriteRotated(id, clockwise: false)
    }

    /// Makes a frame live on the camera (ribbon tap), or `nil` for no overlay.
    func select(_ id: UUID?) {
        let mode = ExternalOutputSettings.orientation
        if let id, !frames.contains(where: { $0.id == id }) {
            selectedId = nil
            setSelectedId(nil, for: mode)
        } else {
            selectedId = id
            setSelectedId(id, for: mode)
            if let id {
                touchLastUsed(for: id)
            }
        }
        NotificationCenter.default.post(name: Self.didChangeNotification, object: self)
        guard !EclipseSyncController.shared.isApplyingRemote else { return }
        markSettingsNeedsUpload(orientation: mode)
        EclipseSyncController.shared.backend.scheduleCameraSettingsSave(orientation: mode)
    }

    private func rewriteRotated(_ id: UUID, clockwise: Bool) {
        guard allFrames.contains(where: { $0.id == id }),
              let image = image(for: id) else { return }
        let rotated = clockwise
            ? MediaAspect.rotatedClockwise(image)
            : MediaAspect.rotatedCounterclockwise(image)
        guard let data = rotated.pngData() else {
            logger.error("Failed to encode rotated camera frame PNG")
            return
        }
        do {
            try data.write(to: fileURL(for: id), options: .atomic)
            NotificationCenter.default.post(name: Self.didChangeNotification, object: self)
            guard !EclipseSyncController.shared.isApplyingRemote else { return }
            markFrameNeedsUpload(id: id)
            EclipseSyncController.shared.backend.scheduleCameraFrameSave(id: id)
        } catch {
            logger.error("Failed to write rotated frame: \(error.localizedDescription)")
        }
    }

    // MARK: - Display Mode

    private func displayModeChanged() {
        loadSelection(for: ExternalOutputSettings.orientation)
        NotificationCenter.default.post(name: Self.didChangeNotification, object: self)
    }

    // MARK: - Persistence

    private func touchLastUsed(for id: UUID) {
        guard let index = allFrames.firstIndex(where: { $0.id == id }) else { return }
        allFrames[index].lastUsedAt = Date()
        saveIndex()
    }

    private func loadIndex() {
        guard let data = try? Data(contentsOf: indexURL),
              let decoded = try? JSONDecoder().decode([CameraFrame].self, from: data)
        else {
            allFrames = []
            return
        }
        allFrames = decoded.filter {
            FileManager.default.fileExists(atPath: fileURL(for: $0.id).path)
        }
        if allFrames.count != decoded.count {
            saveIndex()
        }
    }

    private func saveIndex() {
        do {
            let data = try JSONEncoder().encode(allFrames)
            try data.write(to: indexURL, options: .atomic)
        } catch {
            logger.error("Failed to save frame index: \(error.localizedDescription)")
        }
    }

    private func selectedDefaultsKey(for orientation: ExternalOutputOrientation) -> String {
        "EclipseTV.camera.selectedFrameId.\(orientation.rawValue)"
    }

    private func selectedIdKeyValue(for orientation: ExternalOutputOrientation) -> UUID? {
        guard let raw = UserDefaults.standard.string(
            forKey: selectedDefaultsKey(for: orientation)
        ) else { return nil }
        return UUID(uuidString: raw)
    }

    private func setSelectedId(_ id: UUID?, for orientation: ExternalOutputOrientation) {
        let key = selectedDefaultsKey(for: orientation)
        if let id {
            UserDefaults.standard.set(id.uuidString, forKey: key)
        } else {
            UserDefaults.standard.removeObject(forKey: key)
        }
    }

    private func loadSelection(for orientation: ExternalOutputOrientation) {
        if let id = selectedIdKeyValue(for: orientation),
           allFrames.contains(where: { $0.id == id && $0.orientation == orientation }) {
            selectedId = id
        } else {
            selectedId = nil
            setSelectedId(nil, for: orientation)
        }
    }

    /// Moves the pre-split global selection into the Landscape bucket once.
    private func migrateLegacySelectionIfNeeded() {
        let legacyKey = Self.legacySelectedIdKey
        guard let raw = UserDefaults.standard.string(forKey: legacyKey),
              let id = UUID(uuidString: raw) else { return }
        let landscapeKey = selectedDefaultsKey(for: .landscape)
        if UserDefaults.standard.string(forKey: landscapeKey) == nil,
           allFrames.contains(where: { $0.id == id }) {
            UserDefaults.standard.set(raw, forKey: landscapeKey)
        }
        UserDefaults.standard.removeObject(forKey: legacyKey)
    }

    // MARK: - CloudKit Sync

    /// Every frame on disk (both Display Modes) for bootstrap enqueue.
    var allFramesForSync: [CameraFrame] { allFrames }

    /// Frame metadata for `id`, if present.
    func frame(id: UUID) -> CameraFrame? {
        allFrames.first { $0.id == id }
    }

    /// Selected overlay id for `orientation`.
    func selectedId(for orientation: ExternalOutputOrientation) -> UUID? {
        selectedIdKeyValue(for: orientation)
    }

    /// Inserts or replaces a frame that arrived from iCloud.
    func applyRemote(
        id: UUID,
        orientation: ExternalOutputOrientation,
        createdAt: Date,
        assetURL: URL
    ) {
        let destination = fileURL(for: id)
        do {
            if FileManager.default.fileExists(atPath: destination.path) {
                try FileManager.default.removeItem(at: destination)
            }
            try FileManager.default.copyItem(at: assetURL, to: destination)
        } catch {
            logger.error("Remote frame copy failed: \(error.localizedDescription)")
            return
        }
        if let index = allFrames.firstIndex(where: { $0.id == id }) {
            allFrames[index] = CameraFrame(
                id: id,
                createdAt: createdAt,
                lastUsedAt: allFrames[index].lastUsedAt,
                orientation: orientation
            )
        } else {
            allFrames.append(
                CameraFrame(
                    id: id,
                    createdAt: createdAt,
                    lastUsedAt: createdAt,
                    orientation: orientation
                )
            )
            insertEnabled(id)
        }
        saveIndex()
        markFrameSynced(id: id)
        NotificationCenter.default.post(name: Self.didChangeNotification, object: self)
    }

    /// Applies ribbon enabled / selected state from iCloud.
    func applyRemoteSettings(
        orientation: ExternalOutputOrientation,
        enabledIds: [UUID],
        selectedId: UUID?
    ) {
        let valid = frameIds(in: orientation)
        let filtered = Set(enabledIds).intersection(valid)
        UserDefaults.standard.set(
            filtered.map(\.uuidString).sorted(),
            forKey: "EclipseTV.camera.enabledFrameIds.\(orientation.rawValue)"
        )
        if let selectedId, valid.contains(selectedId) {
            setSelectedId(selectedId, for: orientation)
        } else {
            setSelectedId(nil, for: orientation)
        }
        if orientation == ExternalOutputSettings.orientation {
            loadSelection(for: orientation)
        }
        markSettingsSynced(orientation: orientation)
        NotificationCenter.default.post(name: Self.didChangeNotification, object: self)
    }

    /// Ribbon-enabled ids for `orientation` (CloudKit upload).
    func enabledIds(for orientation: ExternalOutputOrientation) -> Set<UUID> {
        let key = "EclipseTV.camera.enabledFrameIds.\(orientation.rawValue)"
        let valid = frameIds(in: orientation)
        guard let raw = UserDefaults.standard.array(forKey: key) as? [String] else {
            return valid
        }
        return Set(raw.compactMap(UUID.init(uuidString:))).intersection(valid)
    }
}
