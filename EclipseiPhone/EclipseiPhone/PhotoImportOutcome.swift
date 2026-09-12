//
//  PhotoImportOutcome.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import PhotosUI
import UIKit

/// One Photos pick, tagged with where it sat in the selection.
///
/// Downloads finish out of order — a small still beats a 4K movie every time —
/// so the position travels with the pick and the library add order is restored
/// from it once everything has landed.
struct PhotoImportPick {
    let index: Int
    let result: PHPickerResult
}

/// A pick that finished downloading and is ready to be added to the library.
struct PhotoImportPrepared {
    let index: Int
    let localURL: URL
    let isVideo: Bool
    let thumbnail: UIImage?
    let duration: Double
}

/// What a download phase produced: the files, the counts, and which picks are
/// still sitting in iCloud.
struct PhotoImportOutcome {
    /// Files ready to add, in no particular order.
    var prepared: [PhotoImportPrepared] = []
    /// Counts for the status line.
    var tally = PhotoImportTally()
    /// Selection positions worth another attempt, so Try Again can re-run only
    /// those. Positions rather than picks: they survive being merged between
    /// phases and keep this type free of Photos.
    var retryableIndexes: [Int] = []

    /// Files one pick's result into the right bucket.
    mutating func record(
        _ result: Result<PhotoImportPrepared, PhotoImportFailure>,
        at index: Int
    ) {
        switch result {
        case .success(let prepared):
            self.prepared.append(prepared)
        case .failure(let failure):
            tally.record(failure)
            if failure.isWorthRetrying {
                retryableIndexes.append(index)
            }
        }
    }

    /// Folds another phase's results into this one.
    mutating func merge(_ other: PhotoImportOutcome) {
        prepared.append(contentsOf: other.prepared)
        retryableIndexes.append(contentsOf: other.retryableIndexes)
        tally.merge(other.tally)
    }

    /// Prepared files in the order the user picked them.
    var preparedInPickOrder: [PhotoImportPrepared] {
        prepared.sorted { $0.index < $1.index }
    }
}

/// Collects outcomes from the concurrent still phase.
///
/// Stills download several at a time, and their results are `UIImage`s and file
/// URLs that have no business crossing between tasks. Keeping the accumulator on
/// the main actor means each task hands its result to one owner instead.
@MainActor
final class PhotoImportCollector {
    var outcome = PhotoImportOutcome()

    func record(
        _ result: Result<PhotoImportPrepared, PhotoImportFailure>,
        at index: Int
    ) {
        outcome.record(result, at: index)
    }
}
