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

    @Test func scrubKeepsTheCrashTypeAndDropsAllFreeText() throws {
        let event = Event(level: .error)
        event.user = User(userId: "someone")
        event.message = SentryMessage(formatted: "Spring Recital")
        event.extra = ["show": "Spring Recital"]
        event.tags = ["show": "Spring Recital"]
        let crumb = Breadcrumb(level: .info, category: "ui")
        crumb.message = "Opened Spring Recital"
        crumb.data = ["title": "Spring Recital"]
        event.breadcrumbs = [crumb]
        event.context = [
            "device": ["name": "Jo's iPhone", "model": "iPhone18,1"],
            "app": ["device_app_hash": "abc123", "app_version": "1.0"],
            "culture": ["timezone": "America/Indiana/Indianapolis"]
        ]
        let exception = Exception(value: "cannot open /var/mobile/Spring Recital.mov", type: "NSException")
        let mechanism = Mechanism(type: "signal")
        mechanism.data = ["reason": "Spring Recital"]
        mechanism.desc = "Spring Recital"
        exception.mechanism = mechanism
        event.exceptions = [exception]

        let scrubbed = try #require(CrashReporting.scrub(event))

        #expect(scrubbed.user?.userId == nil)
        #expect(scrubbed.user?.ipAddress == "0.0.0.0")
        #expect(scrubbed.message == nil)
        #expect(scrubbed.extra == nil)
        #expect(scrubbed.tags == nil)
        #expect(scrubbed.breadcrumbs == nil)
        #expect(scrubbed.context?["device"]?["name"] == nil)
        #expect(scrubbed.context?["device"]?["model"] as? String == "iPhone18,1")
        #expect(scrubbed.context?["app"]?["device_app_hash"] == nil)
        #expect(scrubbed.context?["app"]?["app_version"] as? String == "1.0")
        #expect(scrubbed.context?["culture"] == nil)
        #expect(scrubbed.exceptions?.first?.type == "NSException")
        #expect(scrubbed.exceptions?.first?.value == nil)
        #expect(scrubbed.exceptions?.first?.mechanism?.data == nil)
        #expect(scrubbed.exceptions?.first?.mechanism?.desc == nil)
    }
}
