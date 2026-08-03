//
//  AudioStore.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import AVFoundation
import Foundation
import os.log
import UIKit
import UniformTypeIdentifiers

/// Persists imported audio files under Application Support.
@MainActor
final class AudioStore {

    static let shared = AudioStore()

    /// Posted when the track list changes.
    static let didChangeNotification = Notification.Name("AudioStore.didChange")

    /// Soft import cap (similar spirit to video limits).
    static let maxFileBytes: Int64 = 200_000_000

    enum StoreError: LocalizedError {
        case copyFailed
        case invalidFile
        case fileTooLarge
        case emptyTitle

        var errorDescription: String? {
            switch self {
            case .copyFailed: return "Couldn't save that audio file. Please try again."
            case .invalidFile: return "That doesn't look like a supported audio file."
            case .fileTooLarge: return "That file is too large. Maximum size is 200 MB."
            case .emptyTitle: return "Enter a name for the track."
            }
        }
    }

    private(set) var tracks: [AudioTrack] = []

    private let defaults: UserDefaults
    private let itemsKey = "EclipseTV.audio.items"
    private let rootDirectory: URL
    private let logger = Logger(subsystem: "com.eclipseapp.ios", category: "AudioStore")

    /// Allowed document-picker types for import.
    static let importTypes: [UTType] = {
        var types: [UTType] = [.mp3, .mpeg4Audio, .wav, .aiff]
        if let aac = UTType("public.aac-audio") { types.append(aac) }
        return types
    }()

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let base = FileManager.default.urls(
            for: .applicationSupportDirectory, in: .userDomainMask
        )[0]
        rootDirectory = base.appendingPathComponent("Audio", isDirectory: true)
        try? FileManager.default.createDirectory(
            at: rootDirectory, withIntermediateDirectories: true
        )
        excludeFromBackup(rootDirectory)
        load()
    }

    // MARK: - Reads

    /// On-disk URL for a track, or `nil` if the file is missing.
    func fileURL(for id: UUID) -> URL? {
        guard let track = tracks.first(where: { $0.id == id }) else { return nil }
        let url = rootDirectory.appendingPathComponent(
            "\(id.uuidString).\(track.fileExtension)"
        )
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    /// Track with `id`, if any.
    func track(id: UUID) -> AudioTrack? {
        tracks.first { $0.id == id }
    }

    // MARK: - Mutations

    /// Copies `sourceURL` into the store and returns the new track.
    @discardableResult
    func add(from sourceURL: URL, title: String?) async throws -> AudioTrack {
        let ext = normalizedExtension(sourceURL)
        guard Self.allowedExtensions.contains(ext) else {
            throw StoreError.invalidFile
        }

        if let size = fileSize(at: sourceURL), size > Self.maxFileBytes {
            throw StoreError.fileTooLarge
        }

        let trimmed = title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let fallbackTitle = sourceURL.deletingPathExtension().lastPathComponent
        let resolvedTitle = UserDisplayName.clamp(
            trimmed.isEmpty ? fallbackTitle : trimmed
        )
        guard !resolvedTitle.isEmpty else { throw StoreError.invalidFile }

        let id = UUID()
        let destination = rootDirectory.appendingPathComponent(
            "\(id.uuidString).\(ext)"
        )
        do {
            if FileManager.default.fileExists(atPath: destination.path) {
                try FileManager.default.removeItem(at: destination)
            }
            try FileManager.default.copyItem(at: sourceURL, to: destination)
        } catch {
            logger.error("Audio copy failed: \(error.localizedDescription)")
            throw StoreError.copyFailed
        }

        let meta = await Self.readMetadata(at: destination)
        let item = AudioTrack(
            id: id,
            title: UserDisplayName.clamp(meta.title ?? resolvedTitle),
            artist: meta.artist,
            duration: meta.duration,
            fileExtension: ext
        )
        tracks.insert(item, at: 0)
        persist()
        return item
    }

    /// Replaces the library track order (Music list arrange).
    func reorder(trackIds: [UUID]) {
        let byId = Dictionary(uniqueKeysWithValues: tracks.map { ($0.id, $0) })
        var next = trackIds.compactMap { byId[$0] }
        let placed = Set(next.map(\.id))
        for track in tracks where !placed.contains(track.id) {
            next.append(track)
        }
        guard next.map(\.id) != tracks.map(\.id) else { return }
        tracks = next
        persist()
    }

    /// Renames the track with `id` when present. Protected tracks are ignored.
    func rename(id: UUID, to title: String) throws {
        guard let trimmed = UserDisplayName.normalized(title) else {
            throw StoreError.emptyTitle
        }
        guard let index = tracks.firstIndex(where: { $0.id == id }) else { return }
        guard !tracks[index].isProtected else { return }
        tracks[index].title = trimmed
        persist()
    }

    /// Removes the track and deletes its file; prunes playlists.
    /// Protected (bundled) tracks are never removed.
    func remove(id: UUID) {
        guard let existing = tracks.first(where: { $0.id == id }),
              !existing.isProtected else { return }
        let before = tracks.count
        tracks.removeAll { $0.id == id }
        guard tracks.count != before else { return }
        let prefix = id.uuidString
        if let contents = try? FileManager.default.contentsOfDirectory(
            at: rootDirectory, includingPropertiesForKeys: nil
        ) {
            for url in contents where url.lastPathComponent.hasPrefix(prefix) {
                try? FileManager.default.removeItem(at: url)
            }
        }
        AudioPlaylistStore.shared.removeTrackFromAllPlaylists(trackId: id)
        persist()
        NotificationCenter.default.post(
            name: AudioPlayerController.trackRemovedNotification,
            object: nil,
            userInfo: ["id": id]
        )
    }

    /// Copies a bundled audio resource into the store under a fixed id when missing.
    func ensureBundledTrack(
        id: UUID,
        title: String,
        resourceName: String,
        resourceExtension: String
    ) {
        let destination = rootDirectory.appendingPathComponent(
            "\(id.uuidString).\(resourceExtension)"
        )
        if !FileManager.default.fileExists(atPath: destination.path) {
            guard let bundled = Bundle.main.url(
                forResource: resourceName,
                withExtension: resourceExtension
            ) else {
                logger.error("Missing bundled audio \(resourceName).\(resourceExtension)")
                return
            }
            do {
                try FileManager.default.copyItem(at: bundled, to: destination)
                excludeFromBackup(destination)
            } catch {
                logger.error("Bundled audio copy failed: \(error.localizedDescription)")
                return
            }
        }

        if let index = tracks.firstIndex(where: { $0.id == id }) {
            if !tracks[index].isProtected {
                tracks[index].isProtected = true
                persist()
            }
            return
        }

        let duration = Self.syncDuration(at: destination)
        let item = AudioTrack(
            id: id,
            title: title,
            artist: nil,
            duration: duration,
            fileExtension: resourceExtension,
            isProtected: true
        )
        tracks.insert(item, at: 0)
        persist()
    }

    /// Loads duration without the deprecated synchronous `AVAsset.duration`.
    ///
    /// Uses `Task.detached` so the async load is never scheduled on the caller’s
    /// actor — a plain `Task { }` from `@MainActor` seeding would deadlock the
    /// semaphore wait for up to the timeout.
    nonisolated private static func syncDuration(at url: URL) -> TimeInterval {
        let asset = AVURLAsset(url: url)
        let semaphore = DispatchSemaphore(value: 0)
        let box = DurationBox()
        Task.detached {
            defer { semaphore.signal() }
            do {
                let duration = try await asset.load(.duration)
                let value = CMTimeGetSeconds(duration)
                box.seconds = (value.isNaN || value < 0) ? 0 : value
            } catch {
                box.seconds = 0
            }
        }
        _ = semaphore.wait(timeout: .now() + 5)
        return box.seconds
    }

    /// Tiny hand-off box so `Task.detached` can publish duration across the wait.
    private final class DurationBox: @unchecked Sendable {
        var seconds: TimeInterval = 0
    }

    // MARK: - Persistence

    private static let allowedExtensions: Set<String> = [
        "mp3", "m4a", "aac", "wav", "aiff", "aif", "caf"
    ]

    private func normalizedExtension(_ url: URL) -> String {
        let ext = url.pathExtension.lowercased()
        if ext == "aif" { return "aiff" }
        return ext
    }

    private func fileSize(at url: URL) -> Int64? {
        let values = try? url.resourceValues(forKeys: [.fileSizeKey])
        if let size = values?.fileSize { return Int64(size) }
        return nil
    }

    private struct Metadata {
        var title: String?
        var artist: String?
        var duration: TimeInterval
    }

    private static func readMetadata(at url: URL) async -> Metadata {
        let asset = AVURLAsset(url: url)
        var meta = Metadata(title: nil, artist: nil, duration: 0)
        do {
            let duration = try await asset.load(.duration)
            meta.duration = CMTimeGetSeconds(duration)
            if meta.duration.isNaN || meta.duration < 0 { meta.duration = 0 }

            let items = try await asset.load(.commonMetadata)
            for item in items {
                guard let key = item.commonKey else { continue }
                switch key {
                case .commonKeyTitle:
                    if let value = try await item.load(.stringValue), !value.isEmpty {
                        meta.title = value
                    }
                case .commonKeyArtist:
                    if let value = try await item.load(.stringValue), !value.isEmpty {
                        meta.artist = value
                    }
                default:
                    break
                }
            }
        } catch {
            // Keep defaults when metadata can't be loaded.
        }
        return meta
    }

    /// Loads embedded artwork when present.
    static func artwork(at url: URL) async -> UIImage? {
        let asset = AVURLAsset(url: url)
        do {
            let items = try await asset.load(.commonMetadata)
            for item in items where item.commonKey == .commonKeyArtwork {
                if let data = try await item.load(.dataValue),
                   let image = UIImage(data: data) {
                    return image
                }
            }
        } catch {
            return nil
        }
        return nil
    }

    private func load() {
        let decoded = SalvagingListDecoder.decodeList(
            AudioTrack.self,
            forKey: itemsKey,
            from: defaults,
            logger: logger
        ).elements
        tracks = decoded.filter { track in
            let url = rootDirectory.appendingPathComponent(
                "\(track.id.uuidString).\(track.fileExtension)"
            )
            return FileManager.default.fileExists(atPath: url.path)
        }
        if tracks.count != decoded.count { persist() }
    }

    private func persist() {
        do {
            let data = try JSONEncoder().encode(tracks)
            defaults.set(data, forKey: itemsKey)
            NotificationCenter.default.post(name: Self.didChangeNotification, object: self)
        } catch {
            logger.error("Failed to encode audio: \(error.localizedDescription)")
        }
    }

    private func excludeFromBackup(_ url: URL) {
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        var mutableURL = url
        try? mutableURL.setResourceValues(values)
    }
}
