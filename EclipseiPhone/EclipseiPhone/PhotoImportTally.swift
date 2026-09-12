//
//  PhotoImportTally.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import Foundation

/// Running counts for one Photos import, and the copy that reports them.
///
/// An asset stuck in iCloud and an asset we rejected are different outcomes with
/// different remedies, so they are counted separately: "skipped" means we read the
/// media and said no (wrong type for a Slideshow, too large, too low-resolution),
/// while "not downloaded" means the user can reconnect and get it.
struct PhotoImportTally: Equatable {
    /// Picks that made it into the library.
    var added = 0
    /// Picks whose original never came down from iCloud.
    var iCloudFailures = 0
    /// Picks we read and declined.
    var skipped = 0
    /// True when the user stopped the import partway.
    var wasCancelled = false

    /// Files anything but an add into the matching bucket.
    mutating func record(_ failure: PhotoImportFailure) {
        switch failure {
        case .iCloudDownload: iCloudFailures += 1
        case .cancelled: wasCancelled = true
        case .unreadable: skipped += 1
        }
    }

    /// Adds another phase's counts to this one.
    mutating func merge(_ other: PhotoImportTally) {
        added += other.added
        iCloudFailures += other.iCloudFailures
        skipped += other.skipped
        wasCancelled = wasCancelled || other.wasCancelled
    }
}

// MARK: - Copy

extension PhotoImportTally {

    /// Status line for a finished library / Show import.
    var statusMessage: String {
        if wasCancelled {
            return added == 0 ? "Import stopped" : "Stopped — added \(added)"
        }
        guard added > 0 else {
            return iCloudFailures > 0
                ? "Couldn't download from iCloud"
                : "Couldn't import selection"
        }
        let shortfall = shortfallClause
        return shortfall.isEmpty ? "Added \(added)" : "Added \(added), \(shortfall)"
    }

    /// Status line when not one slide came down, so there was nothing to build.
    var slideshowFailureMessage: String {
        if wasCancelled { return "Slideshow cancelled" }
        return iCloudFailures > 0
            ? "Couldn't download from iCloud"
            : "Couldn't create Slideshow"
    }

    /// Status line once a Slideshow has been created from the batch.
    var slideshowMessage: String {
        let shortfall = shortfallClause
        return shortfall.isEmpty
            ? "Slideshow created"
            : "Slideshow created, \(shortfall)"
    }

    /// "2 not downloaded, 1 skipped" — empty when everything landed.
    private var shortfallClause: String {
        var parts: [String] = []
        if iCloudFailures > 0 { parts.append("\(iCloudFailures) not downloaded") }
        if skipped > 0 { parts.append("\(skipped) skipped") }
        return parts.joined(separator: ", ")
    }

    /// Alert body offered with a Retry when originals were left in iCloud.
    var iCloudRetryMessage: String {
        let subject = iCloudFailures == 1
            ? "One item hasn't"
            : "\(iCloudFailures) items haven't"
        return """
        \(subject) finished downloading from iCloud, so \
        \(iCloudFailures == 1 ? "it was" : "they were") left out. \
        Check your connection and try again.
        """
    }
}

// MARK: - In-flight copy

/// Titles for the import progress overlay.
enum PhotoImportProgressCopy {

    /// Title while picks are being downloaded and prepared.
    ///
    /// The overlay is only revealed once the work outlasts a short delay, so by
    /// the time a single-item title is read there is a real wait to explain —
    /// naming iCloud is the useful part of that explanation.
    ///
    /// - Parameters:
    ///   - completed: Picks finished so far.
    ///   - total: Picks in the batch.
    static func title(completed: Int, total: Int) -> String {
        guard total > 1 else { return "Downloading from iCloud…" }
        let current = min(completed + 1, total)
        return "Importing \(current) of \(total)…"
    }

    /// Title shown between a Cancel tap and the downloads actually unwinding.
    static let stopping = "Stopping…"
}
