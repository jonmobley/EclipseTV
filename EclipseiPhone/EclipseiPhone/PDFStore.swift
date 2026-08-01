//
//  PDFStore.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import Foundation
import os.log

/// Persists AirPlay PDF bookmarks and their files under Application Support.
@MainActor
final class PDFStore {

    static let shared = PDFStore()

    /// Posted when the saved PDF list changes.
    static let didChangeNotification = Notification.Name("PDFStore.didChange")

    enum StoreError: LocalizedError {
        case copyFailed
        case invalidFile

        var errorDescription: String? {
            switch self {
            case .copyFailed: return "Couldn't save that PDF. Please try again."
            case .invalidFile: return "That doesn't look like a readable PDF."
            }
        }
    }

    private(set) var documents: [SavedPDF] = []

    private let defaults: UserDefaults
    private let itemsKey = "EclipseTV.pdfs.items"
    /// Ids the server has acknowledged, so launch does not re-upload every file.
    private let syncedIdsKey = "EclipseTV.pdfs.syncedIds"
    private var syncedIds: Set<String> = []
    private let rootDirectory: URL
    private let logger = Logger(subsystem: "com.eclipseapp.ios", category: "PDFStore")

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let base = FileManager.default.urls(
            for: .applicationSupportDirectory, in: .userDomainMask
        )[0]
        rootDirectory = base.appendingPathComponent("PDFs", isDirectory: true)
        try? FileManager.default.createDirectory(
            at: rootDirectory, withIntermediateDirectories: true
        )
        excludeFromBackup(rootDirectory)
        load()
    }

    // MARK: - Reads

    /// On-disk URL for a saved PDF, or `nil` if the file is missing.
    func fileURL(for id: UUID) -> URL? {
        let url = rootDirectory.appendingPathComponent("\(id.uuidString).pdf")
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    /// Every PDF id that must survive an Apple TV library prune.
    ///
    /// Saved PDFs are phone-owned — the TV never sees them — so a manifest that omits
    /// them must not strip their cards out of Shows.
    var keepIds: Set<String> {
        Set(documents.map { $0.id.uuidString })
    }

    /// Documents the server has not acknowledged yet (drives the sync indicator).
    var idsNeedingUpload: [UUID] {
        documents.filter { !syncedIds.contains($0.id.uuidString) }.map(\.id)
    }

    var hasPendingSync: Bool { !idsNeedingUpload.isEmpty }

    // MARK: - Mutations

    /// Copies `sourceURL` into the store and returns the new bookmark.
    @discardableResult
    func add(from sourceURL: URL, title: String?) throws -> SavedPDF {
        let trimmed = title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let resolvedTitle = trimmed.isEmpty
            ? sourceURL.deletingPathExtension().lastPathComponent
            : trimmed
        guard !resolvedTitle.isEmpty else { throw StoreError.invalidFile }

        let id = UUID()
        let destination = rootDirectory.appendingPathComponent("\(id.uuidString).pdf")
        do {
            if FileManager.default.fileExists(atPath: destination.path) {
                try FileManager.default.removeItem(at: destination)
            }
            try FileManager.default.copyItem(at: sourceURL, to: destination)
        } catch {
            logger.error("PDF copy failed: \(error.localizedDescription)")
            throw StoreError.copyFailed
        }

        let item = SavedPDF(id: id, title: resolvedTitle)
        documents.insert(item, at: 0)
        persist()
        PDFThumbnailStore.shared.generate(from: destination, for: id)
        scheduleSaveIfNeeded(id: id)
        return item
    }

    /// Inserts (or updates) a PDF that arrived from iCloud, copying in its file.
    ///
    /// A record without usable bytes is skipped rather than stored: a document with no
    /// file can't render a card, a thumbnail, or a presentation, so a placeholder would
    /// only be a dead tile the user can't act on.
    func applyRemote(_ doc: SavedPDF, assetURL: URL?) {
        let destination = rootDirectory.appendingPathComponent("\(doc.id.uuidString).pdf")
        if fileURL(for: doc.id) == nil {
            guard let assetURL else {
                logger.error("Remote PDF \(doc.id.uuidString, privacy: .public) has no asset")
                return
            }
            do {
                try FileManager.default.copyItem(at: assetURL, to: destination)
            } catch {
                logger.error("Remote PDF copy failed: \(error.localizedDescription)")
                return
            }
        }
        if let index = documents.firstIndex(where: { $0.id == doc.id }) {
            documents[index] = doc
        } else {
            documents.insert(doc, at: 0)
        }
        // The server is the source of this copy, so nothing to push back up.
        syncedIds.insert(doc.id.uuidString)
        persist()
        if PDFThumbnailStore.shared.image(for: doc.id) == nil {
            PDFThumbnailStore.shared.generate(from: destination, for: doc.id)
        }
    }

    /// Records that the backend accepted this document's upload.
    func markSynced(id: UUID) {
        guard !syncedIds.contains(id.uuidString) else { return }
        syncedIds.insert(id.uuidString)
        persistSyncedIds()
    }

    /// Enqueues an upload unless we are mid-apply of a remote change.
    private func scheduleSaveIfNeeded(id: UUID) {
        guard !EclipseSyncController.shared.isApplyingRemote else { return }
        EclipseSyncController.shared.backend.schedulePDFSave(id: id)
    }

    /// Removes the bookmark and deletes its file + thumbnail.
    ///
    /// Also drops Show membership: the file is gone, so a lingering id would leave
    /// every Show that used it with an unrenderable member (and possibly a cover
    /// pointing at nothing).
    func remove(id: UUID) {
        let before = documents.count
        documents.removeAll { $0.id == id }
        guard documents.count != before else { return }
        let url = rootDirectory.appendingPathComponent("\(id.uuidString).pdf")
        try? FileManager.default.removeItem(at: url)
        PDFThumbnailStore.shared.remove(id: id)
        syncedIds.remove(id.uuidString)
        persist()
        LocalAlbumStore.shared.removeItemFromAllAlbums(itemId: id.uuidString)
        // A server tombstone arrives with the flag set — deleting again would echo.
        guard !EclipseSyncController.shared.isApplyingRemote else { return }
        EclipseSyncController.shared.backend.schedulePDFDelete(id: id)
    }

    // MARK: - Persistence

    private func load() {
        syncedIds = Set(defaults.stringArray(forKey: syncedIdsKey) ?? [])
        let decoded = SalvagingListDecoder.decodeList(
            SavedPDF.self,
            forKey: itemsKey,
            from: defaults,
            logger: logger
        ).elements
        // Drop bookmarks whose files were deleted outside the app.
        documents = decoded.filter { fileURL(for: $0.id) != nil }
        if documents.count != decoded.count { persist() }
    }

    private func persist() {
        do {
            let data = try JSONEncoder().encode(documents)
            defaults.set(data, forKey: itemsKey)
            persistSyncedIds()
            NotificationCenter.default.post(name: Self.didChangeNotification, object: self)
        } catch {
            logger.error("Failed to encode PDFs: \(error.localizedDescription)")
        }
    }

    private func persistSyncedIds() {
        defaults.set(Array(syncedIds), forKey: syncedIdsKey)
    }

    private func excludeFromBackup(_ url: URL) {
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        var mutableURL = url
        try? mutableURL.setResourceValues(values)
    }
}
