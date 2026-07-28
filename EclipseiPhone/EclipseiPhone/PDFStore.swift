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
        return item
    }

    /// Removes the bookmark and deletes its file + thumbnail.
    func remove(id: UUID) {
        let before = documents.count
        documents.removeAll { $0.id == id }
        guard documents.count != before else { return }
        let url = rootDirectory.appendingPathComponent("\(id.uuidString).pdf")
        try? FileManager.default.removeItem(at: url)
        PDFThumbnailStore.shared.remove(id: id)
        persist()
    }

    // MARK: - Persistence

    private func load() {
        guard let data = defaults.data(forKey: itemsKey) else { return }
        do {
            let decoded = try JSONDecoder().decode([SavedPDF].self, from: data)
            // Drop bookmarks whose files were deleted outside the app.
            documents = decoded.filter { fileURL(for: $0.id) != nil }
            if documents.count != decoded.count { persist() }
        } catch {
            logger.error("Failed to decode PDFs: \(error.localizedDescription)")
            documents = []
        }
    }

    private func persist() {
        do {
            let data = try JSONEncoder().encode(documents)
            defaults.set(data, forKey: itemsKey)
            NotificationCenter.default.post(name: Self.didChangeNotification, object: self)
        } catch {
            logger.error("Failed to encode PDFs: \(error.localizedDescription)")
        }
    }

    private func excludeFromBackup(_ url: URL) {
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        var mutableURL = url
        try? mutableURL.setResourceValues(values)
    }
}
