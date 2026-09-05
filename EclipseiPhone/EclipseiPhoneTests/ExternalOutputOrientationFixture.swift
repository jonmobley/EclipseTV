//
//  ExternalOutputOrientationFixture.swift
//  EclipseiPhoneTests
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import Foundation
@testable import EclipseiPhone

/// Serializes tests that set the process-global `ExternalOutputSettings.orientation`.
///
/// Swift Testing runs suites in parallel and `.serialized` only orders tests inside
/// one suite, so two suites that each set-then-restore the orientation used to
/// clobber each other and fail at random. Every writer goes through here, and the
/// fixture is main-actor bound: synchronous main-actor test bodies run one at a
/// time, so writers can never interleave with each other or with main-actor
/// readers. Do not `await` inside `body`.
///
/// A lock would not do: the setter posts `didChangeNotification`, whose observers
/// hop to the main thread, so a background writer holding a lock while a main-actor
/// test waited on it deadlocked the whole run.
@MainActor
enum ExternalOutputOrientationFixture {

    /// Runs `body` with `orientation` applied, restoring the previous value after.
    static func with<T>(
        _ orientation: ExternalOutputOrientation,
        _ body: () throws -> T
    ) rethrows -> T {
        let previous = ExternalOutputSettings.orientation
        defer { ExternalOutputSettings.orientation = previous }
        ExternalOutputSettings.orientation = orientation
        return try body()
    }

    /// Like `with(_:_:)` for tests that switch orientation more than once; `set`
    /// changes it and the original is restored afterwards.
    static func withSwitching<T>(
        _ body: (_ set: (ExternalOutputOrientation) -> Void) throws -> T
    ) rethrows -> T {
        let previous = ExternalOutputSettings.orientation
        defer { ExternalOutputSettings.orientation = previous }
        return try body { ExternalOutputSettings.orientation = $0 }
    }
}
