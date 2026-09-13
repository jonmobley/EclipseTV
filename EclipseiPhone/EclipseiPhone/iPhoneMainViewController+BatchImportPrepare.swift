//
//  iPhoneMainViewController+BatchImportPrepare.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import UIKit
import PhotosUI

// MARK: - Download & Prepare

extension iPhoneMainViewController {

    /// Stills downloading at once.
    ///
    /// Enough to hide the per-item round trip on a batch of camera-roll photos
    /// without opening so many connections that each one crawls.
    private static let stillDownloadConcurrency = 3

    /// Downloads every pick and writes it to a file the library can take.
    ///
    /// Stills go several at a time; movies go one at a time. A still is a few
    /// megabytes once encoded, but a movie's original can be gigabytes, and three
    /// of those in flight would mean three of them sitting in the temporary
    /// directory at once. Pick order is carried on each result, so splitting the
    /// work into phases is invisible in the finished library.
    func prepareImportPicks(_ picks: [PhotoImportPick]) async -> PhotoImportOutcome {
        let movies = picks.filter { PhotoImportLoader.isMovie($0.result.itemProvider) }
        let stills = picks.filter { !PhotoImportLoader.isMovie($0.result.itemProvider) }
        var outcome = await prepareStillPicks(stills)
        let movieOutcome = await prepareMoviePicks(movies)
        outcome.merge(movieOutcome)
        return outcome
    }

    // MARK: - Phases

    /// Runs the still downloads with at most `stillDownloadConcurrency` in flight,
    /// starting the next one as each finishes.
    private func prepareStillPicks(_ picks: [PhotoImportPick]) async -> PhotoImportOutcome {
        guard !picks.isEmpty else { return PhotoImportOutcome() }
        let collector = PhotoImportCollector()
        var nextToSchedule = 0

        await withTaskGroup(of: Int.self) { group in
            let slots = min(Self.stillDownloadConcurrency, picks.count)
            while nextToSchedule < slots {
                let pick = picks[nextToSchedule]
                group.addTask { @MainActor in
                    collector.record(await self.prepareStill(pick), at: pick.index)
                    return pick.index
                }
                nextToSchedule += 1
            }

            while let finishedIndex = await group.next() {
                photoImportSession.finish(at: finishedIndex)
                guard !photoImportSession.isCancelled,
                      nextToSchedule < picks.count else { continue }
                let pick = picks[nextToSchedule]
                group.addTask { @MainActor in
                    collector.record(await self.prepareStill(pick), at: pick.index)
                    return pick.index
                }
                nextToSchedule += 1
            }
        }

        return collector.outcome
    }

    /// Runs the movie downloads one at a time, stopping early if cancelled.
    private func prepareMoviePicks(_ picks: [PhotoImportPick]) async -> PhotoImportOutcome {
        var outcome = PhotoImportOutcome()
        for pick in picks {
            guard !photoImportSession.isCancelled else { break }
            let result = await prepareMovie(pick)
            outcome.record(result, at: pick.index)
            photoImportSession.finish(at: pick.index)
        }
        return outcome
    }

    // MARK: - Per-pick

    private func prepareStill(
        _ pick: PhotoImportPick
    ) async -> Result<PhotoImportPrepared, PhotoImportFailure> {
        let loaded = await PhotoImportLoader.loadImage(from: pick.result.itemProvider) {
            progress in
            photoImportSession.track(progress, at: pick.index)
        }
        switch loaded {
        case .failure(let failure):
            return .failure(failure)
        case .success(let image):
            guard let still = await Self.writeStill(image) else {
                return .failure(.unreadable)
            }
            return .success(
                PhotoImportPrepared(
                    index: pick.index,
                    localURL: still.url,
                    isVideo: false,
                    thumbnail: still.image,
                    duration: 0
                )
            )
        }
    }

    private func prepareMovie(
        _ pick: PhotoImportPick
    ) async -> Result<PhotoImportPrepared, PhotoImportFailure> {
        let loaded = await PhotoImportLoader.loadMovie(from: pick.result.itemProvider) {
            progress in
            photoImportSession.track(progress, at: pick.index)
        }
        switch loaded {
        case .failure(let failure):
            return .failure(failure)
        case .success(let localURL):
            guard case .valid = await MediaValidator.validateVideo(at: localURL) else {
                cleanupTempFile(at: localURL)
                return .failure(.unreadable)
            }
            return .success(
                PhotoImportPrepared(
                    index: pick.index,
                    localURL: localURL,
                    isVideo: true,
                    thumbnail: await VideoCropExporter.previewFrame(at: localURL),
                    duration: await VideoPosterFrame.durationSeconds(at: localURL)
                )
            )
        }
    }

    /// A downscaled still written to the temporary directory.
    private struct WrittenStill {
        let url: URL
        let image: UIImage
    }

    /// Downscales and encodes off the main thread.
    ///
    /// The import overlay is on screen by this point, so a 4K JPEG encode on the
    /// main thread would stall the progress bar it is supposed to be animating.
    private static func writeStill(_ image: UIImage) async -> WrittenStill? {
        await withCheckedContinuation { (continuation: CheckedContinuation<WrittenStill?, Never>) in
            DispatchQueue.global(qos: .userInitiated).async {
                let optimized = MediaValidator.downscaleImage(image)
                guard let data = optimized.jpegData(compressionQuality: 0.7) else {
                    continuation.resume(returning: nil)
                    return
                }
                let fileURL = FileManager.default.temporaryDirectory
                    .appendingPathComponent("batch_\(UUID().uuidString).jpg")
                do {
                    try data.write(to: fileURL, options: .atomic)
                    continuation.resume(
                        returning: WrittenStill(url: fileURL, image: optimized)
                    )
                } catch {
                    continuation.resume(returning: nil)
                }
            }
        }
    }
}
