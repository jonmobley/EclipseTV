//
//  StoreScreenshotDriver.swift
//  EclipseiPhoneUITests
//
//  Throwaway helper for capturing App Store screenshots in the simulator.
//  It only runs when STORE_SHOTS_DIR is set (via TEST_RUNNER_STORE_SHOTS_DIR), and it
//  executes simple commands read from numbered files in that host folder, so a person (or
//  script) can drive the real app screen by screen. Never part of the normal test pass.
//

import XCTest

final class StoreScreenshotDriver: XCTestCase {

    private var app: XCUIApplication!
    private var dir: URL!

    @MainActor
    func testDriveForStoreScreenshots() throws {
        guard let path = ProcessInfo.processInfo.environment["STORE_SHOTS_DIR"] else {
            throw XCTSkip("Store screenshot driver only runs when STORE_SHOTS_DIR is set.")
        }
        dir = URL(fileURLWithPath: path)
        executionTimeAllowance = 60 * 60 * 3
        continueAfterFailure = true
        app = XCUIApplication()

        var step = 1
        let fm = FileManager.default
        while true {
            let cmdURL = dir.appendingPathComponent("cmd.\(step)")
            guard fm.fileExists(atPath: cmdURL.path),
                  let text = try? String(contentsOf: cmdURL, encoding: .utf8) else {
                Thread.sleep(forTimeInterval: 0.3)
                continue
            }
            var log: [String] = []
            for raw in text.split(separator: "\n") {
                let line = raw.trimmingCharacters(in: .whitespaces)
                if line.isEmpty { continue }
                if line == "quit" { return }
                log.append("> \(line)")
                log.append(run(line))
            }
            try? log.joined(separator: "\n")
                .write(to: dir.appendingPathComponent("out.\(step)"), atomically: true, encoding: .utf8)
            step += 1
        }
    }

    @MainActor
    private func find(_ query: String, in root: XCUIElement? = nil) -> XCUIElement? {
        let base = root ?? app!
        let pred = NSPredicate(format: "label == %@ OR identifier == %@", query, query)
        let all = base.descendants(matching: .any).matching(pred)
        let count = all.count
        for i in 0..<count {
            let el = all.element(boundBy: i)
            if el.exists && el.isHittable { return el }
        }
        return count > 0 ? all.element(boundBy: 0) : nil
    }

    @MainActor
    private func run(_ line: String) -> String {
        let parts = line.split(separator: " ", maxSplits: 1).map(String.init)
        let cmd = parts[0]
        let arg = parts.count > 1 ? parts[1] : ""
        switch cmd {
        case "launch":
            app.launchArguments = ["-StoreScreenshots"] + arg.split(separator: " ").map(String.init)
            app.launch()
            return "launched"
        case "activate":
            app.activate()
            return "ok"
        case "wait":
            Thread.sleep(forTimeInterval: Double(arg) ?? 1)
            return "ok"
        case "tap", "long", "dtap":
            // "tap Label" or "tap Label#2" picks the nth match.
            var q = arg
            var idx: Int? = nil
            if let hash = arg.lastIndex(of: "#"), let n = Int(arg[arg.index(after: hash)...]) {
                q = String(arg[..<hash]); idx = n
            }
            let el: XCUIElement?
            if let idx {
                el = app.descendants(matching: .any)
                    .matching(NSPredicate(format: "label == %@ OR identifier == %@", q, q))
                    .element(boundBy: idx)
            } else {
                el = find(q)
            }
            guard let el, el.waitForExistence(timeout: 5) else { return "NOT FOUND: \(q)" }
            let desc = "\(el.elementType.rawValue) '\(el.label)'"
            // Coordinate taps never raise "not hittable" failures, which would end the session.
            let target = el.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
            guard el.frame.width > 0, el.frame.height > 0 else { return "ZERO FRAME: \(q)" }
            if cmd == "long" { target.press(forDuration: 1.2) }
            else if cmd == "dtap" { target.doubleTap() }
            else { target.tap() }
            return "tapped \(desc)"
        case "xy", "longxy":
            // Normalized coordinates within the app window.
            let nums = arg.split(separator: " ").compactMap { Double($0) }
            guard nums.count == 2 else { return "bad xy" }
            let c = app.coordinate(withNormalizedOffset: CGVector(dx: nums[0], dy: nums[1]))
            if cmd == "longxy" { c.press(forDuration: 1.2) } else { c.tap() }
            return "ok"
        case "drag":
            let n = arg.split(separator: " ").compactMap { Double($0) }
            guard n.count == 4 else { return "bad drag" }
            let a = app.coordinate(withNormalizedOffset: CGVector(dx: n[0], dy: n[1]))
            let b = app.coordinate(withNormalizedOffset: CGVector(dx: n[2], dy: n[3]))
            a.press(forDuration: 0.1, thenDragTo: b)
            return "ok"
        case "type":
            // Typing with nothing focused is a fatal XCTest failure; bail out politely instead.
            let focused = app.descendants(matching: .any)
                .matching(NSPredicate(format: "hasKeyboardFocus == true")).firstMatch
            guard focused.waitForExistence(timeout: 3) else { return "NO FOCUS" }
            app.typeText(arg.replacingOccurrences(of: "\\n", with: "\n"))
            return "ok"
        case "swipe":
            switch arg {
            case "up": app.swipeUp()
            case "down": app.swipeDown()
            case "left": app.swipeLeft()
            default: app.swipeRight()
            }
            return "ok"
        case "shot":
            let png = XCUIScreen.main.screenshot().pngRepresentation
            try? png.write(to: dir.appendingPathComponent("\(arg).png"))
            return "saved \(arg).png"
        case "dump":
            try? app.debugDescription.write(
                to: dir.appendingPathComponent("\(arg).txt"), atomically: true, encoding: .utf8)
            return "dumped \(arg).txt"
        case "rotate":
            XCUIDevice.shared.orientation = arg == "landscape" ? .landscapeLeft : .portrait
            return "ok"
        default:
            return "unknown command"
        }
    }
}
