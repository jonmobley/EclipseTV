//
//  QuestPollPINViewControllerTests.swift
//  EclipseiPhoneTests
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import Testing
import UIKit
@testable import EclipseiPhone

@MainActor
struct QuestPollPINViewControllerTests {

    @Test func sheetKeepsPadInCardWithoutSystemNumberPad() {
        let pin = QuestPollPINViewController()
        pin.loadViewIfNeeded()
        #expect(pin.preferredContentSize == QuestPollPINViewController.sheetSize)
        #expect(textFields(in: pin.view).isEmpty)
        #expect(view(in: pin.view, id: "questpoll.pin.pad") != nil)
        for digit in ["0", "1", "2", "3", "4", "5", "6", "7", "8", "9"] {
            #expect(view(in: pin.view, id: "questpoll.pin.key.\(digit)") != nil)
        }
        #expect(view(in: pin.view, id: "questpoll.pin.key.delete") != nil)
    }

    @Test func errorCopyMatchesPINFailures() {
        #expect(QuestPollError.invalidPIN.userMessage == "That PIN is wrong.")
        #expect(QuestPollError.transport.userMessage.contains("questpoll.live"))
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
