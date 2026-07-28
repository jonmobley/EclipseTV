//
//  ImageStorage.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import Foundation
import os.log

class ImageStorage {
    // MARK: - Singleton

    static let shared = ImageStorage()

    // MARK: - Properties

    private let fileManager = FileManager.default
    private let logger = Logger(subsystem: "com.eclipsetv.app", category: "ImageStorage")

    /// Location for user media. On tvOS, Caches is the reliable writable location and
    /// is durable in practice (only purged under genuine storage pressure). This was the
    /// app's original, working location; a later move to Application Support broke saving
    /// on tvOS. Note: for guaranteed persistence Apple's intended option is iCloud/CloudKit.
    private let mediaRootDirectory: URL

    // MARK: - Initialization

    private init() {
        let baseDirectory = fileManager.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        mediaRootDirectory = baseDirectory.appendingPathComponent("Media", isDirectory: true)
        createDirectory(at: mediaRootDirectory)
        migrateLegacyFlatFilesIfNeeded()
        for mode in EclipseShareProtocol.LibraryMode.allCases {
            createDirectory(at: directory(for: mode))
        }
    }

    // MARK: - Directory Management

    /// Root `Caches/Media` directory (contains Landscape / Vertical subdirs).
    func getMediaRootDirectory() -> URL {
        mediaRootDirectory
    }

    /// Mode-scoped media directory (`Caches/Media/Landscape` or `…/Vertical`).
    func getImagesDirectory(
        for mode: EclipseShareProtocol.LibraryMode = MediaDataSource.shared.activeLibraryMode
    ) -> URL {
        directory(for: mode)
    }

    private func directory(for mode: EclipseShareProtocol.LibraryMode) -> URL {
        mediaRootDirectory.appendingPathComponent(mode.directoryName, isDirectory: true)
    }

    @discardableResult
    func createImagesDirectory(
        for mode: EclipseShareProtocol.LibraryMode = MediaDataSource.shared.activeLibraryMode
    ) -> Bool {
        createDirectory(at: directory(for: mode))
    }

    @discardableResult
    private func createDirectory(at url: URL) -> Bool {
        do {
            try fileManager.createDirectory(at: url,
                                            withIntermediateDirectories: true,
                                            attributes: nil)
            return true
        } catch {
            logger.error("Error creating directory: \(error.localizedDescription)")
            return false
        }
    }

    /// Moves loose files that lived directly under `Caches/Media` into `Landscape/`.
    private func migrateLegacyFlatFilesIfNeeded() {
        guard let contents = try? fileManager.contentsOfDirectory(
            at: mediaRootDirectory,
            includingPropertiesForKeys: [.isDirectoryKey]
        ) else { return }

        let landscape = directory(for: .landscape)
        createDirectory(at: landscape)

        for url in contents {
            let isDir = (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
            if isDir { continue }
            let dest = landscape.appendingPathComponent(url.lastPathComponent)
            if fileManager.fileExists(atPath: dest.path) {
                try? fileManager.removeItem(at: url)
                continue
            }
            do {
                try fileManager.moveItem(at: url, to: dest)
                logger.info("Migrated media file to Landscape: \(url.lastPathComponent, privacy: .public)")
            } catch {
                logger.error("Failed to migrate \(url.lastPathComponent, privacy: .public): \(error.localizedDescription)")
            }
        }
    }

    // MARK: - Image Management

    func saveReceivedImage(_ imageData: Data) -> URL? {
        let mode = MediaDataSource.shared.activeLibraryMode
        guard createImagesDirectory(for: mode) else { return nil }

        let filename = "\(UUID().uuidString).jpg"
        let fileURL = getImagesDirectory(for: mode).appendingPathComponent(filename)

        do {
            try imageData.write(to: fileURL, options: [.atomic])
            logger.info("Saved image to: \(fileURL.path)")
            return fileURL
        } catch {
            logger.error("Error saving image: \(error.localizedDescription)")
            return nil
        }
    }

    func saveSampleImage(_ imageData: Data, name: String) -> URL? {
        let mode = MediaDataSource.shared.activeLibraryMode
        guard createImagesDirectory(for: mode) else { return nil }

        let filename = "sample_\(name).jpg"
        let fileURL = getImagesDirectory(for: mode).appendingPathComponent(filename)

        if !fileManager.fileExists(atPath: fileURL.path) {
            do {
                try imageData.write(to: fileURL, options: [.atomic])
                logger.info("Saved sample image to: \(fileURL.path)")
                return fileURL
            } catch {
                logger.error("Error saving sample image: \(error.localizedDescription)")
                return nil
            }
        }

        return fileURL
    }

    // MARK: - Video Management

    func saveReceivedVideo(_ videoData: Data) -> URL? {
        let mode = MediaDataSource.shared.activeLibraryMode
        guard createImagesDirectory(for: mode) else { return nil }

        let filename = "\(UUID().uuidString).mp4"
        let fileURL = getImagesDirectory(for: mode).appendingPathComponent(filename)

        do {
            try videoData.write(to: fileURL, options: [.atomic])
            logger.info("Saved video to: \(fileURL.path)")
            return fileURL
        } catch {
            logger.error("Error saving video: \(error.localizedDescription)")
            return nil
        }
    }

    // MARK: - Cleanup

    /// Removes files under each mode directory that no library bucket references.
    func cleanupOrphanedFiles(keeping referencedPaths: [String]) {
        let referencedNamesByMode: [EclipseShareProtocol.LibraryMode: Set<String>] = {
            var map: [EclipseShareProtocol.LibraryMode: Set<String>] = [
                .landscape: [], .vertical: []
            ]
            for path in referencedPaths {
                let name = (path as NSString).lastPathComponent
                if path.contains("/Vertical/") {
                    map[.vertical, default: []].insert(name)
                } else {
                    map[.landscape, default: []].insert(name)
                }
            }
            return map
        }()

        DispatchQueue.global(qos: .utility).async { [logger, mediaRootDirectory] in
            let fm = FileManager.default
            for mode in EclipseShareProtocol.LibraryMode.allCases {
                let dir = mediaRootDirectory.appendingPathComponent(
                    mode.directoryName, isDirectory: true
                )
                let keep = referencedNamesByMode[mode] ?? []
                guard let files = try? fm.contentsOfDirectory(
                    at: dir, includingPropertiesForKeys: nil
                ) else { continue }
                for fileURL in files where !keep.contains(fileURL.lastPathComponent) {
                    do {
                        try fm.removeItem(at: fileURL)
                        logger.info(
                            "Removed orphaned media file: \(fileURL.lastPathComponent, privacy: .public)"
                        )
                    } catch {
                        logger.error("Failed to remove orphaned file: \(error.localizedDescription)")
                    }
                }
            }
        }
    }

    // MARK: - File Operations

    func fileExists(at path: String) -> Bool {
        fileManager.fileExists(atPath: path)
    }

    func getDirectoryContents(
        for mode: EclipseShareProtocol.LibraryMode = MediaDataSource.shared.activeLibraryMode
    ) -> [URL]? {
        let imagesDir = getImagesDirectory(for: mode)
        do {
            return try fileManager.contentsOfDirectory(
                at: imagesDir,
                includingPropertiesForKeys: [.creationDateKey]
            )
        } catch {
            logger.error("Error getting directory contents: \(error.localizedDescription)")
            return nil
        }
    }

    func removeFile(at url: URL) -> Bool {
        do {
            try fileManager.removeItem(at: url)
            logger.info("Removed file: \(url.lastPathComponent)")
            return true
        } catch {
            logger.error("Error removing file: \(error.localizedDescription)")
            return false
        }
    }
}
