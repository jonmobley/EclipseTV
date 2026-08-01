//
//  ScreensaverStore.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import AVFoundation
import os.log
import UIKit

/// Bundled looping Screensaver, optionally replaced by a user image or video.
@MainActor
final class ScreensaverStore {

    static let shared = ScreensaverStore()

    /// Posted when custom Screensaver media is set or cleared.
    static let didChangeNotification = Notification.Name("ScreensaverStore.didChange")

    /// True when the user has replaced the bundled loop.
    var hasCustomMedia: Bool { customKind != nil }

    /// Tile / fallback poster while video loads (or the custom still).
    var poster: UIImage? {
        if let customImage { return customImage }
        if let posterImage { return posterImage }
        return UIImage(named: "HomeHeroEclipse")
    }

    /// Looping video URL when the active Screensaver is video (bundled or custom).
    var videoURL: URL? {
        switch customKind {
        case .image: return nil
        case .video: return existingCustomVideoURL()
        case .none: return Self.bundledVideoURL
        }
    }

    /// AirPlay / preview source for the active Screensaver.
    var presentationSource: PresentationSource? {
        switch customKind {
        case .image:
            guard FileManager.default.fileExists(atPath: imageFileURL.path) else {
                return nil
            }
            return .image(imageFileURL, fill: true)
        case .video, .none:
            guard let url = videoURL else { return nil }
            return .screensaver(url)
        }
    }

    // MARK: - Static facades (call-site compatibility)

    static var videoURL: URL? { shared.videoURL }
    static var poster: UIImage? { shared.poster }
    static var presentationSource: PresentationSource? { shared.presentationSource }
    static var hasCustomMedia: Bool { shared.hasCustomMedia }

    // MARK: - Private

    private enum CustomKind: String {
        case image
        case video
    }

    private var customKind: CustomKind?
    private var customImage: UIImage?
    private var posterImage: UIImage?
    private let directory: URL
    private let imageFileURL: URL
    private let posterFileURL: URL
    private let kindKey = "EclipseTV.screensaver.customKind"
    private let logger = Logger(
        subsystem: "com.eclipseapp.ios", category: "ScreensaverStore"
    )

    private static var bundledVideoURL: URL? {
        Bundle.main.url(forResource: "EclipseScreensaver", withExtension: "mp4")
    }

    private init() {
        let base = FileManager.default.urls(
            for: .applicationSupportDirectory, in: .userDomainMask
        )[0]
        directory = base.appendingPathComponent("Screensaver", isDirectory: true)
        try? FileManager.default.createDirectory(
            at: directory, withIntermediateDirectories: true
        )
        imageFileURL = directory.appendingPathComponent("custom.jpg")
        posterFileURL = directory.appendingPathComponent("poster.jpg")
        if let raw = UserDefaults.standard.string(forKey: kindKey),
           let kind = CustomKind(rawValue: raw) {
            customKind = kind
        }
        reloadFromDisk()
    }

    // MARK: - Mutations

    /// Replaces the Screensaver with a still (aspect-fill on AirPlay).
    func saveImage(_ image: UIImage) {
        let normalized = MediaAspect.normalized(image)
        guard let data = normalized.jpegData(compressionQuality: 0.92) else {
            logger.error("Failed to encode screensaver JPEG")
            return
        }
        do {
            try data.write(to: imageFileURL, options: .atomic)
            removeCustomVideos()
            try? FileManager.default.removeItem(at: posterFileURL)
            customKind = .image
            customImage = normalized
            posterImage = nil
            UserDefaults.standard.set(CustomKind.image.rawValue, forKey: kindKey)
            NotificationCenter.default.post(name: Self.didChangeNotification, object: self)
        } catch {
            logger.error("Failed to write screensaver image: \(error.localizedDescription)")
        }
    }

    /// Replaces the Screensaver with a muted looping video copied from `sourceURL`.
    func saveVideo(from sourceURL: URL) {
        let ext = sourceURL.pathExtension.isEmpty ? "mp4" : sourceURL.pathExtension
        let destination = directory.appendingPathComponent("custom.\(ext)")
        do {
            removeCustomVideos()
            try FileManager.default.copyItem(at: sourceURL, to: destination)
            try? FileManager.default.removeItem(at: imageFileURL)
            customKind = .video
            customImage = nil
            UserDefaults.standard.set(CustomKind.video.rawValue, forKey: kindKey)
            if let poster = Self.makePoster(for: destination),
               let data = poster.jpegData(compressionQuality: 0.85) {
                try? data.write(to: posterFileURL, options: .atomic)
                posterImage = poster
            } else {
                posterImage = nil
            }
            NotificationCenter.default.post(name: Self.didChangeNotification, object: self)
        } catch {
            logger.error("Failed to save screensaver video: \(error.localizedDescription)")
        }
    }

    /// Restores the bundled Eclipse Screensaver loop.
    func clear() {
        try? FileManager.default.removeItem(at: imageFileURL)
        removeCustomVideos()
        try? FileManager.default.removeItem(at: posterFileURL)
        customKind = nil
        customImage = nil
        posterImage = nil
        UserDefaults.standard.removeObject(forKey: kindKey)
        NotificationCenter.default.post(name: Self.didChangeNotification, object: self)
    }

    // MARK: - Private

    private func existingCustomVideoURL() -> URL? {
        let names = ["custom.mp4", "custom.mov", "custom.m4v"]
        for name in names {
            let url = directory.appendingPathComponent(name)
            if FileManager.default.fileExists(atPath: url.path) { return url }
        }
        return nil
    }

    private func removeCustomVideos() {
        for name in ["custom.mp4", "custom.mov", "custom.m4v"] {
            try? FileManager.default.removeItem(
                at: directory.appendingPathComponent(name)
            )
        }
    }

    private func reloadFromDisk() {
        switch customKind {
        case .image:
            customImage = UIImage(contentsOfFile: imageFileURL.path)
            if customImage == nil { customKind = nil }
        case .video:
            if existingCustomVideoURL() == nil {
                customKind = nil
            } else {
                posterImage = UIImage(contentsOfFile: posterFileURL.path)
            }
        case .none:
            break
        }
    }

    /// Poster still via async generator API (avoids deprecated `copyCGImage`).
    ///
    /// `nonisolated` so a semaphore wait cannot deadlock the main actor.
    nonisolated private static func makePoster(for url: URL) -> UIImage? {
        let asset = AVURLAsset(url: url)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 720, height: 720)
        let time = CMTime(seconds: 0.4, preferredTimescale: 600)
        let semaphore = DispatchSemaphore(value: 0)
        var image: UIImage?
        Task {
            defer { semaphore.signal() }
            do {
                let cg = try await generator.image(at: time).image
                image = UIImage(cgImage: cg)
            } catch {
                image = nil
            }
        }
        _ = semaphore.wait(timeout: .now() + 5)
        return image
    }
}
