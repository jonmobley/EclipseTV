//
//  EclipseWalkthroughTests.swift
//  EclipseiPhoneUITests
//
//  Description: Walks every screen of the iPhone/iPad app in a simulator:
//               taps each safe control, long-presses for menus, and keeps a
//               picture of every step.
//  Thread Safety: Main actor only.
//

import XCTest

// MARK: - EclipseWalkthroughTests

/// Audit walk-through for iPhone and iPad (same tests on either simulator).
///
/// Records, never judges: failures become `finding` attachments and the
/// run carries on. Run with `-only-testing:EclipseiPhoneUITests/EclipseWalkthroughTests`
/// on a fresh simulator that is not signed in to iCloud.
@MainActor
final class EclipseWalkthroughTests: XCTestCase {

    // MARK: - Constants

    /// Most controls tapped per screen.
    private static let controlLimit = 60

    /// Seconds to let a screen settle before a picture.
    private static let settle: TimeInterval = 1.0

    /// Seconds a tap may take before it counts as a hang.
    private static let hangSeconds: TimeInterval = 8

    // MARK: - Properties

    private var app = XCUIApplication()
    private lazy var recorder = WalkthroughRecorder(testCase: self, app: app)

    // MARK: - Lifecycle

    override func setUpWithError() throws {
        continueAfterFailure = true
        executionTimeAllowance = 60 * 60
        // Never come back up in Camera Mode: one tap on it would otherwise
        // trap every later relaunch on the camera screen.
        app.launchArguments += ["-EclipseTV.cameraMode.active", "NO"]
        app.launch()
        allowSystemAlerts()
        Thread.sleep(forTimeInterval: 3)
    }

    /// Logs the problem instead of failing the run.
    override func record(_ issue: XCTIssue) {
        recorder.finding("harness", area: name, detail: issue.compactDescription)
    }

    // MARK: - Tests

    /// Makes a show to walk, so the Show tab is not empty.
    func testAMakeShow() {
        let newShow = app.buttons["New Show"].firstMatch
        guard newShow.waitForExistence(timeout: 5) else {
            recorder.finding("missing", area: "Setup", detail: "No New Show button on the first screen")
            return
        }
        newShow.tap()
        Thread.sleep(forTimeInterval: Self.settle)
        recorder.shot("Setup", "New Show prompt")
        let field = app.textFields.firstMatch
        if field.waitForExistence(timeout: 3) {
            field.tap()
            field.typeText("Walkthrough Show")
        }
        recorder.shot("Setup", "name typed")
        for title in ["Create", "Save", "OK", "Done", "Add"] where app.buttons[title].firstMatch.exists {
            app.buttons[title].firstMatch.tap()
            break
        }
        Thread.sleep(forTimeInterval: Self.settle * 2)
        recorder.shot("Setup", "new show open")
        recorder.note("show tree", recorder.tree())
    }

    /// First screen, then every control on it and one level below.
    func testBWalkEveryScreen() {
        recorder.note("launch tree", recorder.tree())
        recorder.shot("Launch", "first screen")
        let rootControls = recorder.controls()
        recorder.note("launch controls", rootControls.map(\.name).joined(separator: "\n"))
        for control in rootControls.prefix(Self.controlLimit) {
            visit(control, area: "Root")
            backToRoot()
        }
    }

    /// Long-press every card-sized control for its menu.
    func testCLongPressMenus() {
        let cards = recorder.controls().filter { $0.frame.width >= 80 && $0.frame.height >= 60 }
        recorder.note("long-press targets", cards.map(\.name).joined(separator: "\n"))
        for card in cards.prefix(Self.controlLimit / 2) {
            coordinate(card.frame).press(forDuration: 1.2)
            Thread.sleep(forTimeInterval: Self.settle)
            recorder.shot("Long-press", card.name)
            recorder.note("menu \(card.name)", menuItems().joined(separator: "\n"))
            backToRoot()
        }
    }

    // MARK: - Visiting

