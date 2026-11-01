//
//  CrashReporting.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import Foundation
import Sentry

/// Sends crash and freeze reports to Sentry. Nothing else: no analytics, no
/// screenshots, no network addresses, no account details.
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

    /// Removes anything that could name a person's file, link or device.
    static func scrub(_ event: Event) -> Event? {
        event.user = nil
        event.serverName = nil
        event.breadcrumbs = event.breadcrumbs?.filter { !containsSensitiveText($0.message) }
        if let message = event.message?.formatted {
            event.message = SentryMessage(formatted: redact(message))
        }
        event.exceptions?.forEach { exception in
            exception.value = exception.value.map(redact)
        }
        return event
    }

    private static func containsSensitiveText(_ text: String?) -> Bool {
        guard let text else { return false }
        return text != redact(text)
    }

    /// Links and file paths can carry names of shows, media and people.
    static func redact(_ text: String) -> String {
        text
            .replacingOccurrences(of: #"[a-zA-Z][a-zA-Z0-9+.-]*://\S+"#, with: "<url>", options: .regularExpression)
            .replacingOccurrences(of: #"(/[^/\s]+){2,}/?"#, with: "<path>", options: .regularExpression)
    }
}
