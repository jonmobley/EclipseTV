//
//  CrashReporting.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import Foundation
import Sentry

/// Sends crash and freeze reports to Sentry. Nothing else: no analytics, no
/// screenshots, no activity trail, and no free text. A report keeps the crash
/// type, where in the code it happened, and basic device details.
///
/// Off in Debug builds and tests, so development never reaches the project.
enum CrashReporting {

    private static let dsn = "https://d3bf97e4fb55eb32dc46b2141f09b4dd@o4509495047159808.ingest.us.sentry.io/4512354585542656"

    static func start() {
        #if !DEBUG
        guard ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil else { return }
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "unknown"
        let build = info?["CFBundleVersion"] as? String ?? "0"
        SentrySDK.start { options in
            options.dsn = dsn
            options.releaseName = "Eclipse-AppleTV@\(version)+\(build)"
            options.dist = build
            options.environment = isTestFlight ? "testflight" : "production"
            options.sendDefaultPii = false
            options.enableAutoPerformanceTracing = false
            options.enableAutoBreadcrumbTracking = false
            options.enableNetworkBreadcrumbs = false
            options.enableCaptureFailedRequests = false
            options.attachStacktrace = true
            options.beforeSend = { scrub($0) }
        }
        #endif
    }

    private static var isTestFlight: Bool {
        Bundle.main.appStoreReceiptURL?.lastPathComponent == "sandboxReceipt"
    }

    /// Keeps only known-safe fields. Exception and log text can quote file names,
    /// links and note text, so it is dropped rather than filtered.
    static func scrub(_ event: Event) -> Event? {
        // With no address of its own, Sentry reads a city from the connection.
        let user = User()
        user.ipAddress = "0.0.0.0"
        event.user = user
        event.serverName = nil
        event.message = nil
        event.breadcrumbs = nil
        event.extra = nil
        event.tags = nil
        event.context?["device"]?["name"] = nil
        event.context?["device"]?["locale"] = nil
        event.context?["app"]?["device_app_hash"] = nil
        event.context?["culture"] = nil
        event.exceptions?.forEach { exception in
            exception.value = nil
            exception.mechanism?.data = nil
            exception.mechanism?.desc = nil
        }
        return event
    }
}
