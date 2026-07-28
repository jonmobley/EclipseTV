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
/// Files live under `LocalMedia/<Landscape|Vertical>/` so the same filename can exist
/// in both libraries. Legacy flat files under `LocalMedia/` migrate to Landscape.
final class LocalMediaStore {

    /// Shared instance written at send time and read when presenting on an external display.
    static let shared = LocalMediaStore()

    private let rootDirectory: URL
    private let ioQueue = DispatchQueue(label: "com.eclipseapp.ios.LocalMediaStore", qos: .utility)
    private let logger = Logger(subsystem: "com.eclipseapp.ios", category: "LocalMediaStore")

    private init() {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        rootDirectory = base.appendingPathComponent("LocalMedia", isDirectory: true)
        try? FileManager.default.createDirectory(at: rootDirectory, withIntermediateDirectories: true)
        excludeFromBackup(rootDirectory)
        for mode in EclipseShareProtocol.LibraryMode.allCases {
            let dir = directory(for: mode)
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            excludeFromBackup(dir)
        }
        migrateLegacyFlatFilesIfNeeded()
    }

    // MARK: - Reads

    /// The local full-resolution file for `id` in `mode`, or nil if absent.
    func localURL(
        forId id: String,
        mode: EclipseShareProtocol.LibraryMode = ExternalOutputSettings.libraryMode
    ) -> URL? {
        let url = fileURL(forId: id, mode: mode)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    func hasMedia(
        forId id: String,
        mode: EclipseShareProtocol.LibraryMode = ExternalOutputSettings.libraryMode
    ) -> Bool {
        localURL(forId: id, mode: mode) != nil
    }

    /// Ids of full-resolution files still on disk for `mode` (filename = library id).
    func storedIds(
        for mode: EclipseShareProtocol.LibraryMode = ExternalOutputSettings.libraryMode
    ) -> [String] {
        let dir = directory(for: mode)
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: dir, includingPropertiesForKeys: [.isDirectoryKey]
        ) else { return [] }
        return files.compactMap { url in
            let isDir = (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
            guard !isDir else { return nil }
            return url.lastPathComponent
        }
    }

    // MARK: - Writes

    /// Keeps a persistent copy of `fileURL` keyed by `id` under the mode subdirectory.
    func store(
        fileURL sourceURL: URL,
        forId id: String,
        mode: EclipseShareProtocol.LibraryMode = ExternalOutputSettings.libraryMode
    ) {
        let destination = fileURL(forId: id, mode: mode)
        ioQueue.async { [weak self] in
            guard let self = self else { return }
            let fm = FileManager.default
            do {
                try fm.createDirectory(
                    at: destination.deletingLastPathComponent(),
                    withIntermediateDirectories: true
                )
                if fm.fileExists(atPath: destination.path) {
                    try fm.removeItem(at: destination)
                }
                try fm.copyItem(at: sourceURL, to: destination)
            } catch {
                self.logger.error(
                    "Failed to store full-res media for \(id, privacy: .public): \(error.localizedDescription)"
                )
            }
        }
    }

    /// Deletes the stored copy for a single id in `mode`, if present.
    func remove(
        id: String,
        mode: EclipseShareProtocol.LibraryMode = ExternalOutputSettings.libraryMode
    ) {
        let url = fileURL(forId: id, mode: mode)
        ioQueue.async {
            try? FileManager.default.removeItem(at: url)
        }
    }

    // MARK: - Maintenance

    /// Removes stored files in `mode` whose ids are not in `liveIds`.
    func prune(
        keeping liveIds: Set<String>,
        mode: EclipseShareProtocol.LibraryMode = ExternalOutputSettings.libraryMode
    ) {
        let dir = directory(for: mode)
        ioQueue.async {
            let fm = FileManager.default
            guard let files = try? fm.contentsOfDirectory(
                at: dir, includingPropertiesForKeys: nil
            ) else { return }
            let keepNames = Set(liveIds.map { Self.fileName(forId: $0) })
            for file in files where !keepNames.contains(file.lastPathComponent) {
                try? fm.removeItem(at: file)
            }
        }
    }

    // MARK: - Helpers

    private func directory(for mode: EclipseShareProtocol.LibraryMode) -> URL {
        rootDirectory.appendingPathComponent(mode.directoryName, isDirectory: true)
    }

    private func fileURL(forId id: String, mode: EclipseShareProtocol.LibraryMode) -> URL {
        directory(for: mode).appendingPathComponent(Self.fileName(forId: id))
    }

    /// Moves loose files under `LocalMedia/` into `LocalMedia/Landscape/`.
    private func migrateLegacyFlatFilesIfNeeded() {
        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: rootDirectory,
            includingPropertiesForKeys: [.isDirectoryKey]
        ) else { return }

        let landscape = directory(for: .landscape)
        try? FileManager.default.createDirectory(at: landscape, withIntermediateDirectories: true)

        for url in contents {
            let isDir = (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
            if isDir { continue }
            let dest = landscape.appendingPathComponent(url.lastPathComponent)
            if FileManager.default.fileExists(atPath: dest.path) {
                try? FileManager.default.removeItem(at: url)
                continue
            }
            do {
                try FileManager.default.moveItem(at: url, to: dest)
            } catch {
                logger.error(
                    "Failed to migrate local media \(url.lastPathComponent, privacy: .public): \(error.localizedDescription)"
                )
            }
        }
    }

    private static func fileName(forId id: String) -> String {
        let component = (id as NSString).lastPathComponent
        let ext = (component as NSString).pathExtension
        let base = (component as NSString).deletingPathExtension
        let safeBase = base.unicodeScalars.map {
            CharacterSet.alphanumerics.contains($0) ? Character($0) : "_"
        }
        var name = String(safeBase)
        if name.isEmpty || name.allSatisfy({ $0 == "_" }) { name = "item" }
        let safeExt = ext.unicodeScalars
            .filter { CharacterSet.alphanumerics.contains($0) }
            .map(String.init)
            .joined()
        return safeExt.isEmpty ? name : "\(name).\(safeExt)"
    }

    private func excludeFromBackup(_ url: URL) {
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        var mutableURL = url
        try? mutableURL.setResourceValues(values)
    }
}