    /// Taps one control, photographs the result, then taps each control on
    /// the screen it opened (one level deeper), returning in between.
    private func visit(_ control: WalkthroughControl, area: String) {
        let before = Set(recorder.controls().map(\.name))
        tap(control, area: area)
        let opened = recorder.controls().filter { !before.contains($0.name) }
        guard !opened.isEmpty else { return }
        let screen = "\(area) › \(control.name)"
        recorder.note("controls \(screen)", opened.map(\.name).joined(separator: "\n"))
        for child in opened.prefix(Self.controlLimit / 3) {
            tap(child, area: screen)
            dismissTopmost()
            if !isShowing(opened) {
                backToRoot()
                tap(control, area: area, photograph: false)
            }
        }
    }

    private func tap(_ control: WalkthroughControl, area: String, photograph: Bool = true) {
        let started = Date()
        coordinate(control.frame).tap()
        Thread.sleep(forTimeInterval: Self.settle)
        allowSystemAlerts()
        guard photograph else { return }
        recorder.shot(area, control.name)
        checkHealth(area: area, step: control.name, started: started)
    }

    private func checkHealth(area: String, step: String, started: Date) {
        if app.state != .runningForeground {
            recorder.finding("crash", area: area, detail: "App left the foreground after: \(step)")
            app.launch()
            Thread.sleep(forTimeInterval: 3)
            return
        }
        let elapsed = Date().timeIntervalSince(started)
        if elapsed > Self.hangSeconds + Self.settle {
            recorder.finding("hang", area: area, detail: String(format: "%@ took %.1f s", step, elapsed))
        }
        let alert = app.alerts.firstMatch
        if alert.exists {
            recorder.finding("alert", area: area, detail: "\(step): \(alert.label) \(alert.staticTexts.allElementsBoundByIndex.map(\.label).joined(separator: " "))")
        }
        if recorder.controls().isEmpty {
            recorder.finding("empty", area: area, detail: "\(step): nothing tappable on screen")
        }
    }

    // MARK: - Navigation

    /// Closes the top sheet, menu, alert or pushed screen.
    private func dismissTopmost() {
        let names = ["Cancel", "Done", "Close", "Not Now", "OK", "Back"]
        for name in names {
            let button = app.buttons[name].firstMatch
            if button.exists && button.isHittable {
                button.tap()
                Thread.sleep(forTimeInterval: 0.5)
                return
            }
        }
        let back = app.navigationBars.buttons.element(boundBy: 0)
        if back.exists && back.isHittable && app.navigationBars.count > 0 && !back.label.isEmpty {
            back.tap()
        } else {
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.05)).tap()
            app.swipeDown(velocity: .fast)
        }
        Thread.sleep(forTimeInterval: 0.5)
    }

    /// Relaunches the app so the next control starts from the first screen.
    private func backToRoot() {
        app.terminate()
        app.launch()
        Thread.sleep(forTimeInterval: 2.5)
    }

    private func isShowing(_ controls: [WalkthroughControl]) -> Bool {
        let now = Set(recorder.controls().map(\.name))
        return controls.prefix(3).allSatisfy { now.contains($0.name) }
    }

    // MARK: - Helpers

    private func coordinate(_ frame: CGRect) -> XCUICoordinate {
        app.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: frame.midX, dy: frame.midY))
    }

    private func menuItems() -> [String] {
        let buttons = app.collectionViews.buttons.allElementsBoundByIndex + app.menuItems.allElementsBoundByIndex
        return buttons.map(\.label).filter { !$0.isEmpty }
    }

    /// Answers permission prompts (photos, local network, camera) with the
    /// least-sharing choice so the walk can continue.
    private func allowSystemAlerts() {
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let alert = springboard.alerts.firstMatch
        guard alert.waitForExistence(timeout: 0.3) else { return }
        recorder.shot("System prompt", alert.label)
        for choice in ["Don’t Allow", "Don't Allow", "Not Now", "Allow Once", "OK"] where alert.buttons[choice].exists {
            alert.buttons[choice].tap()
            return
        }
    }
}
