//
//  WalkthroughRecorder.swift
//  EclipseiPhoneUITests
//
//  Description: Saves walk-through screenshots and findings as test
//               attachments, and finds the tappable controls on a screen.
//  Thread Safety: Main actor only (XCUITest APIs are main-actor bound).
//

import XCTest

// MARK: - WalkthroughControl

/// One tappable control found in an accessibility snapshot.
struct WalkthroughControl: Hashable {
    let role: XCUIElement.ElementType
    let label: String
    let frame: CGRect

    /// Name used in attachment names.
    var name: String { label.isEmpty ? "unlabelled \(role.rawValue) at \(Int(frame.midX)),\(Int(frame.midY))" : label }
}

// MARK: - WalkthroughRecorder

/// Pictures and notes for one walk-through test.
///
/// Every picture is an attachment named `NNNN area - step`, kept even when
/// the test passes; `xcrun xcresulttool export attachments` pulls them out.
/// Findings (crash, error, empty, missing, note) are text attachments named
/// `finding …` so they sort next to their picture.
///
/// Thread Safety: Main actor only.
@MainActor
final class WalkthroughRecorder {

    // MARK: - Constants

    /// Labels never tapped: they delete, buy, sign out or leave the app.
    static let unsafeWords = [
        "delete", "remove", "erase", "reset", "clear", "sign out", "log out", "buy", "purchase",
        "subscribe", "restore", "unpair", "forget", "trash", "share", "send", "report", "email",
        "rate", "review", "app store", "testflight", "contact", "record"
    ]

    /// Kinds of control worth tapping.
    static let tappableRoles: Set<XCUIElement.ElementType> = [
        .button, .cell, .switch, .segmentedControl, .tab, .link, .menuButton, .image
    ]

    // MARK: - Properties

    private unowned let testCase: XCTestCase
    private let app: XCUIApplication
    private var counter = 0

    // MARK: - Initialization

    init(testCase: XCTestCase, app: XCUIApplication) {
        self.testCase = testCase
        self.app = app
    }

    // MARK: - Recording

    /// Saves a picture of the whole screen.
    /// - Parameters:
    ///   - area: App area, e.g. "Library".
    ///   - step: What is on screen.
    func shot(_ area: String, _ step: String) {
        counter += 1
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = String(format: "%04d %@ - %@", counter, area, step)
        attachment.lifetime = .keepAlways
        testCase.add(attachment)
    }

    /// Records a problem next to the latest picture.
    func finding(_ kind: String, area: String, detail: String) {
        note("finding \(kind) \(area)", "\(kind) | \(area) | \(detail)")
    }

    /// Saves free text (control lists, element dumps).
    func note(_ name: String, _ text: String) {
        let attachment = XCTAttachment(string: text)
        attachment.name = String(format: "%04d %@", counter, name)
        attachment.lifetime = .keepAlways
        testCase.add(attachment)
    }

    // MARK: - Controls

    /// Safe, visible, tappable controls on screen, top to bottom.
    func controls() -> [WalkthroughControl] {
        guard let snapshot = try? app.snapshot() else { return [] }
        var found: [WalkthroughControl] = []
        collect(snapshot, screen: app.frame, into: &found)
        var seen = Set<String>()
        return found.filter { seen.insert("\($0.role.rawValue)|\($0.label)|\(Int($0.frame.midX / 8))|\(Int($0.frame.midY / 8))").inserted }
            .sorted { ($0.frame.minY, $0.frame.minX) < ($1.frame.minY, $1.frame.minX) }
    }

    /// Element tree as text, for review.
    func tree() -> String {
        guard let snapshot = try? app.snapshot() else { return "(no snapshot)" }
        var lines: [String] = []
        dump(snapshot, depth: 0, into: &lines)
        return lines.joined(separator: "\n")
    }

    /// True when a label names something the walk-through must not tap.
    static func isUnsafe(_ label: String) -> Bool {
        let lower = label.lowercased()
        return unsafeWords.contains { lower.contains($0) }
    }

    // MARK: - Private Helpers

    private func collect(_ node: XCUIElementSnapshot, screen: CGRect, into found: inout [WalkthroughControl]) {
        guard node.elementType != .keyboard else { return }
        let label = node.label.isEmpty ? node.identifier : node.label
        let visible = node.frame.width > 4 && node.frame.height > 4 && screen.contains(CGPoint(x: node.frame.midX, y: node.frame.midY))
        let isImageButton = node.elementType != .image || node.label.count > 1
        if Self.tappableRoles.contains(node.elementType), node.isEnabled, visible, isImageButton, !Self.isUnsafe(label) {
            found.append(WalkthroughControl(role: node.elementType, label: label, frame: node.frame))
        }
        for child in node.children { collect(child, screen: screen, into: &found) }
    }

    private func dump(_ node: XCUIElementSnapshot, depth: Int, into lines: inout [String]) {
        guard depth < 40 else { return }
        let text = [node.label, node.identifier, (node.value as? String) ?? ""].filter { !$0.isEmpty }.joined(separator: " | ")
        let frame = node.frame
        lines.append(String(repeating: "  ", count: depth)
            + "\(node.elementType.rawValue) \(text) [\(Int(frame.minX)),\(Int(frame.minY)) \(Int(frame.width))x\(Int(frame.height))]")
        for child in node.children { dump(child, depth: depth + 1, into: &lines) }
    }
}
