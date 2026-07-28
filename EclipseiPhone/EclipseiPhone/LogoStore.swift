//
//  LogoStore.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import UIKit
import os.log

/// Persists the home-grid Logo image under Application Support.
@MainActor
final class LogoStore {

    static let shared = LogoStore()

    /// Posted when the logo image is set or cleared.
    static let didChangeNotification = Notification.Name("LogoStore.didChange")

    /// Custom logo if the user picked one; otherwise the bundled Eclipse app icon.
    var image: UIImage? {
        customImage ?? Self.bundledDefault
    }

    /// Whether the user has replaced the bundled default with a custom image.
    var hasCustomImage: Bool { customImage != nil }

    /// On-disk file for AirPlay: custom JPEG, or a cached copy of the bundled default.
    var fileURL: URL? {
        if FileManager.default.fileExists(atPath: logoFileURL.path) {
            return logoFileURL
        }
        return ensureDefaultFileURL()
    }

    /// Whether `url` is the custom or bundled logo file used for AirPlay.
    func isLogoFileURL(_ url: URL) -> Bool {
        let path = url.standardizedFileURL.path
        return path == logoFileURL.path || path == defaultFileURL.path
    }

    private var customImage: UIImage?
    private let logoFileURL: URL
    private let defaultFileURL: URL
    private let logger = Logger(subsystem: "com.eclipseapp.ios", category: "LogoStore")

    private static var bundledDefault: UIImage? {
        UIImage(named: "EclipseLogo")
    }

    private init() {
        let base = FileManager.default.urls(
            for: .applicationSupportDirectory, in: .userDomainMask
        )[0]
        let dir = base.appendingPathComponent("Logo", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        logoFileURL = dir.appendingPathComponent("logo.jpg")
        defaultFileURL = dir.appendingPathComponent("default.png")
        customImage = UIImage(contentsOfFile: logoFileURL.path)
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

    /// Removes the custom logo (falls back to the bundled app icon).
    func clear() {
        try? FileManager.default.removeItem(at: logoFileURL)
        customImage = nil
        NotificationCenter.default.post(name: Self.didChangeNotification, object: self)
    }

    /// Writes the bundled default to disk once so AirPlay can load a file URL.
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
