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
    /// Landscape and Vertical keep separate frame libraries.
    let orientation: ExternalOutputOrientation

    enum CodingKeys: String, CodingKey {
        case id, createdAt, orientation
    }

    init(id: UUID, createdAt: Date, orientation: ExternalOutputOrientation) {
        self.id = id
        self.createdAt = createdAt
        self.orientation = orientation
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        createdAt = try c.decode(Date.self, forKey: .createdAt)
        // Legacy frames (no orientation) land in Landscape.
        let raw = try c.decodeIfPresent(String.self, forKey: .orientation)
        orientation = ExternalOutputOrientation.resolved(fromStored: raw)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(createdAt, forKey: .createdAt)
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

    /// Frames for the current Display Mode, newest-first.
    var frames: [CameraFrame] {
        let mode = ExternalOutputSettings.orientation
        return allFrames.filter { $0.orientation == mode }
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
            let frame = CameraFrame(id: id, createdAt: Date(), orientation: mode)
            allFrames.insert(frame, at: 0)
            saveIndex()
            NotificationCenter.default.post(name: Self.didChangeNotification, object: self)
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
        saveIndex()
        NotificationCenter.default.post(name: Self.didChangeNotification, object: self)
    }

    /// Selects a frame in the current Display Mode, or `nil` for None.
    func select(_ id: UUID?) {
        let mode = ExternalOutputSettings.orientation
        if let id, !frames.contains(where: { $0.id == id }) {
            selectedId = nil
            setSelectedId(nil, for: mode)
        } else {
            selectedId = id
            setSelectedId(id, for: mode)
        }
        NotificationCenter.default.post(name: Self.didChangeNotification, object: self)
    }

    // MARK: - Display Mode

    private func displayModeChanged() {
        loadSelection(for: ExternalOutputSettings.orientation)
        NotificationCenter.default.post(name: Self.didChangeNotification, object: self)
    }

    // MARK: - Persistence

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
}
