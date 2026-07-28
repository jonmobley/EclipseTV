//
//  WebThumbnailStore.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import UIKit
import os.log

/// Disk-backed website previews (page snapshots + optional favicons).
@MainActor
final class WebThumbnailStore {

    static let shared = WebThumbnailStore()

    /// Posted when a snapshot or favicon is saved or removed.
    static let didChangeNotification = Notification.Name("WebThumbnailStore.didChange")

    private let rootDirectory: URL
    private let ioQueue = DispatchQueue(label: "com.eclipseapp.ios.WebThumbnailStore", qos: .utility)
    private let logger = Logger(subsystem: "com.eclipseapp.ios", category: "WebThumbnail")
    private var memory: [UUID: UIImage] = [:]
    private var favicons: [UUID: UIImage] = [:]

    private init() {
        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        rootDirectory = base.appendingPathComponent("WebThumbnails", isDirectory: true)
        try? FileManager.default.createDirectory(at: rootDirectory, withIntermediateDirectories: true)
    }

    // MARK: - Reads

    /// Best available preview: snapshot, else favicon.
    func image(for id: UUID) -> UIImage? {
        if let snapshot = snapshot(for: id) { return snapshot }
        return favicon(for: id)
    }

    /// Full-page snapshot if one has been captured.
    func snapshot(for id: UUID) -> UIImage? {
        if let cached = memory[id] { return cached }
        let url = snapshotURL(for: id)
        guard let image = UIImage(contentsOfFile: url.path) else { return nil }
        memory[id] = image
        return image
    }

    /// Site icon used until a snapshot exists.
    func favicon(for id: UUID) -> UIImage? {
        if let cached = favicons[id] { return cached }
        let url = faviconURL(for: id)
        guard let image = UIImage(contentsOfFile: url.path) else { return nil }
        favicons[id] = image
        return image
    }

    // MARK: - Writes

    /// Persists a page snapshot and notifies the UI.
    func saveSnapshot(_ image: UIImage, for id: UUID) {
        memory[id] = image
        let url = snapshotURL(for: id)
        ioQueue.async { [weak self] in
            guard let data = image.jpegData(compressionQuality: 0.82) else { return }
            do {
                try data.write(to: url, options: .atomic)
            } catch {
                self?.logger.error("Snapshot save failed: \(error.localizedDescription)")
            }
            Task { @MainActor in
                NotificationCenter.default.post(name: Self.didChangeNotification, object: self)
            }
        }
    }

    /// Persists a favicon and notifies the UI when no snapshot is present yet.
    func saveFavicon(_ image: UIImage, for id: UUID) {
        favicons[id] = image
        let url = faviconURL(for: id)
        ioQueue.async { [weak self] in
            guard let data = image.pngData() else { return }
            try? data.write(to: url, options: .atomic)
            Task { @MainActor in
                // Only nudge the grid if we still lack a real snapshot.
                if self?.memory[id] == nil {
                    NotificationCenter.default.post(name: Self.didChangeNotification, object: self)
                }
            }
        }
    }

    /// Drops snapshot + favicon for a deleted bookmark.
    func remove(id: UUID) {
        memory[id] = nil
        favicons[id] = nil
        let snap = snapshotURL(for: id)
        let icon = faviconURL(for: id)
        ioQueue.async {
            try? FileManager.default.removeItem(at: snap)
            try? FileManager.default.removeItem(at: icon)
        }
        NotificationCenter.default.post(name: Self.didChangeNotification, object: self)
    }

    // MARK: - Paths

    private func snapshotURL(for id: UUID) -> URL {
        rootDirectory.appendingPathComponent("\(id.uuidString).jpg")
    }

    private func faviconURL(for id: UUID) -> URL {
        rootDirectory.appendingPathComponent("\(id.uuidString)-favicon.png")
    }
}
