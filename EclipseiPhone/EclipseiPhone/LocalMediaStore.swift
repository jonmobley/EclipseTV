//
//  LocalMediaStore.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import UIKit
import os.log

/// Where a full-resolution file lives and whether it should be backed up.
enum MediaProvenance: String, Codable, CaseIterable {
    /// Copy of a Photos import — excluded from iCloud device backup.
    case imported
    /// In-app camera capture (or CloudKit download of one) — included in backup.
    case captured
}

/// Persistent store of full-resolution media on the phone.
///
/// Imported files live under `LocalMedia/<Landscape|Vertical>/` (backup-excluded).
/// Captures live under `Captures/<Landscape|Vertical>/` (backed up with the device).
final class LocalMediaStore {

    /// Shared instance written at send / capture time and read for AirPlay / preview.
    static let shared = LocalMediaStore()

    private let importedRoot: URL
    private let capturesRoot: URL
    private let ioQueue = DispatchQueue(label: "com.eclipseapp.ios.LocalMediaStore", qos: .utility)
    private let logger = Logger(subsystem: "com.eclipseapp.ios", category: "LocalMediaStore")

    private init() {
        let base = FileManager.default.urls(
            for: .applicationSupportDirectory, in: .userDomainMask
        )[0]
        importedRoot = base.appendingPathComponent("LocalMedia", isDirectory: true)
        capturesRoot = base.appendingPathComponent("Captures", isDirectory: true)
        try? FileManager.default.createDirectory(
            at: importedRoot, withIntermediateDirectories: true
        )
        try? FileManager.default.createDirectory(
            at: capturesRoot, withIntermediateDirectories: true
        )
        excludeFromBackup(importedRoot)
        for mode in EclipseShareProtocol.LibraryMode.allCases {
            let imported = directory(for: mode, provenance: .imported)
            let captured = directory(for: mode, provenance: .captured)
            try? FileManager.default.createDirectory(
                at: imported, withIntermediateDirectories: true
            )
            try? FileManager.default.createDirectory(
                at: captured, withIntermediateDirectories: true
            )
            excludeFromBackup(imported)
        }
        migrateLegacyFlatFilesIfNeeded()
    }

    // MARK: - Reads

    /// The local full-resolution file for `id` in `mode`, preferring captures.
    func localURL(
        forId id: String,
        mode: EclipseShareProtocol.LibraryMode = ExternalOutputSettings.libraryMode
    ) -> URL? {
        if let url = fileURLIfPresent(forId: id, mode: mode, provenance: .captured) {
            return url
        }
        return fileURLIfPresent(forId: id, mode: mode, provenance: .imported)
    }

    /// Provenance of the on-disk file for `id`, if any.
    func provenance(
        forId id: String,
        mode: EclipseShareProtocol.LibraryMode = ExternalOutputSettings.libraryMode
    ) -> MediaProvenance? {
        if fileURLIfPresent(forId: id, mode: mode, provenance: .captured) != nil {
            return .captured
        }
        if fileURLIfPresent(forId: id, mode: mode, provenance: .imported) != nil {
            return .imported
        }
        return nil
    }

    func hasMedia(
        forId id: String,
        mode: EclipseShareProtocol.LibraryMode = ExternalOutputSettings.libraryMode
    ) -> Bool {
        localURL(forId: id, mode: mode) != nil
    }

    /// Ids on disk for `mode`. When `provenance` is nil, returns the union
    /// (captures first in the list for stable logging only — callers treat as a set).
    func storedIds(
        for mode: EclipseShareProtocol.LibraryMode = ExternalOutputSettings.libraryMode,
        provenance: MediaProvenance? = nil
    ) -> [String] {
        if let provenance {
            return listIds(in: directory(for: mode, provenance: provenance))
        }
        let captured = listIds(in: directory(for: mode, provenance: .captured))
        let imported = listIds(in: directory(for: mode, provenance: .imported))
        return captured + imported.filter { !captured.contains($0) }
    }

    // MARK: - Writes

