//
//  ShowMediaExporter.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import Foundation

/// Builds a ZIP of a Show's media, slideshows, and PDFs for the share sheet.
enum ShowMediaExporter {

    enum ExportError: LocalizedError {
        case showMissing
        case nothingToExport
        case packageFailed

        var errorDescription: String? {
            switch self {
            case .showMissing:
                return "That Show is no longer on this iPhone."
            case .nothingToExport:
                return "This Show has no media, slideshows, or PDFs to export."
            case .packageFailed:
                return "Couldn't prepare the export. Please try again."
            }
        }
    }

    /// One file to place in the archive.
    struct PackageEntry: Sendable {
        let relativePath: String
        let sourceURL: URL
    }

    /// Snapshot of files to archive (paths resolved on the main actor).
    struct PackageRequest: Sendable {
        let zipFileName: String
        let entries: [PackageEntry]
    }

    /// Resolves Show membership into numbered file entries. Call on the main actor.
    @MainActor
    static func makePackageRequest(forShowId id: UUID) throws -> PackageRequest {
        guard let album = LocalAlbumStore.shared.album(id: id) else {
            throw ExportError.showMissing
        }
        let built = buildSources(for: album)
        guard !built.sources.isEmpty else { throw ExportError.nothingToExport }

        let planned = ShowMediaExportPlanner.plan(nodes: built.nodes)
        let entries = planned.map { plan in
            PackageEntry(
                relativePath: plan.relativePath,
                sourceURL: built.sources[plan.sourceIndex]
            )
        }
        let zipFileName = "\(ExportFileName.sanitize(album.name)).zip"
        return PackageRequest(zipFileName: zipFileName, entries: entries)
    }

    /// Writes `request` to a temporary ZIP. Safe to call off the main actor.
    static func writeZip(_ request: PackageRequest) throws -> URL {
        let zipURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(request.zipFileName)
        let pairs = request.entries.map {
            (relativePath: $0.relativePath, sourceURL: $0.sourceURL)
        }
        do {
            try ZipStoreWriter.write(entries: pairs, to: zipURL)
        } catch {
            throw ExportError.packageFailed
        }
        return zipURL
    }

    // MARK: - Surface → nodes

    private struct Built {
        let nodes: [ShowMediaExportPlanner.Node]
        let sources: [URL]
    }

    @MainActor
    private static func buildSources(for album: LocalAlbum) -> Built {
        let slideshowIds = SlideshowStore.shared.slideshows(forShowId: album.id)
            .map { ShowSlideshowToken.token(for: $0.id) }
        let surface = album.resolvedSurfaceIds(
            slideshowIds: slideshowIds,
            countdownIds: nil,
            livePollIds: nil
        )
        let mode = album.orientation.libraryMode
        var nodes: [ShowMediaExportPlanner.Node] = []
        var sources: [URL] = []

        for surfaceId in surface {
            if let slideshowId = ShowSlideshowToken.slideshowId(from: surfaceId),
               let show = SlideshowStore.shared.slideshow(id: slideshowId),
               show.showId == album.id {
                appendSlideshow(
                    show, mode: mode, nodes: &nodes, sources: &sources
                )
                continue
            }
            if ShowToolToken.isTool(surfaceId)
                || ShowCountdownToken.isCountdown(surfaceId)
                || ShowLivePollToken.isLivePoll(surfaceId) {
                continue
            }
            if let uuid = UUID(uuidString: surfaceId) {
                if WebPageStore.shared.page(id: uuid) != nil { continue }
                if let doc = PDFStore.shared.documents.first(where: { $0.id == uuid }) {
                    appendPDF(doc, nodes: &nodes, sources: &sources)
                    continue
                }
            }
            appendMedia(
                id: surfaceId, mode: mode, nodes: &nodes, sources: &sources
            )
        }
        return Built(nodes: nodes, sources: sources)
    }

    @MainActor
    private static func appendMedia(
        id: String,
        mode: EclipseShareProtocol.LibraryMode,
        nodes: inout [ShowMediaExportPlanner.Node],
        sources: inout [URL]
    ) {
        guard let url = LocalMediaStore.shared.localURL(forId: id, mode: mode)
        else { return }
        nodes.append(
            .file(title: mediaTitle(forId: id), pathExtension: url.pathExtension)
        )
        sources.append(url)
    }

    @MainActor
    private static func appendPDF(
        _ doc: SavedPDF,
        nodes: inout [ShowMediaExportPlanner.Node],
        sources: inout [URL]
    ) {
        guard let url = PDFStore.shared.fileURL(for: doc.id) else { return }
        nodes.append(.file(title: doc.title, pathExtension: "pdf"))
        sources.append(url)
    }

    @MainActor
    private static func appendSlideshow(
        _ show: Slideshow,
        mode: EclipseShareProtocol.LibraryMode,
        nodes: inout [ShowMediaExportPlanner.Node],
        sources: inout [URL]
    ) {
        var slides: [ShowMediaExportPlanner.Node.Slide] = []
        var slideURLs: [URL] = []
        for slideId in show.itemIds {
            guard let url = LocalMediaStore.shared.localURL(
                forId: slideId, mode: mode
            ) else { continue }
            slides.append(.init(
                title: mediaTitle(forId: slideId),
                pathExtension: url.pathExtension
            ))
            slideURLs.append(url)
        }
        guard !slides.isEmpty else { return }
        nodes.append(.slideshow(name: show.name, slides: slides))
        sources.append(contentsOf: slideURLs)
    }

    @MainActor
    private static func mediaTitle(forId id: String) -> String {
        if let custom = MediaTitleStore.title(forId: id) { return custom }
        if let name = TVLibraryStore.shared.items.first(where: { $0.id == id })?.name {
            let base = (name as NSString).deletingPathExtension
            return base.isEmpty ? name : base
        }
        let base = (id as NSString).deletingPathExtension
        return base.isEmpty ? id : base
    }
}
