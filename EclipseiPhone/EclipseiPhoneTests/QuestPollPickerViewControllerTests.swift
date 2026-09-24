//
//  QuestPollPickerViewControllerTests.swift
//  EclipseiPhoneTests
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import LivePollKit
import Testing
import UIKit
@testable import EclipseiPhone

@MainActor
struct QuestPollPickerViewControllerTests {

    @Test func accountSectionOffersDelete() {
        let picker = QuestPollPickerViewController(client: quietClient())
        picker.loadViewIfNeeded()
        #expect(picker.tableView.numberOfSections == 2)
        let index = IndexPath(row: 0, section: 1)
        let cell = picker.tableView(picker.tableView, cellForRowAt: index)
        #expect(cell.accessibilityIdentifier == "livepoll.delete.account")
        let text = cell.contentConfiguration as? UIListContentConfiguration
        #expect(text?.text == "Delete Account")
    }
}

private func quietClient() -> LivePollClient {
    let config = URLSessionConfiguration.ephemeral
    config.protocolClasses = [QuietPollProtocol.self]
    config.timeoutIntervalForRequest = 1
    return LivePollClient(
        origin: URL(string: "https://example.invalid")!,
        session: URLSession(configuration: config)
    )
}

private final class QuietPollProtocol: URLProtocol, @unchecked Sendable {
    override class func canInit(with request: URLRequest) -> Bool { true }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        let url = request.url ?? URL(string: "https://example.invalid")!
        let response = HTTPURLResponse(
            url: url, statusCode: 401, httpVersion: nil, headerFields: nil
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data("{}".utf8))
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
