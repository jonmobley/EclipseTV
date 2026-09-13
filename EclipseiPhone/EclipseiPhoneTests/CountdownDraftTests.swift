//
//  CountdownDraftTests.swift
//  EclipseiPhoneTests
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import Foundation
import Testing
@testable import EclipseiPhone

@MainActor
struct CountdownDraftTests {

    private static let suiteName = "EclipseTV.CountdownDraftTests"

    @Test func newDraftStartsWhereTheMenuAddDid() {
        let draft = CountdownDraft(showId: UUID(), name: "Countdown", duration: 300)
        #expect(draft.layout == .default)
        #expect(draft.background == .black)
        #expect(draft.endAction == .hold)
        #expect(draft.isPresetDuration)
        #expect(draft.durationText == "5:00")
    }

    @Test func customDurationIsNotAPreset() {
        var draft = CountdownDraft(showId: UUID(), name: "Doors", duration: 450)
        #expect(!draft.isPresetDuration)
        #expect(draft.durationText == "7:30")
        draft.duration = 60
        #expect(draft.isPresetDuration)
    }

    @Test func layoutSummaryDescribesPositionAndScale() {
        #expect(CountdownDraft.layoutSummary(for: .default) == "Centered · 100%")
        #expect(
            CountdownDraft.layoutSummary(
                for: CountdownClockLayout(centerX: 0.5, centerY: 0.5, scale: 1.3)
            ) == "Centered · 130%"
        )
        #expect(
            CountdownDraft.layoutSummary(
                for: CountdownClockLayout(centerX: 0.2, centerY: 0.8, scale: 0.5)
            ) == "Custom position · 50%"
        )
        // Out-of-range scale reads as what will actually be saved.
        #expect(
            CountdownDraft.layoutSummary(
                for: CountdownClockLayout(centerX: 0.5, centerY: 0.5, scale: 9)
            ) == "Centered · 250%"
        )
    }

    @Test func previewItemCarriesEveryDraftValueUnderTheGivenId() {
        let id = UUID()
        let showId = UUID()
        let draft = CountdownDraft(
            showId: showId,
            name: "  Doors  ",
            duration: 90,
            layout: CountdownClockLayout(centerX: 0.3, centerY: 0.7, scale: 1.2),
            background: .screensaver,
            endAction: .next
        )
        let item = draft.previewItem(id: id)
        #expect(item.id == id)
        #expect(item.showId == showId)
        #expect(item.name == "Doors")
        #expect(item.duration == 90)
        #expect(item.layout == draft.layout)
        #expect(item.background == .screensaver)
        #expect(item.endAction == .next)
    }

    @Test func previewItemWithBlankNameStillHasATitle() {
        let draft = CountdownDraft(showId: UUID(), name: "   ", duration: 60)
        #expect(draft.previewItem(id: UUID()).name == "Countdown")
    }

    @Test func commitCreatesTheCountdownAndRemembersTheDuration() throws {
        let (store, defaults) = makeStore()
        let showId = UUID()
        let draft = CountdownDraft(
            showId: showId,
            name: "Offering",
            duration: 450,
            layout: CountdownClockLayout(centerX: 0.5, centerY: 0.9, scale: 0.6),
            background: .background,
            endAction: .black
        )
        let item = try draft.commit(to: store, defaults: defaults)
        let saved = try #require(store.countdown(id: item.id))
        #expect(saved.showId == showId)
        #expect(saved.name == "Offering")
        #expect(saved.duration == 450)
        #expect(saved.layout == draft.layout)
        #expect(saved.background == .background)
        #expect(saved.endAction == .black)
        #expect(defaults.integer(forKey: CountdownController.durationKey) == 450)
        #expect(CountdownController.lastStoredDuration(defaults: defaults) == 450)
    }

    @Test func commitRejectsABlankNameWithoutTouchingTheStore() {
        let (store, defaults) = makeStore()
        let draft = CountdownDraft(showId: UUID(), name: "  ", duration: 60)
        #expect(throws: CountdownStore.StoreError.self) {
            try draft.commit(to: store, defaults: defaults)
        }
        #expect(store.countdowns.isEmpty)
        #expect(defaults.object(forKey: CountdownController.durationKey) == nil)
    }

    @Test func addScreenOffersFromThisShowOnlyWhenMediaIsOnDevice() {
        #expect(
            AddCountdownViewController.sections(hasShowMedia: false)
                == [.name, .duration, .layout, .background, .ending]
        )
        #expect(
            AddCountdownViewController.sections(hasShowMedia: true)
                == [.name, .duration, .layout, .background, .showMedia, .ending]
        )
    }

    // MARK: - Helpers

    private func makeStore() -> (CountdownStore, UserDefaults) {
        let defaults = UserDefaults(suiteName: Self.suiteName) ?? .standard
        defaults.removePersistentDomain(forName: Self.suiteName)
        return (CountdownStore(defaults: defaults), defaults)
    }
}
