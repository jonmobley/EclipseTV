//
//  CountdownBackgroundTests.swift
//  EclipseiPhoneTests
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import CloudKit
import Foundation
import Testing
import UIKit
@testable import EclipseiPhone

struct CountdownBackgroundTests {

    @Test func tokensRoundTrip() {
        let cases: [CountdownBackground] = [
            .black,
            .screensaver,
            .background,
            .libraryItem(id: "IMG_0042.jpg")
        ]
        for background in cases {
            #expect(CountdownBackground(token: background.token) == background)
        }
    }

    @Test func unrecognizedTokensFallBackToBlack() {
        // A token written by a newer build must degrade to black, not fail decoding.
        #expect(CountdownBackground(token: nil) == .black)
        #expect(CountdownBackground(token: "") == .black)
        #expect(CountdownBackground(token: "media:") == .black)
        #expect(CountdownBackground(token: "gradient") == .black)
    }

    @Test func libraryItemIdIsExposedOnlyForMedia() {
        #expect(CountdownBackground.libraryItem(id: "a.mov").libraryItemId == "a.mov")
        #expect(CountdownBackground.screensaver.libraryItemId == nil)
        #expect(CountdownBackground.black.libraryItemId == nil)
    }

    @Test func codableRoundTripPreservesBackground() throws {
        let item = ShowCountdown(
            showId: UUID(),
            name: "Doors",
            duration: 600,
            background: .libraryItem(id: "IMG_1.jpg")
        )
        let data = try JSONEncoder().encode(item)
        let decoded = try JSONDecoder().decode(ShowCountdown.self, from: data)
        #expect(decoded.background == .libraryItem(id: "IMG_1.jpg"))
    }

    @Test func missingBackgroundDecodesAsBlack() throws {
        let item = ShowCountdown(
            showId: UUID(), name: "Break", duration: 90, background: .screensaver
        )
        let encoded = try JSONEncoder().encode(item)
        var object = try #require(
            JSONSerialization.jsonObject(with: encoded) as? [String: Any]
        )
        object.removeValue(forKey: "background")
        let stripped = try JSONSerialization.data(withJSONObject: object)
        let decoded = try JSONDecoder().decode(ShowCountdown.self, from: stripped)
        #expect(decoded.background == .black)
        #expect(decoded.name == "Break")
    }

    @Test func recordRoundTripPreservesBackground() throws {
        let item = ShowCountdown(
            showId: UUID(), name: "Doors", duration: 300, background: .screensaver
        )
        let record = CloudKitRecordMapper.makeCountdownRecord(from: item)
        let decoded = try #require(CloudKitRecordMapper.countdown(from: record))
        #expect(decoded.background == .screensaver)
    }

    @Test func recordWithoutBackgroundFieldDecodesAsBlack() throws {
        let item = ShowCountdown(
            showId: UUID(), name: "Doors", duration: 300, background: .background
        )
        let record = CloudKitRecordMapper.makeCountdownRecord(from: item)
        let empty: CKRecordValue? = nil
        record[CloudKitSchema.CountdownKey.background] = empty
        let decoded = try #require(CloudKitRecordMapper.countdown(from: record))
        #expect(decoded.background == .black)
    }

    /// `none` as a case name would make this comparison resolve to `Optional.none`
    /// and silently test against nil instead of the black background.
    @Test func caseNameDoesNotCollideWithOptional() {
        let item: ShowCountdown? = ShowCountdown(
            showId: UUID(), name: "Doors", duration: 60
        )
        #expect(item?.background == .black)
    }
}

@MainActor
struct CountdownBackgroundStoreTests {

    private static let suiteName = "EclipseTV.CountdownBackgroundTests"

    @Test func setBackgroundPersists() {
        let store = makeStore()
        let item = ShowCountdown(showId: UUID(), name: "Doors", duration: 60)
        store.applyRemote(item)
        #expect(store.countdown(id: item.id)?.background == .black)

        store.setBackground(id: item.id, .screensaver)
        #expect(store.countdown(id: item.id)?.background == .screensaver)

        store.setBackground(id: item.id, .black)
        #expect(store.countdown(id: item.id)?.background == .black)
    }

    @Test func setBackgroundIgnoresUnknownCountdown() {
        let store = makeStore()
        store.setBackground(id: UUID(), .screensaver)
        #expect(store.countdowns.isEmpty)
    }

