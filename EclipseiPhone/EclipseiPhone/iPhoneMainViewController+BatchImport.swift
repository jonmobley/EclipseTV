//
//  iPhoneMainViewController+BatchImport.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import UIKit
import PhotosUI
import UniformTypeIdentifiers

// MARK: - Multi-Select Import (no crop)

extension iPhoneMainViewController {

    /// Ingests multiple Photos picks into the library/Show without crop or confirm UI.
    /// Queues locally, then flushes pending uploads when a TV is connected.
    /// When a Slideshow draft is pending, images become one Slideshow (not Show members).
    func importPickedMediaBatch(_ results: [PHPickerResult]) {
        let albumId = pendingAlbumId
        let slideshowShowId = pendingSlideshowShowId
        let slideshowName = pendingSlideshowName
        pendingAlbumId = nil
        pendingSlideshowShowId = nil
        pendingSlideshowName = nil
        connectionManager.pendingRestoreId = nil

        let makingSlideshow = slideshowShowId != nil && slideshowName != nil
        showTemporaryStatus("Importing \(results.count)…", duration: 120)

        Task { @MainActor in
            var addedIds: [String] = []
            var failed = 0
            for result in results {
                if makingSlideshow {
                    // Slideshows are images-only this phase.
                    if result.itemProvider.hasItemConformingToTypeIdentifier(
                        UTType.movie.identifier
                    ) {
                        failed += 1
                        continue
                    }
                }
                if let id = await importOnePickedResult(
                    result,
                    albumId: makingSlideshow ? nil : albumId
                ) {
                    addedIds.append(id)
                } else {
                    failed += 1
                }
            }

            if isConnected() {
                connectionManager.flushPendingUploads(
                    for: TVLibraryStore.shared.activeLibraryMode
                )
            }

            if makingSlideshow,
               let showId = slideshowShowId,
               let name = slideshowName {
                finishSlideshowImport(
                    name: name,
                    showId: showId,
                    itemIds: addedIds,
                    failed: failed
                )
                return
            }

            let added = addedIds.count
            if added == 0 {
                showTemporaryStatus("Couldn't import selection")
            } else if failed == 0 {
                showTemporaryStatus("Added \(added)")
            } else {
                showTemporaryStatus("Added \(added), \(failed) skipped")
            }
        }
    }

    // MARK: - Slideshow finish

    private func finishSlideshowImport(
        name: String,
        showId: UUID,
        itemIds: [String],
        failed: Int
    ) {
        guard !itemIds.isEmpty else {
            showTemporaryStatus("Couldn't create Slideshow")
            return
        }
        let orientation = LocalAlbumStore.shared.album(id: showId)?.orientation
            ?? ExternalOutputSettings.orientation
        do {
            _ = try SlideshowStore.shared.create(
                name: name,
                showId: showId,
                itemIds: itemIds,
                orientation: orientation
            )
            if failed == 0 {
                showTemporaryStatus("Slideshow created")
            } else {
                showTemporaryStatus("Slideshow created, \(failed) skipped")
            }
        } catch {
            showTemporaryStatus(error.localizedDescription)
        }
    }

    // MARK: - Per-item ingest

    /// Imports one pick. Returns the new library id on success.
    private func importOnePickedResult(
        _ result: PHPickerResult,
        albumId: UUID?
    ) async -> String? {
        let provider = result.itemProvider
        if provider.hasItemConformingToTypeIdentifier(UTType.movie.identifier) {
            return await importPickedVideoSkippingCrop(provider, albumId: albumId)
        }
        if provider.canLoadObject(ofClass: UIImage.self) {
            return await importPickedImageSkippingCrop(provider, albumId: albumId)
        }
        return nil
    }

    private func importPickedImageSkippingCrop(
        _ provider: NSItemProvider,
        albumId: UUID?
    ) async -> String? {
        guard let image = await loadUIImage(from: provider) else { return nil }
        let optimized = MediaValidator.downscaleImage(image)
        guard let data = optimized.jpegData(compressionQuality: 0.7) else { return nil }

        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("batch_\(UUID().uuidString).jpg")
        do {
            try data.write(to: fileURL, options: .atomic)
        } catch {
            return nil
        }

        return addMedia(
            localURL: fileURL,
            isVideo: false,
            thumbnail: optimized,
            duration: 0,
            toAlbumId: albumId,
            sendIfConnected: false
        )
    }

    private func importPickedVideoSkippingCrop(
        _ provider: NSItemProvider,
        albumId: UUID?
    ) async -> String? {
        // Copied inside the PHPicker callback so the file survives after it returns.
        guard let localURL = await loadMovieFileURL(from: provider) else { return nil }

        let validation = await MediaValidator.validateVideo(at: localURL)
        switch validation {
        case .invalid:
            cleanupTempFile(at: localURL)
            return nil
        case .valid:
            break
        }

        let thumbnail = await VideoCropExporter.previewFrame(at: localURL)
        if let thumbnail {
            saveCustomThumbnail(thumbnail, for: localURL)
        }

        return addMedia(
            localURL: localURL,
            isVideo: true,
            thumbnail: thumbnail,
            duration: 0,
            toAlbumId: albumId,
            sendIfConnected: false
        )
    }

    // MARK: - NSItemProvider helpers

    private func loadUIImage(from provider: NSItemProvider) async -> UIImage? {
        await withCheckedContinuation { continuation in
            provider.loadObject(ofClass: UIImage.self) { object, _ in
                continuation.resume(returning: object as? UIImage)
            }
        }
    }

    /// Copies the movie out of PHPicker's ephemeral location before the callback returns.
    private func loadMovieFileURL(from provider: NSItemProvider) async -> URL? {
        await withCheckedContinuation { continuation in
            provider.loadFileRepresentation(
                forTypeIdentifier: UTType.movie.identifier
            ) { url, _ in
                guard let url else {
                    continuation.resume(returning: nil)
                    return
                }
                continuation.resume(returning: Self.copyTemporaryMovie(from: url))
            }
        }
    }

    private static func copyTemporaryMovie(from sourceURL: URL) -> URL? {
        let ext = sourceURL.pathExtension.isEmpty ? "mov" : sourceURL.pathExtension
        let destination = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension(ext)
        do {
            if FileManager.default.fileExists(atPath: destination.path) {
                try FileManager.default.removeItem(at: destination)
            }
            try FileManager.default.copyItem(at: sourceURL, to: destination)
            return destination
        } catch {
            return nil
        }
    }
}
