//
//  PhotoImportFailure.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import Foundation

/// Why a Photos pick never became a usable local file.
///
/// `PHPickerViewController` hands back an `NSItemProvider`, not the asset. With
/// iCloud Photos and Optimize iPhone Storage the original can live only in iCloud
/// while the picker grid shows a local thumbnail, so loading the provider may have
/// to pull the full-resolution file over the network first. That download is the
/// one failure the user can act on — reconnect and try again — so it is reported
/// separately from media we looked at and declined.
enum PhotoImportFailure: Error, Equatable {
    /// The original had to come from iCloud and the download did not finish.
    case iCloudDownload
    /// The user stopped the import.
    case cancelled
    /// The asset arrived but is not media we can use.
    case unreadable
}

// MARK: - Classification

extension PhotoImportFailure {

    /// `PHPhotosError.Code.networkAccessRequired`, spelled numerically so this
    /// type stays Foundation-only.
    private static let networkAccessRequiredCode = 3164

    /// Maps an `NSItemProvider` load error onto the reason shown to the user.
    ///
    /// Cancellation is checked across the whole chain before the network domains,
    /// because cancelling an in-flight iCloud fetch reports both.
    static func classify(_ error: Error?) -> PhotoImportFailure {
        guard let error else { return .unreadable }
        if error is CancellationError { return .cancelled }
        let chain = errorChain(from: error as NSError)
        if chain.contains(where: isCancellation) { return .cancelled }
        if chain.contains(where: isNetwork) { return .iCloudDownload }
        return .unreadable
    }

    private static func isCancellation(_ error: NSError) -> Bool {
        error.domain == NSCocoaErrorDomain && error.code == NSUserCancelledError
    }

    /// Domains that mean the bytes were supposed to arrive over the network.
    private static func isNetwork(_ error: NSError) -> Bool {
        if error.domain == NSURLErrorDomain { return true }
        // Photos' own iCloud transfer failures, e.g. CloudPhotoLibraryErrorDomain 82.
        if error.domain.contains("CloudPhotoLibrary") { return true }
        if error.domain == "PHPhotosErrorDomain" {
            return error.code == networkAccessRequiredCode
        }
        return false
    }

    /// The error plus every error nested under it.
    ///
    /// Photos reports the interesting domain a level or two down: the outer error
    /// is a generic "couldn't read the file" and the iCloud transfer failure is
    /// wrapped inside it.
    private static func errorChain(from error: NSError, limit: Int = 8) -> [NSError] {
        var chain: [NSError] = []
        var current: NSError? = error
        while let next = current, chain.count < limit {
            guard !chain.contains(where: { $0 === next }) else { break }
            chain.append(next)
            current = next.userInfo[NSUnderlyingErrorKey] as? NSError
        }
        return chain
    }
}

// MARK: - Copy

extension PhotoImportFailure {

    /// Alert title for a single failed pick.
    var alertTitle: String {
        switch self {
        case .iCloudDownload: return "Still in iCloud"
        case .cancelled: return "Import Stopped"
        case .unreadable: return "Couldn't Add Media"
        }
    }

    /// Alert body for a single failed pick.
    ///
    /// - Parameter noun: What the user picked ("image", "video", "media").
    func message(noun: String) -> String {
        switch self {
        case .iCloudDownload:
            return """
            That \(noun) hasn't finished downloading from iCloud. \
            Check your connection and try again.
            """
        case .cancelled:
            return "The download was stopped before the \(noun) finished."
        case .unreadable:
            return "Could not load the selected \(noun). Please try again."
        }
    }

    /// True when trying again could plausibly succeed.
    var isWorthRetrying: Bool {
        self == .iCloudDownload
    }
}
