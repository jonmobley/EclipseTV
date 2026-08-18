//
//  CameraAlternateStillStore.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import UIKit
import os.log

/// Persists the camera-mode cutaway still the user can toggle onto AirPlay.
///
/// Empty until the user picks a photo. Independent of Background (`LogoStore`) and
/// of PNG frame overlays (`CameraFrameStore`).
@MainActor
final class CameraAlternateStillStore {

    static let shared = CameraAlternateStillStore()

    /// Posted when the cutaway still is set or cleared.
    static let didChangeNotification =
        Notification.Name("CameraAlternateStillStore.didChange")

    /// In-memory image when a cutaway is saved; nil when none is chosen.
    private(set) var image: UIImage?

    /// Whether the user has chosen a cutaway still.
    var hasStill: Bool { image != nil }

    /// AirPlay source for the cutaway (aspect-fill), or nil when empty.
    var presentationSource: PresentationSource? {
        guard let url = fileURL else { return nil }
        return .image(url, fill: true)
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

    /// Removes the cutaway still.
    func clear() {
        try? FileManager.default.removeItem(at: stillFileURL)
        image = nil
        NotificationCenter.default.post(name: Self.didChangeNotification, object: self)
    }
}
