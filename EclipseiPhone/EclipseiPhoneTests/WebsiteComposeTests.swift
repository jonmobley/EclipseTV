//
//  WebsiteComposeTests.swift
//  EclipseiPhoneTests
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import Foundation
import Testing
@testable import EclipseiPhone

struct WebsiteComposeTests {

    @Test func keyboardCheckOnURLMovesToTitle() {
        #expect(
            AddWebsiteViewController.keyboardReturnAction(isURLField: true) == .focusTitle
        )
    }

    @Test func keyboardCheckOnTitleHidesKeyboardInsteadOfAdding() {
        #expect(
            AddWebsiteViewController.keyboardReturnAction(isURLField: false) == .hideKeyboard
        )
    }

    @Test func showGridFindsAddedWebsiteCard() {
        let page = WebPage(
            title: "Example",
            url: URL(string: "https://example.com")!
        )
        let items: [ShowGridItem] = [.camera, .website(page), .add]
        #expect(
            LibraryGridViewController.indexOfShowMember(
                page.id.uuidString,
                in: items
            ) == 1
        )
    }
}
