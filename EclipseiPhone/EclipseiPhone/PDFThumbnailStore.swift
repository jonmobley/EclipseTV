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

    private init() {
        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        rootDirectory = base.appendingPathComponent("PDFThumbnails", isDirectory: true)
        try? FileManager.default.createDirectory(
            at: rootDirectory, withIntermediateDirectories: true
        )
    }

    // MARK: - Reads

    /// First-page thumbnail if available.
    func image(for id: UUID) -> UIImage? {
        if let cached = memory[id] { return cached }
        let url = fileURL(for: id)
        guard let image = UIImage(contentsOfFile: url.path) else { return nil }
        memory[id] = image
        return image
    }

    // MARK: - Writes

    /// Renders page 0 of the PDF at `pdfURL` and persists a JPEG preview.
    func generate(from pdfURL: URL, for id: UUID) {
        let destination = fileURL(for: id)
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

    /// Drops the thumbnail for a deleted PDF.
    func remove(id: UUID) {
        memory[id] = nil
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
