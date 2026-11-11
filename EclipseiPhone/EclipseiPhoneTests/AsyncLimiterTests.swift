//
//  AsyncLimiterTests.swift
//  EclipseiPhoneTests
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import Foundation
import Testing
@testable import EclipseiPhone

struct AsyncLimiterTests {

    /// Counts how many jobs overlap.
    private actor Gauge {
        private(set) var current = 0
        private(set) var peak = 0
        func enter() { current += 1; peak = max(peak, current) }
        func leave() { current -= 1 }
    }

    @Test func neverRunsMoreThanTheLimit() async {
        let limiter = AsyncLimiter(limit: 2)
        let gauge = Gauge()
        await withTaskGroup(of: Void.self) { group in
            for _ in 0..<8 {
                group.addTask {
                    await limiter.run {
                        await gauge.enter()
                        try? await Task.sleep(nanoseconds: 20_000_000)
                        await gauge.leave()
                    }
                }
            }
        }
        #expect(await gauge.peak <= 2)
        #expect(await gauge.peak >= 1)
        #expect(await limiter.runningCount == 0)
    }

    @Test func returnsTheJobsResult() async {
        let limiter = AsyncLimiter(limit: 1)
        let value = await limiter.run { 42 }
        #expect(value == 42)
    }
}

@MainActor
struct ThumbnailRetryDelayTests {

    @Test func lastRetryWaitsForSlowCopies() {
        #expect(TVLibraryStore.thumbnailRetryDelay(attempt: 1) == 0.35)
        #expect(TVLibraryStore.thumbnailRetryDelay(attempt: 2) == 0.7)
        #expect(TVLibraryStore.thumbnailRetryDelay(attempt: 3) == 2.0)
    }
}
