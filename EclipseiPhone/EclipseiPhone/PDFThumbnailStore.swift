//
//  PDFThumbnailStore.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import UIKit
import PDFKit
import os.log

/// Disk-backed first-page previews for saved PDFs.
@MainActor
final class PDFThumbnailStore {

    static let shared = PDFThumbnailStore()

    /// Posted when a thumbnail is saved or removed.
    static let didChangeNotification = Notification.Name("PDFThumbnailStore.didChange")

    private let rootDirectory: URL
    private let ioQueue = DispatchQueue(
        label: "com.eclipseapp.ios.PDFThumbnailStore", qos: .utility
    )
    private let logger = Logger(subsystem: "com.eclipseapp.ios", category: "PDFThumbnail")
    private var memory: [UUID: UIImage] = [:]
    /// Finds a saved PDF's file, so a purged preview can be rebuilt from it.
    private let pdfURL: (UUID) -> URL?
    /// Ids already sent for a rebuild, so a broken PDF isn't re-rendered on every reload.
    private var rebuildRequested: Set<UUID> = []

    /// - Parameters:
    ///   - rootDirectory: Where previews live. Defaults to `Caches/PDFThumbnails`;
    ///     tests pass a scratch directory.
    ///   - pdfURL: Looks up a saved PDF's file. Defaults to `PDFStore.shared`.
    init(rootDirectory: URL? = nil, pdfURL: ((UUID) -> URL?)? = nil) {
        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        self.rootDirectory = rootDirectory
            ?? base.appendingPathComponent("PDFThumbnails", isDirectory: true)
        self.pdfURL = pdfURL ?? { PDFStore.shared.fileURL(for: $0) }
        try? FileManager.default.createDirectory(
            at: self.rootDirectory, withIntermediateDirectories: true
        )
    }

    // MARK: - Reads

    /// First-page thumbnail if available.
    ///
    /// Previews live in Caches, which iOS empties when storage runs low. On a miss
    /// for a PDF that is still saved, this starts a rebuild and returns `nil`; the
    /// tile picks the preview up from `didChangeNotification`.
    func image(for id: UUID) -> UIImage? {
        if let cached = memory[id] { return cached }
        let url = fileURL(for: id)
        guard let image = UIImage(contentsOfFile: url.path) else {
            rebuildIfMissing(id)
            return nil
        }
        memory[id] = image
        return image
    }

    // MARK: - Writes

    /// Renders page 0 of the PDF at `pdfURL` and persists a JPEG preview.
    func generate(from pdfURL: URL, for id: UUID) {
        let destination = fileURL(for: id)
        let directory = rootDirectory
        ioQueue.async { [weak self] in
            let log = Logger(subsystem: "com.eclipseapp.ios", category: "PDFThumbnail")
            guard let document = PDFDocument(url: pdfURL),
                  let page = document.page(at: 0) else {
                log.error("Could not open PDF for thumbnail")
                return
            }
            let size = CGSize(width: 360, height: 480)
            let image = page.thumbnail(of: size, for: .mediaBox)
            guard let data = image.jpegData(compressionQuality: 0.85) else { return }
            do {
                // iOS may have purged the whole folder, not just its files.
                try FileManager.default.createDirectory(
                    at: directory, withIntermediateDirectories: true
                )
                try data.write(to: destination, options: .atomic)
            } catch {
                log.error("Thumbnail save failed: \(error.localizedDescription)")
                return
            }
            Task { @MainActor in
                guard let self else { return }
                self.memory[id] = image
                NotificationCenter.default.post(
                    name: Self.didChangeNotification, object: self
                )
            }
        }
    }

    /// Re-renders a purged preview once, when the PDF itself is still on disk.
    private func rebuildIfMissing(_ id: UUID) {
        guard !rebuildRequested.contains(id), let source = pdfURL(id) else { return }
        rebuildRequested.insert(id)
        generate(from: source, for: id)
    }

    /// Drops the thumbnail for a deleted PDF.
    func remove(id: UUID) {
        memory[id] = nil
        rebuildRequested.remove(id)
        let url = fileURL(for: id)
        ioQueue.async {
            try? FileManager.default.removeItem(at: url)
        }
        NotificationCenter.default.post(name: Self.didChangeNotification, object: self)
    }

    // MARK: - Paths

    private func fileURL(for id: UUID) -> URL {
        rootDirectory.appendingPathComponent("\(id.uuidString).jpg")
    }
}