    @Test func blackResolvesToNoMedia() {
        #expect(CountdownBackground.black.media == nil)
    }

    @Test func hidingTheHeroClockClearsTheBackground() {
        // A background left installed keeps a loop decoding behind other content.
        let header = LiveHeaderView(frame: CGRect(x: 0, y: 0, width: 320, height: 180))
        let background = CountdownBackgroundView()
        header.addSubview(background)
        header.countdownBackground = background

        header.hideCountdownClock()
        #expect(header.countdownBackground == nil)
        #expect(background.superview == nil)
    }

    @Test func heroSkipsBackgroundWhileTheClockIsHidden() {
        let header = LiveHeaderView(frame: CGRect(x: 0, y: 0, width: 320, height: 180))
        header.countdownClockLabel.isHidden = true
        header.refreshCountdownBackground()
        #expect(header.countdownBackground == nil)
    }

    @Test func viewSkipsRebuildForUnchangedMedia() {
        let view = CountdownBackgroundView()
        #expect(view.media == nil)

        let media = CountdownBackgroundMedia.still(URL(fileURLWithPath: "/tmp/a.jpg"))
        view.apply(media)
        #expect(view.media == media)
        view.apply(media)
        #expect(view.media == media)
        #expect(!view.isLoopPlaying)

        view.apply(nil)
        #expect(view.media == nil)
    }

    // MARK: - Readiness

    /// The transition holds its opaque overlay on this signal, so a still must not
    /// report ready until it has actually decoded.
    @Test func stillIsNotReadyUntilItDecodes() async throws {
        let url = try Self.writeTempImage()
        defer { try? FileManager.default.removeItem(at: url) }

        let view = CountdownBackgroundView()
        var didSignal = false
        view.onReady = { didSignal = true }

        view.apply(.still(url))
        #expect(!view.isReadyForDisplay)

        await Self.wait { didSignal }
        #expect(view.isReadyForDisplay)
        #expect(didSignal)
    }

    /// An unreadable file must still report ready or it stalls the transition until
    /// the watchdog fires, holding a stale frame on output for a full second.
    @Test func undecodableStillReportsReadyAnyway() async {
        let url = URL(fileURLWithPath: "/tmp/EclipseTV.countdown.missing.jpg")
        let view = CountdownBackgroundView()
        view.apply(.still(url))

        await Self.wait { view.isReadyForDisplay }
        #expect(view.isReadyForDisplay)
    }

    @Test func emptyBackgroundIsReadyWithoutWaiting() throws {
        let url = try Self.writeTempImage()
        defer { try? FileManager.default.removeItem(at: url) }

        let view = CountdownBackgroundView()
        view.apply(.still(url))
        view.apply(nil)
        #expect(view.isReadyForDisplay)
    }

    @Test func newMediaClearsReadiness() async throws {
        let url = try Self.writeTempImage()
        defer { try? FileManager.default.removeItem(at: url) }

        let view = CountdownBackgroundView()
        view.apply(.still(url))
        await Self.wait { view.isReadyForDisplay }
        #expect(view.isReadyForDisplay)

        view.apply(.still(URL(fileURLWithPath: "/tmp/EclipseTV.countdown.other.jpg")))
        #expect(!view.isReadyForDisplay)
    }

    // MARK: - Helpers

    private func makeStore() -> CountdownStore {
        let defaults = UserDefaults(suiteName: Self.suiteName) ?? .standard
        defaults.removePersistentDomain(forName: Self.suiteName)
        return CountdownStore(defaults: defaults)
    }

    /// Yields the main actor until `condition` holds, or ~2s passes.
    ///
    /// Decoding hops to a background queue and back, so the main queue has to drain
    /// for the background to report in.
    private static func wait(until condition: () -> Bool) async {
        for _ in 0..<100 {
            if condition() { return }
            try? await Task.sleep(for: .milliseconds(20))
        }
    }

    private static func writeTempImage() throws -> URL {
        let size = CGSize(width: 8, height: 8)
        let image = UIGraphicsImageRenderer(size: size).image { context in
            UIColor.systemTeal.setFill()
            context.fill(CGRect(origin: .zero, size: size))
        }
        guard let data = image.pngData() else {
            throw CocoaError(.fileWriteUnknown)
        }
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("countdown-\(UUID().uuidString).png")
        try data.write(to: url)
        return url
    }
}
