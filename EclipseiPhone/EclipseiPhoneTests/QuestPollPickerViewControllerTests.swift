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

    @Test func pickerOnlyChoosesPollsAccountActionsLiveInSettings() {
        let picker = QuestPollPickerViewController(client: quietClient())
        picker.loadViewIfNeeded()
        #expect(picker.title == "Choose a Poll")
        #expect(picker.tableView.numberOfSections == 2)
        // Plan row appears only once the plan loads; the stub returns 401.
        #expect(picker.tableView.numberOfRows(inSection: 0) == 0)
        #expect(picker.navigationItem.rightBarButtonItem?.title == "Manage")
    }

    @Test func planTextNamesTheLimitAndHowToLiftIt() {
        let free = LivePollPlan(eclipse: false, playerLimit: 50, linkExpired: false)
        #expect(QuestPollPlanText.title(free) == "Free plan · up to 50 people")
        #expect(QuestPollPlanText.detail(free)?.contains("Eclipse license") == true)
        let eclipse = LivePollPlan(eclipse: true, playerLimit: 300, linkExpired: false)
        #expect(QuestPollPlanText.title(eclipse) == "Eclipse plan · up to 300 people")
        #expect(QuestPollPlanText.detail(eclipse) == nil)
    }

    @Test func joinedTextShowsTheFreeLimit() {
        #expect(QuestPollHostViewController.joinedText(joined: 12, limit: 300) == "12 joined")
        #expect(QuestPollHostViewController.joinedText(joined: 12, limit: nil) == "12 joined")
        #expect(QuestPollHostViewController.joinedText(joined: 12, limit: 50) == "12 of 50 joined")
        #expect(
            QuestPollHostViewController.joinedText(joined: 50, limit: 50)
                == "50 of 50 joined · free plan limit"
        )
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
