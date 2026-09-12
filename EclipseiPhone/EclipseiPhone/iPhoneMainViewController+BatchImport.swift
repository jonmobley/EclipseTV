//
//  iPhoneMainViewController+BatchImport.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import UIKit
import PhotosUI

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

        Task { @MainActor in
            await runImport(
                results,
                albumId: albumId,
                slideshowShowId: slideshowShowId,
                slideshowName: slideshowName
            )
        }
    }

    /// Downloads the picks, then adds them in the order they were picked.
    ///
    /// Download and ingest are separate passes because a pick's original may have
    /// to come from iCloud: those arrive out of order and some never arrive at
    /// all, so the library add waits until the files are on disk.
    private func runImport(
        _ results: [PHPickerResult],
        albumId: UUID?,
        slideshowShowId: UUID?,
        slideshowName: String?
    ) async {
        let makingSlideshow = slideshowShowId != nil && slideshowName != nil
        var outcome = PhotoImportOutcome()
        let picks = eligiblePicks(
            from: results,
            imagesOnly: makingSlideshow,
            tally: &outcome.tally
        )
        guard !picks.isEmpty else {
            showTemporaryStatus(outcome.tally.statusMessage)
            return
        }

        beginImportProgress(count: picks.count)
        let downloaded = await prepareImportPicks(picks)
        outcome.merge(downloaded)
        // Picks the user stopped before they were scheduled leave no failure of
        // their own, so the session is the authority on whether this was cut short.
        outcome.tally.wasCancelled = outcome.tally.wasCancelled
            || photoImportSession.isCancelled
        endImportProgress()

        let addedIds = ingest(
            outcome.preparedInPickOrder,
            albumId: makingSlideshow ? nil : albumId,
            ownerShowId: makingSlideshow ? slideshowShowId : nil
        )
        outcome.tally.added = addedIds.count

        if isConnected() {
            connectionManager.flushPendingUploads(
                for: TVLibraryStore.shared.activeLibraryMode
            )
        }

        reportImport(
            outcome,
            from: results,
            addedIds: addedIds,
            albumId: albumId,
            slideshowShowId: slideshowShowId,
            slideshowName: slideshowName
        )
    }

    /// Reports what landed, builds the Slideshow if one was asked for, and offers
    /// another attempt at anything left in iCloud.
    private func reportImport(
        _ outcome: PhotoImportOutcome,
        from results: [PHPickerResult],
        addedIds: [String],
        albumId: UUID?,
        slideshowShowId: UUID?,
        slideshowName: String?
    ) {
        if let showId = slideshowShowId, let name = slideshowName {
            finishSlideshowImport(
                name: name,
                showId: showId,
                itemIds: addedIds,
                tally: outcome.tally
            )
        } else {
            showTemporaryStatus(outcome.tally.statusMessage)
        }

        offerICloudRetry(
            outcome,
            from: results,
            addedIds: addedIds,
            albumId: albumId,
            slideshowShowId: slideshowShowId,
            slideshowName: slideshowName
        )
    }

    // MARK: - Selection

    /// Drops picks we can rule out before paying for a download.
    ///
    /// - Parameters:
    ///   - imagesOnly: Slideshows take images only this phase, so a picked movie
    ///     is skipped here rather than downloaded and then discarded.
    ///   - tally: Receives the skips.
    private func eligiblePicks(
        from results: [PHPickerResult],
        imagesOnly: Bool,
        tally: inout PhotoImportTally
    ) -> [PhotoImportPick] {
        var picks: [PhotoImportPick] = []
        for (index, result) in results.enumerated() {
            let provider = result.itemProvider
            let isMovie = PhotoImportLoader.isMovie(provider)
            guard isMovie || PhotoImportLoader.isImage(provider) else {
                tally.skipped += 1
                continue
            }
            if imagesOnly, isMovie {
                tally.skipped += 1
                continue
            }
            picks.append(PhotoImportPick(index: index, result: result))
        }
        return picks
    }

    // MARK: - Ingest

    /// Adds downloaded files to the library, keeping the user's pick order.
    private func ingest(
        _ prepared: [PhotoImportPrepared],
        albumId: UUID?,
        ownerShowId: UUID?
    ) -> [String] {
        prepared.map { pick in
            if pick.isVideo, let thumbnail = pick.thumbnail {
                saveCustomThumbnail(thumbnail, for: pick.localURL)
            }
            return addMedia(
                localURL: pick.localURL,
                isVideo: pick.isVideo,
                thumbnail: pick.thumbnail,
                duration: pick.duration,
                toAlbumId: albumId,
                sendIfConnected: false,
                ownerShowId: ownerShowId
            )
        }
    }

    // MARK: - Slideshow finish

    private func finishSlideshowImport(
        name: String,
        showId: UUID,
        itemIds: [String],
        tally: PhotoImportTally
    ) {
        guard !itemIds.isEmpty else {
            showTemporaryStatus(tally.slideshowFailureMessage)
            return
        }
        let orientation = LocalAlbumStore.shared.album(id: showId)?.orientation
            ?? ExternalOutputSettings.orientation
        do {
            let created = try SlideshowStore.shared.create(
                name: name,
                showId: showId,
                itemIds: itemIds,
                orientation: orientation
            )
            libraryViewController.revealAddedShowMember(
                id: ShowSlideshowToken.token(for: created.id)
            )
            showTemporaryStatus(tally.slideshowMessage)
        } catch {
            showTemporaryStatus(error.localizedDescription)
        }
    }

    // MARK: - Retry

    /// Offers another attempt at the picks whose originals never left iCloud.
    ///
    /// A Slideshow that already exists is left alone: re-running the import would
    /// build a second one beside it instead of filling in its gaps. When nothing
    /// was created there is nothing to collide with, so retrying rebuilds it whole.
    private func offerICloudRetry(
        _ outcome: PhotoImportOutcome,
        from results: [PHPickerResult],
        addedIds: [String],
        albumId: UUID?,
        slideshowShowId: UUID?,
        slideshowName: String?
    ) {
        guard !outcome.tally.wasCancelled else { return }
        if slideshowShowId != nil, !addedIds.isEmpty { return }

        let retryable: [PHPickerResult] = outcome.retryableIndexes.compactMap { index in
            guard results.indices.contains(index) else { return nil }
            return results[index]
        }
        guard !retryable.isEmpty else { return }
        presentICloudRetry(message: outcome.tally.iCloudRetryMessage) { [weak self] in
            guard let self else { return }
            self.pendingAlbumId = albumId
            self.pendingSlideshowShowId = slideshowShowId
            self.pendingSlideshowName = slideshowName
            self.importPickedMediaBatch(retryable)
        }
    }
}
