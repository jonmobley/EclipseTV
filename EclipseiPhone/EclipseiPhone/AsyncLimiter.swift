//
//  AsyncLimiter.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import Foundation

/// Lets at most `limit` async jobs run at once; the rest wait their turn in order.
///
/// Used for video poster frames: each one decodes video, so running them all at once
/// thrashes the decoder, but running them one by one on the thumbnail queue made every
/// photo thumbnail wait behind them.
actor AsyncLimiter {
    private let limit: Int
    private var running = 0
    private var waiters: [CheckedContinuation<Void, Never>] = []

    init(limit: Int) {
        precondition(limit > 0)
        self.limit = limit
    }

    /// Jobs running now (for tests).
    var runningCount: Int { running }

    /// Runs `job` once a slot is free.
    func run<T>(_ job: () async -> T) async -> T {
        await acquire()
        let result = await job()
        release()
        return result
    }

    private func acquire() async {
        if running < limit {
            running += 1
            return
        }
        await withCheckedContinuation { waiters.append($0) }
    }

    private func release() {
        if waiters.isEmpty {
            running -= 1
        } else {
            // Hand the slot straight to the next waiter; `running` stays the same.
            waiters.removeFirst().resume()
        }
    }
}
