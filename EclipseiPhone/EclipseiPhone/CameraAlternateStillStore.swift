//
//  CameraAlternateStillStore.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import UIKit
import os.log

/// Persists an optional camera-mode cutaway still the user can toggle on while
/// Camera is open. Program (AirPlay / live preview) shows the still; the phone
/// camera viewfinder stays on the live camera.
///
/// When the user has not picked a photo, display and AirPlay fall back to the Show
/// Background still (`LogoStore`). Frame overlays stay in `CameraFrameStore`.
@MainActor
final class CameraAlternateStillStore {

    static let shared = CameraAlternateStillStore()

    /// Posted when the cutaway still is set or cleared.
    static let didChangeNotification =
        Notification.Name("CameraAlternateStillStore.didChange")

    /// In-memory image when a custom cutaway is saved; nil falls back to Background.
    private(set) var image: UIImage?

    /// Whether the user has replaced the Background default with a custom photo.
    var hasStill: Bool { image != nil }

    /// Thumbnail to show: custom cutaway, or the Show Background card.
    var displayImage: UIImage? {
        image ?? LogoStore.shared.image
    }

    /// AirPlay source: custom cutaway, or the Show Background still.
    var presentationSource: PresentationSource? {
        if let url = fileURL {
            return .image(url, fill: true)
        }
        return LogoStore.shared.presentationSource
    }

    /// On-disk JPEG used by AirPlay, or nil when empty.
    var fileURL: URL? {
        guard FileManager.default.fileExists(atPath: stillFileURL.path) else {
            return nil
        }
        return stillFileURL
    }

    private let stillFileURL: URL
    private let logger = Logger(
        subsystem: "com.eclipseapp.ios",
        category: "CameraAlternateStill"
    )

    private init() {
        let base = FileManager.default.urls(
            for: .applicationSupportDirectory, in: .userDomainMask
        )[0]
        let dir = base.appendingPathComponent("CameraAlternateStill", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        stillFileURL = dir.appendingPathComponent("still.jpg")
        image = UIImage(contentsOfFile: stillFileURL.path)
    }

    // MARK: - Mutations

    /// Saves `image` as JPEG and posts `didChangeNotification`.
    func save(_ image: UIImage) {
        let normalized = MediaAspect.normalized(image)
        guard let data = normalized.jpegData(compressionQuality: 0.92) else {
            logger.error("Failed to encode cutaway JPEG")
            return
        }
        do {
            try data.write(to: stillFileURL, options: .atomic)
            self.image = normalized
            NotificationCenter.default.post(name: Self.didChangeNotification, object: self)
        } catch {
            logger.error("Failed to write cutaway: \(error.localizedDescription)")
        }
    }

    /// Removes the custom cutaway (the thumb falls back to Background).
    func clear() {
        try? FileManager.default.removeItem(at: stillFileURL)
        image = nil
        NotificationCenter.default.post(name: Self.didChangeNotification, object: self)
    }
}
