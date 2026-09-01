//
//  CameraAlternateStillStore.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import UIKit
import os.log

/// One user-picked camera quick-change still.
struct CameraCutawayStill: Equatable, Identifiable, Codable {
    let id: UUID
    let createdAt: Date
}

/// Persists camera-mode cutaway stills the user can toggle on while Camera is
/// open. Program (AirPlay / live preview) shows the still; the phone viewfinder
/// stays on the live camera.
///
/// Background is not stored here — it is always the first ribbon item from
/// `LogoStore`. Frame overlays stay in `CameraFrameStore`.
@MainActor
final class CameraAlternateStillStore {

    static let shared = CameraAlternateStillStore()

    /// Posted when a cutaway is added, replaced, or removed.
    static let didChangeNotification =
        Notification.Name("CameraAlternateStillStore.didChange")

    /// Soft cap so the in-camera ribbon stays tappable.
    static let maxStillCount = 8

    /// Saved quick-change stills, oldest first. `+` appends another.
    private(set) var stills: [CameraCutawayStill] = []

    /// In-memory JPEGs keyed by still id.
    private var images: [UUID: UIImage] = [:]

    /// Whether another still can be added from the ribbon + cell.
    var canAddStill: Bool { stills.count < Self.maxStillCount }

    /// Ids in ribbon order.
    var cutawayIds: [UUID] { stills.map(\.id) }

    private let directory: URL
    private let indexURL: URL
    private let legacyFileURL: URL
    private let logger = Logger(
        subsystem: "com.eclipseapp.ios",
        category: "CameraAlternateStill"
    )

    private init() {
        let base = FileManager.default.urls(
            for: .applicationSupportDirectory, in: .userDomainMask
        )[0]
        directory = base.appendingPathComponent(
            "CameraAlternateStill", isDirectory: true
        )
        try? FileManager.default.createDirectory(
            at: directory, withIntermediateDirectories: true
        )
        indexURL = directory.appendingPathComponent("index.json")
        legacyFileURL = directory.appendingPathComponent("still.jpg")
        load()
    }

    // MARK: - Lookup

    /// Thumbnail / program art for a saved cutaway.
    func image(for id: UUID) -> UIImage? {
        if let image = images[id] { return image }
        return UIImage(contentsOfFile: fileURL(for: id).path)
    }

    /// On-disk JPEG used by AirPlay, or nil when missing.
    func fileURL(for id: UUID) -> URL {
        directory.appendingPathComponent("\(id.uuidString).jpg")
    }

    /// AirPlay source for a saved cutaway.
    func presentationSource(for id: UUID) -> PresentationSource? {
        let url = fileURL(for: id)
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        return .image(url, fill: true)
    }

    /// Whether `id` is a saved cutaway.
    func contains(_ id: UUID) -> Bool {
        stills.contains { $0.id == id }
    }

    // MARK: - Mutations

    /// Writes `image` as JPEG. Pass `replacing` to overwrite an existing still.
    @discardableResult
    func save(_ image: UIImage, replacing id: UUID? = nil) -> UUID? {
        let stillId = id ?? UUID()
        if id == nil {
            guard canAddStill else { return nil }
        } else if !contains(stillId) {
            return nil
        }
        let normalized = MediaAspect.normalized(image)
        guard let data = normalized.jpegData(compressionQuality: 0.92) else {
            logger.error("Failed to encode cutaway JPEG")
            return nil
        }
        do {
            try data.write(to: fileURL(for: stillId), options: .atomic)
            images[stillId] = normalized
            if !contains(stillId) {
                stills.append(CameraCutawayStill(id: stillId, createdAt: Date()))
            }
            saveIndex()
            NotificationCenter.default.post(
                name: Self.didChangeNotification, object: self
            )
            guard !EclipseSyncController.shared.isApplyingRemote else { return stillId }
            markNeedsUpload(id: stillId)
            EclipseSyncController.shared.backend.scheduleCutawaySave(id: stillId)
            return stillId
        } catch {
            logger.error("Failed to write cutaway: \(error.localizedDescription)")
            return nil
        }
    }

    /// Deletes a cutaway. Remaining stills keep their order.
    func remove(_ id: UUID) {
        guard contains(id) else { return }
        try? FileManager.default.removeItem(at: fileURL(for: id))
        images[id] = nil
        stills.removeAll { $0.id == id }
        saveIndex()
        NotificationCenter.default.post(
            name: Self.didChangeNotification, object: self
        )
        guard !EclipseSyncController.shared.isApplyingRemote else { return }
        markNeedsUpload(id: id)
        EclipseSyncController.shared.backend.scheduleCutawayDelete(id: id)
    }

    /// Inserts or replaces a cutaway that arrived from iCloud.
    func applyRemote(id: UUID, createdAt: Date, assetURL: URL) {
        let destination = fileURL(for: id)
        do {
            if FileManager.default.fileExists(atPath: destination.path) {
                try FileManager.default.removeItem(at: destination)
            }
            try FileManager.default.copyItem(at: assetURL, to: destination)
        } catch {
            logger.error("Remote cutaway copy failed: \(error.localizedDescription)")
            return
        }
        images[id] = UIImage(contentsOfFile: destination.path)
        if let index = stills.firstIndex(where: { $0.id == id }) {
            stills[index] = CameraCutawayStill(id: id, createdAt: createdAt)
        } else if stills.count < Self.maxStillCount {
            stills.append(CameraCutawayStill(id: id, createdAt: createdAt))
            stills.sort { $0.createdAt < $1.createdAt }
        } else {
            return
        }
        saveIndex()
        markSynced(id: id)
        NotificationCenter.default.post(
            name: Self.didChangeNotification, object: self
        )
    }

    // MARK: - Persistence

    private func load() {
        loadIndex()
        migrateLegacyStillIfNeeded()
        for still in stills {
            images[still.id] = UIImage(contentsOfFile: fileURL(for: still.id).path)
        }
    }

    private func loadIndex() {
        guard let data = try? Data(contentsOf: indexURL),
              let decoded = try? JSONDecoder().decode(
                [CameraCutawayStill].self, from: data
              )
        else {
            stills = []
            return
        }
        stills = decoded.filter {
            FileManager.default.fileExists(atPath: fileURL(for: $0.id).path)
        }
        if stills.count != decoded.count {
            saveIndex()
        }
    }

    private func saveIndex() {
        do {
            let data = try JSONEncoder().encode(stills)
            try data.write(to: indexURL, options: .atomic)
        } catch {
            logger.error("Failed to save cutaway index: \(error.localizedDescription)")
        }
    }

    /// Pre-ribbon single `still.jpg` becomes a quick-change still.
    private func migrateLegacyStillIfNeeded() {
        guard stills.isEmpty,
              FileManager.default.fileExists(atPath: legacyFileURL.path)
        else { return }
        let id = UUID()
        let dest = fileURL(for: id)
        do {
            try FileManager.default.copyItem(at: legacyFileURL, to: dest)
            stills = [CameraCutawayStill(id: id, createdAt: Date())]
            saveIndex()
            try? FileManager.default.removeItem(at: legacyFileURL)
        } catch {
            logger.error("Failed to migrate cutaway: \(error.localizedDescription)")
        }
    }
}
