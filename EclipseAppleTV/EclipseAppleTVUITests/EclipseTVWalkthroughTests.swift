//
//  EclipseTVWalkthroughTests.swift
//  EclipseAppleTVUITests
//
//  Description: Walks the Apple TV app with the remote in a simulator:
//               moves focus over every screen, opens each item, holds Select
//               for long-press menus, and keeps a picture of every step.
//  Thread Safety: Main actor only.
//

import XCTest

// MARK: - EclipseTVWalkthroughTests

/// Audit walk-through for Apple TV (pairing, idle screen, library, menus).
///
/// Records, never judges: failures become `finding` attachments and the run
/// carries on. Run with `-only-testing:EclipseAppleTVUITests/EclipseTVWalkthroughTests`.
@MainActor
final class EclipseTVWalkthroughTests: XCTestCase {

    // MARK: - Constants

    /// Focus moves tried in each direction on a screen.
    private static let reach = 6

    /// Seconds to let focus or a screen settle.
    private static let settle: TimeInterval = 1.0

    // MARK: - Properties

    private let app = XCUIApplication()
    private let remote = XCUIRemote.shared
    private var counter = 0
    private var seenFocus = Set<String>()

    // MARK: - Lifecycle

    override func setUpWithError() throws {
        continueAfterFailure = true
        executionTimeAllowance = 60 * 60
        app.launch()
        Thread.sleep(forTimeInterval: 4)
    }

    /// Logs the problem instead of failing the run.
    override func record(_ issue: XCTIssue) {
        note("finding harness", issue.compactDescription)
    }

    // MARK: - Tests

    /// First screen, then a focus sweep with Select and long-press on each item.
    func testWalkWithRemote() {
        note("launch tree", app.debugDescription)
        shot("Launch", "first screen")
        for row in 0..<Self.reach {
            for column in 0..<Self.reach {
                guard let label = focusedLabel(), seenFocus.insert(focusKey(label)).inserted else {
                    press(.right)
                    continue
                }
                shot("Focus", "r\(row)c\(column) \(label)")
                openAndReturn(label)
                longPressAndReturn(label)
                press(.right)
            }
            for _ in 0..<Self.reach { press(.left) }
            press(.down)
        }
        press(.menu)
        shot("Menu", "after Menu from first screen")
    }

    /// Play/Pause and Menu on the first screen (shortcuts and help).
    func testRemoteButtons() {
        for (button, name) in [(XCUIRemote.Button.playPause, "Play/Pause"), (.menu, "Menu")] {
            app.launch()
            Thread.sleep(forTimeInterval: 3)
            press(button)
            shot("Remote", name)
            if app.state != .runningForeground {
                note("finding note", "\(name) on the first screen left the app")
            }
        }
    }

    /// The Options (⋯) menu at the top right, and each choice in it.
    func testOptionsMenu() {
        for index in 0..<Self.reach + 2 {
            app.launch()
            Thread.sleep(forTimeInterval: 3)
            guard focusOptions() else {
                shot("Options", "could not focus Options")
                note("finding missing", "Options button never took focus from the remote")
                return
            }
            press(.select)
            if index == 0 { shot("Options", "open"); note("tree options open", app.debugDescription) }
            for _ in 0..<index { press(.down) }
            let label = focusedLabel() ?? "item \(index)"
            press(.select)
            shot("Options", "\(index) \(label)")
            checkHealth(after: "Options \(label)")
            note("tree options \(index)", app.debugDescription)
            press(.menu)
            press(.menu)
        }
    }

    // MARK: - Private Helpers

    /// Moves focus up and right until the Options (⋯) button has it.
    private func focusOptions() -> Bool {
        for _ in 0..<Self.reach {
            if focusedLabel() == "Options" { return true }
            press(.up)
            if focusedLabel() == "Options" { return true }
            press(.right)
        }
        return focusedLabel() == "Options"
    }

    /// Label plus position, so several "Photo" tiles each count once.
    private func focusKey(_ label: String) -> String {
        let focused = app.descendants(matching: .any).matching(NSPredicate(format: "hasFocus == true")).firstMatch
        return "\(label)|\(Int(focused.frame.midX / 20))|\(Int(focused.frame.midY / 20))"
    }

    private func openAndReturn(_ label: String) {
        press(.select)
        shot("Select", label)
        checkHealth(after: "Select \(label)")
        press(.menu)
    }

    private func longPressAndReturn(_ label: String) {
        remote.press(.select, forDuration: 1.5)
        Thread.sleep(forTimeInterval: Self.settle)
        shot("Long-press", label)
        checkHealth(after: "long-press \(label)")
        press(.menu)
    }

    private func checkHealth(after step: String) {
        if app.state != .runningForeground {
            note("finding crash", "App left the foreground after: \(step)")
            app.launch()
            Thread.sleep(forTimeInterval: 3)
        }
        let alert = app.alerts.firstMatch
        if alert.exists {
            note("finding alert", "\(step): \(alert.label)")
        }
    }

    private func press(_ button: XCUIRemote.Button) {
        remote.press(button)
        Thread.sleep(forTimeInterval: Self.settle)
    }

    private func focusedLabel() -> String? {
        let focused = app.descendants(matching: .any).matching(NSPredicate(format: "hasFocus == true")).firstMatch
        guard focused.exists else { return nil }
        let label = focused.label.isEmpty ? focused.identifier : focused.label
        return label.isEmpty ? "unlabelled \(Int(focused.frame.midX)),\(Int(focused.frame.midY))" : label
    }

    private func shot(_ area: String, _ step: String) {
        counter += 1
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = String(format: "%04d %@ - %@", counter, area, step)
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func note(_ name: String, _ text: String) {
        let attachment = XCTAttachment(string: text)
        attachment.name = String(format: "%04d %@", counter, name)
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