    /// Copies `sourceURL` into the store under `provenance` for `mode`.
    ///
    /// `completion` runs on the main queue with whether the bytes landed. Callers that
    /// create a record pointing at this file should wait for it — a record whose file is
    /// still being written renders as an empty tile.
    func store(
        fileURL sourceURL: URL,
        forId id: String,
        mode: EclipseShareProtocol.LibraryMode = ExternalOutputSettings.libraryMode,
        provenance: MediaProvenance = .imported,
        completion: ((Bool) -> Void)? = nil
    ) {
        let destination = fileURL(forId: id, mode: mode, provenance: provenance)
        ioQueue.async { [weak self] in
            guard let self else {
                if let completion { DispatchQueue.main.async { completion(false) } }
                return
            }
            var stored = false
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
                stored = true
            } catch {
                self.logger.error(
                    "Failed to store media for \(id, privacy: .public): \(error.localizedDescription)"
                )
            }
            if let completion {
                DispatchQueue.main.async { completion(stored) }
            }
        }
    }

    /// Synchronously copies into the captures root (used by CloudKit downloads).
    func storeSynchronously(
        fileURL sourceURL: URL,
        forId id: String,
        mode: EclipseShareProtocol.LibraryMode,
        provenance: MediaProvenance
    ) throws {
        let destination = fileURL(forId: id, mode: mode, provenance: provenance)
        let fm = FileManager.default
        try fm.createDirectory(
            at: destination.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        if fm.fileExists(atPath: destination.path) {
            try fm.removeItem(at: destination)
        }
        try fm.copyItem(at: sourceURL, to: destination)
    }

    /// Deletes the stored copy for `id` in `mode` (both provenances when nil).
    func remove(
        id: String,
        mode: EclipseShareProtocol.LibraryMode = ExternalOutputSettings.libraryMode,
        provenance: MediaProvenance? = nil
    ) {
        let targets: [MediaProvenance] = provenance.map { [$0] } ?? [.captured, .imported]
        ioQueue.async { [weak self] in
            guard let self else { return }
            for prov in targets {
                let url = self.fileURL(forId: id, mode: mode, provenance: prov)
                try? FileManager.default.removeItem(at: url)
            }
        }
    }

    // MARK: - Maintenance

    /// Prunes **imported** files only. Captures are never pruned by TV manifests.
    func prune(
        keeping liveIds: Set<String>,
        mode: EclipseShareProtocol.LibraryMode = ExternalOutputSettings.libraryMode
    ) {
        let dir = directory(for: mode, provenance: .imported)
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

    /// On-disk / library id for `id` (e.g. UUID hyphens → underscores).
    static func canonicalFileName(forId id: String) -> String {
        fileName(forId: id)
    }

    private func directory(
        for mode: EclipseShareProtocol.LibraryMode,
        provenance: MediaProvenance
    ) -> URL {
        let root = provenance == .captured ? capturesRoot : importedRoot
        return root.appendingPathComponent(mode.directoryName, isDirectory: true)
    }

    private func fileURL(
        forId id: String,
        mode: EclipseShareProtocol.LibraryMode,
        provenance: MediaProvenance
    ) -> URL {
        directory(for: mode, provenance: provenance)
            .appendingPathComponent(Self.fileName(forId: id))
    }

    private func fileURLIfPresent(
        forId id: String,
        mode: EclipseShareProtocol.LibraryMode,
        provenance: MediaProvenance
    ) -> URL? {
        let url = fileURL(forId: id, mode: mode, provenance: provenance)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    private func listIds(in dir: URL) -> [String] {
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: dir, includingPropertiesForKeys: [.isDirectoryKey]
        ) else { return [] }
        return files.compactMap { url in
            let isDir = (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory)
                ?? false
            guard !isDir else { return nil }
            return url.lastPathComponent
        }
    }

    private func migrateLegacyFlatFilesIfNeeded() {
        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: importedRoot,
            includingPropertiesForKeys: [.isDirectoryKey]
        ) else { return }

        let landscape = directory(for: .landscape, provenance: .imported)
        try? FileManager.default.createDirectory(
            at: landscape, withIntermediateDirectories: true
        )

        for url in contents {
            let isDir = (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory)
                ?? false
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
