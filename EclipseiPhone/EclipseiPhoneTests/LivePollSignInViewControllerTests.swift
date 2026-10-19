//
//  LivePollSignInViewControllerTests.swift
//  EclipseiPhoneTests
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import LivePollKit
import Testing
import UIKit
@testable import EclipseiPhone

@MainActor
struct LivePollSignInViewControllerTests {

    @Test func sheetUsesEmailFieldWithoutPINPad() {
        let signIn = LivePollSignInViewController()
        signIn.loadViewIfNeeded()
        #expect(signIn.preferredContentSize == LivePollSignInViewController.sheetSize)
        #expect(textFields(in: signIn.view).filter { !$0.isHidden }.count == 1)
        #expect(view(in: signIn.view, id: "livepoll.signin.email") != nil)
        let codeField = view(in: signIn.view, id: "livepoll.signin.codeField") as? UITextField
        #expect(codeField?.isHidden == true)
        #expect(codeField?.textContentType == .oneTimeCode)
        #expect(view(in: signIn.view, id: "questpoll.pin.pad") == nil)
    }

    @Test func errorCopyMatchesAuthFailures() {
        #expect(LivePollError.unauthorized.userMessage == "Sign in required.")
        #expect(LivePollError.transport.userMessage.contains("QuestPoll"))
    }
}

private func view(in root: UIView, id: String) -> UIView? {
    if root.accessibilityIdentifier == id { return root }
    for child in root.subviews {
        if let match = view(in: child, id: id) { return match }
    }
    return nil
}

private func textFields(in root: UIView) -> [UITextField] {
    var found: [UITextField] = []
    if let field = root as? UITextField { found.append(field) }
    for child in root.subviews {
        found.append(contentsOf: textFields(in: child))
    }
    return found
}
