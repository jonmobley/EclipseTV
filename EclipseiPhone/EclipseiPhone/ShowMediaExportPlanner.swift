//
//  ShowMediaExportPlanner.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import Foundation

/// Pure layout of numbered relative paths for a Show media export.
///
/// Walks exportable surface nodes in Show grid order. Slideshows become nested
/// folders; media and PDFs become numbered files. Tools, websites, countdowns,
/// and Live Polls are never passed in.
enum ShowMediaExportPlanner {

    /// One exportable Show-grid tile (already filtered).
    enum Node: Equatable {
        case file(title: String, pathExtension: String)
        case slideshow(name: String, slides: [Slide])

        /// One slide inside a slideshow folder.
        struct Slide: Equatable {
            let title: String
            let pathExtension: String
        }
    }

    /// A file to copy into the archive, with its path relative to the Show root.
    struct PlannedFile: Equatable {
        let relativePath: String
        /// Index into the parallel source list the caller keeps.
        let sourceIndex: Int
    }

    /// Builds numbered relative paths for `nodes` in order.
    ///
    /// `sourceIndex` matches the order of leaf files when walking nodes
    /// depth-first (slideshow slides nested under their folder).
    static func plan(nodes: [Node]) -> [PlannedFile] {
        guard !nodes.isEmpty else { return [] }
        var files: [PlannedFile] = []
        var sourceIndex = 0
        for (offset, node) in nodes.enumerated() {
            let index = offset + 1
            switch node {
            case .file(let title, let pathExtension):
                let base = ExportFileName.numbered(
                    title, index: index, totalCount: nodes.count
                )
                let name = ExportFileName.fileName(
                    base: base, pathExtension: pathExtension
                )
                files.append(PlannedFile(relativePath: name, sourceIndex: sourceIndex))
                sourceIndex += 1
            case .slideshow(let name, let slides):
                let folder = ExportFileName.numbered(
                    name, index: index, totalCount: nodes.count
                )
                for (slideOffset, slide) in slides.enumerated() {
                    let slideBase = ExportFileName.numbered(
                        slide.title,
                        index: slideOffset + 1,
                        totalCount: slides.count
                    )
                    let fileName = ExportFileName.fileName(
                        base: slideBase, pathExtension: slide.pathExtension
                    )
                    let path = "\(folder)/\(fileName)"
                    files.append(
                        PlannedFile(relativePath: path, sourceIndex: sourceIndex)
                    )
                    sourceIndex += 1
                }
            }
        }
        return files
    }
}
