//
//  LogoStore.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import UIKit
import os.log

/// Persists the Show-tools Background still under Application Support.
///
/// Default is the bundled eclipse Background art. A user-picked image replaces
/// it until cleared. Looping video belongs to Screensaver, not here.
@MainActor
final class LogoStore {

    static let shared = LogoStore()

    /// Posted when the logo image is set or cleared.
    static let didChangeNotification = Notification.Name("LogoStore.didChange")

    /// Custom image if the user picked one; otherwise the bundled Background art.
    var image: UIImage? {
        customImage ?? Self.bundledDefault
    }

    /// Whether the user has replaced the bundled default with a custom image.
    var hasCustomImage: Bool { customImage != nil }

    /// AirPlay source for Background (always a still, aspect-fill).
    var presentationSource: PresentationSource? {
        guard let url = fileURL else { return nil }
        return .image(url, fill: true)
    }

    /// On-disk file for AirPlay: custom JPEG, or a cached copy of the bundled still.
    var fileURL: URL? {
        if FileManager.default.fileExists(atPath: logoFileURL.path) {
            return logoFileURL
        }
        return ensureDefaultFileURL()
    }

    /// Whether `url` is the custom or bundled Background still used for AirPlay.
    func isLogoFileURL(_ url: URL) -> Bool {
        let path = url.standardizedFileURL.path
        return path == logoFileURL.path || path == defaultFileURL.path
    }

    private var customImage: UIImage?
    private let logoFileURL: URL
    private let defaultFileURL: URL
    private let logger = Logger(subsystem: "com.eclipseapp.ios", category: "LogoStore")

    private static var bundledDefault: UIImage? {
        UIImage(named: "EclipseBackground")
    }

    private init() {
        let base = FileManager.default.urls(
            for: .applicationSupportDirectory, in: .userDomainMask
        )[0]
        let dir = base.appendingPathComponent("Logo", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        logoFileURL = dir.appendingPathComponent("logo.jpg")
        // Versioned so prior poster caches are not reused after art updates.
        defaultFileURL = dir.appendingPathComponent("default-eclipse-background-v2.png")
        customImage = UIImage(contentsOfFile: logoFileURL.path)
        Self.removeLegacyDefaultsIfNeeded(in: dir)
    }

    /// Drops superseded on-disk poster caches.
    private static func removeLegacyDefaultsIfNeeded(in dir: URL) {
        for name in ["default.png", "default-eclipse-background.png"] {
            try? FileManager.default.removeItem(at: dir.appendingPathComponent(name))
        }
    }

    // MARK: - Mutations

    /// Saves `image` as JPEG and posts `didChangeNotification`.
    func save(_ image: UIImage) {
        let normalized = MediaAspect.normalized(image)
        guard let data = normalized.jpegData(compressionQuality: 0.92) else {
            logger.error("Failed to encode logo JPEG")
            return
        }
        do {
            try data.write(to: logoFileURL, options: .atomic)
            customImage = normalized
            NotificationCenter.default.post(name: Self.didChangeNotification, object: self)
        } catch {
            logger.error("Failed to write logo: \(error.localizedDescription)")
        }
    }

    /// Removes the custom image (falls back to the bundled Background art).
    func clear() {
        try? FileManager.default.removeItem(at: logoFileURL)
        customImage = nil
        NotificationCenter.default.post(name: Self.didChangeNotification, object: self)
    }

    /// Writes the bundled still to disk once so AirPlay can load a file URL.
    private func ensureDefaultFileURL() -> URL? {
        if FileManager.default.fileExists(atPath: defaultFileURL.path) {
            return defaultFileURL
        }
        guard let image = Self.bundledDefault,
              let data = image.pngData() else { return nil }
        do {
            try data.write(to: defaultFileURL, options: .atomic)
            return defaultFileURL
        } catch {
            logger.error("Failed to write default logo: \(error.localizedDescription)")
            return nil
        }
    }
}
