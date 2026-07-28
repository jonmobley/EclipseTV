//
//  CameraFrameStore.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import UIKit
import os.log

/// One user-uploaded PNG camera overlay frame.
struct CameraFrame: Equatable, Identifiable, Codable {
    let id: UUID
    let createdAt: Date
}

/// Persists PNG camera frames (with alpha) under Application Support.
@MainActor
final class CameraFrameStore {

    static let shared = CameraFrameStore()

    /// Posted when the library or selection changes.
    static let didChangeNotification = Notification.Name("CameraFrameStore.didChange")

    /// Soft cap so storage stays bounded.
    static let maxFrameCount = 20

    private static let selectedIdKey = "EclipseTV.camera.selectedFrameId"
    private static let indexFileName = "index.json"

    /// Frames newest-first.
    private(set) var frames: [CameraFrame] = []

    /// Selected frame id, or `nil` for None.
    private(set) var selectedId: UUID? {
        didSet {
            if let selectedId {
                UserDefaults.standard.set(selectedId.uuidString, forKey: Self.selectedIdKey)
            } else {
                UserDefaults.standard.removeObject(forKey: Self.selectedIdKey)
            }
        }
    }

    /// Image for the current selection (nil when None).
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
        if let raw = UserDefaults.standard.string(forKey: Self.selectedIdKey),
           let id = UUID(uuidString: raw),
           frames.contains(where: { $0.id == id }) {
            selectedId = id
        } else {
            selectedId = nil
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

    // MARK: - Mutations

    /// Adds a PNG frame. Returns the new id, or nil if the library is full / encode fails.
    @discardableResult
    func add(_ image: UIImage) -> UUID? {
        guard frames.count < Self.maxFrameCount else {
            logger.error("Camera frame library full (\(Self.maxFrameCount))")
            return nil
        }
        let oriented = MediaAspect.normalized(image)
        guard let data = oriented.pngData() else {
            logger.error("Failed to encode camera frame PNG")
            return nil
        }
        let id = UUID()
        let url = fileURL(for: id)
        do {
            try data.write(to: url, options: .atomic)
            let frame = CameraFrame(id: id, createdAt: Date())
            frames.insert(frame, at: 0)
            saveIndex()
            NotificationCenter.default.post(name: Self.didChangeNotification, object: self)
            return id
        } catch {
            logger.error("Failed to write frame: \(error.localizedDescription)")
            return nil
        }
    }

    /// Removes a frame. Clears selection if it was selected.
    func remove(_ id: UUID) {
        frames.removeAll { $0.id == id }
        try? FileManager.default.removeItem(at: fileURL(for: id))
        if selectedId == id {
            selectedId = nil
        }
        saveIndex()
        NotificationCenter.default.post(name: Self.didChangeNotification, object: self)
    }

    /// Selects a frame, or `nil` for None.
    func select(_ id: UUID?) {
        if let id, !frames.contains(where: { $0.id == id }) {
            selectedId = nil
        } else {
            selectedId = id
        }
        NotificationCenter.default.post(name: Self.didChangeNotification, object: self)
    }

    // MARK: - Persistence

    private func loadIndex() {
        guard let data = try? Data(contentsOf: indexURL),
              let decoded = try? JSONDecoder().decode([CameraFrame].self, from: data)
        else {
            frames = []
            return
        }
        // Drop index entries whose files are missing.
        frames = decoded.filter {
            FileManager.default.fileExists(atPath: fileURL(for: $0.id).path)
        }
        if frames.count != decoded.count {
            saveIndex()
        }
    }

    private func saveIndex() {
        do {
            let data = try JSONEncoder().encode(frames)
            try data.write(to: indexURL, options: .atomic)
        } catch {
            logger.error("Failed to save frame index: \(error.localizedDescription)")
        }
    }
}
