//
//  CrashReportingTests.swift
//  EclipseiPhoneTests
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import Sentry
import Testing
@testable import EclipseiPhone

struct CrashReportingTests {

    @Test func redactRemovesLinksAndPaths() {
        let text = "Failed https://example.com/show?id=1 at /var/mobile/Containers/Spring Recital"
        let redacted = CrashReporting.redact(text)
        #expect(!redacted.contains("example.com"))
        #expect(!redacted.contains("/var/mobile"))
        #expect(redacted.hasPrefix("Failed <url> at <path>"))
    }

    @Test func redactKeepsPlainMessages() {
        #expect(CrashReporting.redact("Index out of range") == "Index out of range")
    }

    @Test func scrubDropsUserAndSensitiveBreadcrumbs() throws {
        let event = Event(level: .error)
        event.user = User(userId: "someone")
        let safe = Breadcrumb(level: .info, category: "ui")
        safe.message = "Opened settings"
        let unsafe = Breadcrumb(level: .info, category: "ui")
        unsafe.message = "Loaded https://example.com/a"
        event.breadcrumbs = [safe, unsafe]
        let scrubbed = try #require(CrashReporting.scrub(event))
        #expect(scrubbed.user == nil)
        #expect(scrubbed.breadcrumbs?.map(\.message) == ["Opened settings"])
    }
}
