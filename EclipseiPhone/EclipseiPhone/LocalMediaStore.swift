//
//  LocalMediaStore.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

// LocalMediaStore.swift
import UIKit
import os.log

/// Persistent store of the full-resolution media the phone has sent to an Apple TV.
///
/// The companion normally only mirrors thumbnails of the TV library, but the AirPlay
/// presentation feature needs the original file on the phone so it can render the
/// selected item fullscreen on an external display without the TV-side companion app.
///
/// Files are keyed by the same identifier the TV uses for a `LibraryItemDTO`: the
/// resource name the phone sent, which is `url.lastPathComponent`. Keeping the key
/// identical means a local copy can be looked up directly from `TVLibraryStore.currentId`.
final class LocalMediaStore {

    /// Shared instance written at send time and read when presenting on an external display.
    static let shared = LocalMediaStore()

    private let directory: URL
    private let ioQueue = DispatchQueue(label: "com.eclipseapp.ios.LocalMediaStore", qos: .utility)
    private let logger = Logger(subsystem: "com.eclipseapp.ios", category: "LocalMediaStore")

    private init() {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        directory = base.appendingPathComponent("LocalMedia", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        excludeFromBackup(directory)
    }

    // MARK: - Reads

    /// The local full-resolution file for `id`, or nil if the phone never kept a copy
    /// (e.g. the item was sent from another device).
    func localURL(forId id: String) -> URL? {
        let url = fileURL(forId: id)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    func hasMedia(forId id: String) -> Bool {
        localURL(forId: id) != nil
    }

    // MARK: - Writes

    /// Keeps a persistent copy of `fileURL` keyed by `id`. The copy runs off the main
    /// thread; the source (a temporary send file) is read-only here, so it is safe to
    /// copy concurrently with the MultipeerConnectivity transfer that reads the same file.
    func store(fileURL sourceURL: URL, forId id: String) {
        let destination = fileURL(forId: id)
        ioQueue.async { [weak self] in
            guard let self = self else { return }
            let fm = FileManager.default
            do {
                if fm.fileExists(atPath: destination.path) {
                    try fm.removeItem(at: destination)
                }
                try fm.copyItem(at: sourceURL, to: destination)
            } catch {
                self.logger.error("Failed to store full-res media for \(id, privacy: .public): \(error.localizedDescription)")
            }
        }
    }

    /// Deletes the stored copy for a single id, if present (e.g. the user removed a
    /// not-yet-synced local item).
    func remove(id: String) {
        let url = fileURL(forId: id)
        ioQueue.async {
            try? FileManager.default.removeItem(at: url)
        }
    }

    // MARK: - Maintenance

    /// Removes any stored files whose ids are not in `liveIds`, mirroring the thumbnail
    /// pruning in `TVLibraryStore` so deleting an item on the TV frees the phone copy.
    func prune(keeping liveIds: Set<String>) {
        ioQueue.async { [weak self] in
            guard let self = self else { return }
            let fm = FileManager.default
            guard let files = try? fm.contentsOfDirectory(at: self.directory,
                                                          includingPropertiesForKeys: nil) else { return }
            let keepNames = Set(liveIds.map { Self.fileName(forId: $0) })
            for file in files where !keepNames.contains(file.lastPathComponent) {
                try? fm.removeItem(at: file)
            }
        }
    }

    // MARK: - Helpers

    private func fileURL(forId id: String) -> URL {
        directory.appendingPathComponent(Self.fileName(forId: id))
    }

    /// Maps an id to a filesystem-safe file name while preserving its extension so the
    /// stored file can be type-sniffed (image vs video) and played back correctly.
    private static func fileName(forId id: String) -> String {
        let ext = (id as NSString).pathExtension
        let base = (id as NSString).deletingPathExtension
        let safeBase = base.unicodeScalars.map {
            CharacterSet.alphanumerics.contains($0) ? Character($0) : "_"
        }
        let name = String(safeBase)
        return ext.isEmpty ? name : "\(name).\(ext)"
    }

    private func excludeFromBackup(_ url: URL) {
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        var mutableURL = url
        try? mutableURL.setResourceValues(values)
    }
}
