//
//  CloudKitAvailability.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import CloudKit
import Foundation

/// Whether this build may construct the app's `CKContainer`.
///
/// `CKContainer(identifier:)` *traps* rather than failing when the identifier is
/// missing from the app's entitlements. The XCTest host is signed without the
/// iCloud capability (CI builds with `CODE_SIGNING_ALLOWED=NO`), so every call
/// has to come through here — one unguarded call site takes the whole process
/// down at launch, before a single test can run.
///
/// Callers degrade instead of crashing: `DisabledSyncBackend` stands in for the
/// sync engine, and `ShowLiveSession` leaves `userHash` nil, which already
/// disables director advertising and operator browsing.
enum CloudKitAvailability {

    /// True when a container can be built for `CloudKitSchema.containerIdentifier`.
    static var isAvailable: Bool { !isRunningUnitTests }

    /// The app's container, or nil where CloudKit cannot be reached.
    static func container() -> CKContainer? {
        guard isAvailable else { return nil }
        return CKContainer(identifier: CloudKitSchema.containerIdentifier)
    }

    /// The XCTest host runs unentitled, so it must never touch CloudKit.
    private static var isRunningUnitTests: Bool {
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
    }
}
