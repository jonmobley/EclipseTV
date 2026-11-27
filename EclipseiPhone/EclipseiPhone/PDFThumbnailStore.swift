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
    /// Bounded like `WebThumbnailStore`: renders are larger now (up to 960 px), and a
    /// plain dictionary held every one for the life of the app. Reads fall back to disk.
    private let memory: NSCache<NSUUID, UIImage> = {
        let cache = NSCache<NSUUID, UIImage>()
        cache.totalCostLimit = 24 * 1024 * 1024
        return cache
    }()
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
        if let cached = memory.object(forKey: id as NSUUID) { return cached }
        let url = fileURL(for: id)
        guard let image = UIImage(contentsOfFile: url.path) else {
            rebuildIfMissing(id)
            return nil
        }
        remember(image, for: id)
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
            let image = page.thumbnail(of: Self.renderSize, for: .mediaBox)
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
                self.remember(image, for: id)
                // The memory cache can evict this later and iOS can purge Caches again;
                // a later miss must be free to rebuild. Failed builds stay marked.
                self.rebuildRequested.remove(id)
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
        memory.removeObject(forKey: id as NSUUID)
        rebuildRequested.remove(id)
        let urls = [fileURL(for: id), legacyFileURL(for: id)]
        ioQueue.async {
            for url in urls { try? FileManager.default.removeItem(at: url) }
        }
        NotificationCenter.default.post(name: Self.didChangeNotification, object: self)
    }

    private func remember(_ image: UIImage, for id: UUID) {
        let pixels = image.size.width * image.scale * image.size.height * image.scale
        memory.setObject(image, forKey: id as NSUUID, cost: Int(pixels * 4))
    }

    // MARK: - Paths

    /// Box the first page is fitted into. It used to be 360×480, which left a
    /// landscape page (slides) 360 px wide, soft on a phone tile at 3×. Square so a
    /// page of either shape gets 960 px on its long side.
    nonisolated static let renderSize = CGSize(width: 960, height: 960)

    /// `-v2` since the larger render (2026-11-26): older, smaller files are left
    /// unread and each card rebuilds its picture once (`rebuildIfMissing`).
    private func fileURL(for id: UUID) -> URL {
        rootDirectory.appendingPathComponent("\(id.uuidString)-v2.jpg")
    }

    /// The pre-v2 file, deleted with the document.
    private func legacyFileURL(for id: UUID) -> URL {
        rootDirectory.appendingPathComponent("\(id.uuidString).jpg")
    }
}
