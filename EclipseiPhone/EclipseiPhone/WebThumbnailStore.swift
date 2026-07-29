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

    /// Bounded in-memory caches. Plain dictionaries here grew for the life of the process,
    /// holding a full-resolution `WKWebView` snapshot per bookmark with no eviction. Both
    /// reads fall back to disk, so eviction only costs a reload.
    private let memory = NSCache<NSUUID, UIImage>()
    private let favicons = NSCache<NSUUID, UIImage>()

    private init() {
        memory.totalCostLimit = 24 * 1024 * 1024
        favicons.totalCostLimit = 4 * 1024 * 1024

        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        rootDirectory = base.appendingPathComponent("WebThumbnails", isDirectory: true)
        try? FileManager.default.createDirectory(at: rootDirectory, withIntermediateDirectories: true)
    }

    /// Approximate decoded byte size, used as the `NSCache` cost.
    private static func cost(of image: UIImage) -> Int {
        if let cgImage = image.cgImage {
            return cgImage.bytesPerRow * cgImage.height
        }
        let pixels = image.size.width * image.scale * image.size.height * image.scale
        return Int(pixels * 4)
    }

    // MARK: - Reads

    /// Best available preview: snapshot, else favicon.
    func image(for id: UUID) -> UIImage? {
        if let snapshot = snapshot(for: id) { return snapshot }
        return favicon(for: id)
    }

    /// Full-page snapshot if one has been captured.
    func snapshot(for id: UUID) -> UIImage? {
        if let cached = memory.object(forKey: id as NSUUID) { return cached }
        let url = snapshotURL(for: id)
        guard let image = UIImage(contentsOfFile: url.path) else { return nil }
        memory.setObject(image, forKey: id as NSUUID, cost: Self.cost(of: image))
        return image
    }

    /// Site icon used until a snapshot exists.
    func favicon(for id: UUID) -> UIImage? {
        if let cached = favicons.object(forKey: id as NSUUID) { return cached }
        let url = faviconURL(for: id)
        guard let image = UIImage(contentsOfFile: url.path) else { return nil }
        favicons.setObject(image, forKey: id as NSUUID, cost: Self.cost(of: image))
        return image
    }

    // MARK: - Writes

    /// Persists a page snapshot and notifies the UI.
    func saveSnapshot(_ image: UIImage, for id: UUID) {
        memory.setObject(image, forKey: id as NSUUID, cost: Self.cost(of: image))
        let url = snapshotURL(for: id)
        ioQueue.async { [weak self] in
            // WKWebView snapshots are AlphaPremulLast even when fully opaque;
            // flattening avoids ImageIO's "ignoring alpha" save warning + decode cost.
            guard let data = Self.opaqueJPEGData(from: image, quality: 0.82) else { return }
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

    /// JPEG-encodes after compositing onto an opaque black bitmap.
    private nonisolated static func opaqueJPEGData(
        from image: UIImage, quality: CGFloat
    ) -> Data? {
        let size = image.size
        guard size.width > 1, size.height > 1 else {
            return image.jpegData(compressionQuality: quality)
        }
        let format = UIGraphicsImageRendererFormat.default()
        format.opaque = true
        format.scale = image.scale
        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        let opaque = renderer.image { context in
            UIColor.black.setFill()
            context.fill(CGRect(origin: .zero, size: size))
            image.draw(in: CGRect(origin: .zero, size: size))
        }
        return opaque.jpegData(compressionQuality: quality)
    }

    /// Persists a favicon and notifies the UI when no snapshot is present yet.
    func saveFavicon(_ image: UIImage, for id: UUID) {
        favicons.setObject(image, forKey: id as NSUUID, cost: Self.cost(of: image))
        let url = faviconURL(for: id)
        ioQueue.async { [weak self] in
            guard let data = image.pngData() else { return }
            try? data.write(to: url, options: .atomic)
            Task { @MainActor in
                // Only nudge the grid if we still lack a real snapshot.
                if self?.snapshot(for: id) == nil {
                    NotificationCenter.default.post(name: Self.didChangeNotification, object: self)
                }
            }
        }
    }

    /// Drops snapshot + favicon for a deleted bookmark.
    func remove(id: UUID) {
        memory.removeObject(forKey: id as NSUUID)
        favicons.removeObject(forKey: id as NSUUID)
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
