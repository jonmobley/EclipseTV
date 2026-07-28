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

        var errorDescription: String? {
            switch self {
            case .copyFailed: return "Couldn't save that audio file. Please try again."
            case .invalidFile: return "That doesn't look like a supported audio file."
            case .fileTooLarge: return "That file is too large. Maximum size is 200 MB."
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
        let resolvedTitle = trimmed.isEmpty ? fallbackTitle : trimmed
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
            title: meta.title ?? resolvedTitle,
            artist: meta.artist,
            duration: meta.duration,
            fileExtension: ext
        )
        tracks.insert(item, at: 0)
        persist()
        return item
    }

    /// Removes the track and deletes its file; prunes playlists.
    func remove(id: UUID) {
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
        guard let data = defaults.data(forKey: itemsKey) else { return }
        do {
            let decoded = try JSONDecoder().decode([AudioTrack].self, from: data)
            tracks = decoded.filter { track in
                let url = rootDirectory.appendingPathComponent(
                    "\(track.id.uuidString).\(track.fileExtension)"
                )
                return FileManager.default.fileExists(atPath: url.path)
            }
            if tracks.count != decoded.count { persist() }
        } catch {
            logger.error("Failed to decode audio: \(error.localizedDescription)")
            tracks = []
        }
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
