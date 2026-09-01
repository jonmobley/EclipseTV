//
//  MediaNoteStoreTests.swift
//  EclipseiPhoneTests
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import Testing
import UIKit
@testable import EclipseiPhone

@Suite(.serialized)
@MainActor
struct MediaNoteStoreTests {

    @Test func setAndGetNote() {
        let id = uniqueId()
        defer { MediaNoteStore.clear(forId: id) }

        MediaNoteStore.setNote("Cue the logo", forId: id)
        #expect(MediaNoteStore.note(forId: id) == "Cue the logo")
        #expect(MediaNoteStore.hasNote(forId: id))
    }

    @Test func emptyAndWhitespaceClearsNote() {
        let id = uniqueId()
        defer { MediaNoteStore.clear(forId: id) }

        MediaNoteStore.setNote("Keep this", forId: id)
        MediaNoteStore.setNote("   \n\t  ", forId: id)
        #expect(MediaNoteStore.note(forId: id) == nil)
        #expect(!MediaNoteStore.hasNote(forId: id))

        MediaNoteStore.setNote("Again", forId: id)
        MediaNoteStore.setNote("", forId: id)
        #expect(MediaNoteStore.note(forId: id) == nil)
    }

    @Test func notesAreIsolatedById() {
        let a = uniqueId()
        let b = uniqueId()
        defer {
            MediaNoteStore.clear(forId: a)
            MediaNoteStore.clear(forId: b)
        }

        MediaNoteStore.setNote("Alpha", forId: a)
        MediaNoteStore.setNote("Beta", forId: b)
        #expect(MediaNoteStore.note(forId: a) == "Alpha")
        #expect(MediaNoteStore.note(forId: b) == "Beta")
        MediaNoteStore.clear(forId: a)
        #expect(MediaNoteStore.note(forId: a) == nil)
        #expect(MediaNoteStore.note(forId: b) == "Beta")
    }

    @Test func menuTitleSwitchesAddAndEdit() {
        let id = uniqueId()
        defer { MediaNoteStore.clear(forId: id) }

        #expect(MediaNoteStore.menuTitle(forId: id) == "Add note")
        MediaNoteStore.setNote("Speaker intro", forId: id)
        #expect(MediaNoteStore.menuTitle(forId: id) == "Edit note")
        MediaNoteStore.setNote(nil, forId: id)
        #expect(MediaNoteStore.menuTitle(forId: id) == "Add note")
    }

    @Test func overlayVisibilityRespectsPref() {
        let id = uniqueId()
        let previous = MediaNoteStore.visibility
        defer {
            MediaNoteStore.clear(forId: id)
            MediaNoteStore.visibility = previous
        }

        MediaNoteStore.visibility = .whenExists
        #expect(!MediaNoteStore.shouldShowOverlay(forId: id))

        MediaNoteStore.visibility = .always
        #expect(MediaNoteStore.shouldShowOverlay(forId: id))

        MediaNoteStore.setNote("Visible either way", forId: id)
        MediaNoteStore.visibility = .whenExists
        #expect(MediaNoteStore.shouldShowOverlay(forId: id))
    }

    @Test func overlayViewHidesWhenEmptyAndWhenExists() {
        let id = uniqueId()
        let previous = MediaNoteStore.visibility
        defer {
            MediaNoteStore.clear(forId: id)
            MediaNoteStore.visibility = previous
        }

        MediaNoteStore.visibility = .whenExists
        let overlay = MediaNoteOverlayView()
        overlay.configure(itemId: id)
        #expect(overlay.isHidden)

        MediaNoteStore.visibility = .always
        overlay.reload()
        #expect(!overlay.isHidden)

        MediaNoteStore.setNote("Show me", forId: id)
        MediaNoteStore.visibility = .whenExists
        overlay.reload()
        #expect(!overlay.isHidden)
    }

    @Test func composerWhitespaceSaveRemovesNote() {
        let id = uniqueId()
        defer { MediaNoteStore.clear(forId: id) }

        MediaNoteStore.setNote("Draft", forId: id)
        // Same path the composer uses on Done / dismiss.
        MediaNoteStore.setNote(" \n ", forId: id)
        #expect(MediaNoteStore.note(forId: id) == nil)
    }

    private func uniqueId() -> String {
        "note-test-\(UUID().uuidString)"
    }
}
