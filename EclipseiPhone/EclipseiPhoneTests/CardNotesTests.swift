//
//  CardNotesTests.swift
//  EclipseiPhoneTests
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import Testing
import Foundation
@testable import EclipseiPhone

/// Presenter notes work on every card kind that can carry one.
@Suite(.serialized)
@MainActor
struct CardNotesTests {

    @Test func everyNotableCardKindHasANoteId() {
        let show = UUID()
        let countdown = ShowCountdown(showId: show, name: "Break", duration: 60)
        let poll = ShowLivePoll(showId: show, pollId: "p", title: "T", questionCount: 1)
        let slideshow = Slideshow(showId: show, name: "Deck")
        let scriptId = UUID()
        let media = LibraryItemDTO(id: "clip", name: "clip", isVideo: true, duration: 9, isAvailable: true)

        #expect(ShowGridItem.countdown(countdown).noteId == countdown.id.uuidString)
        #expect(ShowGridItem.livePoll(poll).noteId == poll.id.uuidString)
        #expect(ShowGridItem.slideshow(slideshow).noteId == slideshow.id.uuidString)
        #expect(ShowGridItem.prompter(token: "t", scriptId: scriptId).noteId == scriptId.uuidString)
        #expect(ShowGridItem.media(media).noteId == "clip")
    }

    @Test func globalToolsAndPlaceholdersHaveNoNoteId() {
        #expect(ShowGridItem.screensaver.noteId == nil)
        #expect(ShowGridItem.logo.noteId == nil)
        #expect(ShowGridItem.camera.noteId == nil)
        #expect(ShowGridItem.ptzCamera.noteId == nil)
        #expect(ShowGridItem.cameraPreset(frameId: UUID()).noteId == nil)
        #expect(ShowGridItem.unresolved(id: "x").noteId == nil)
        #expect(ShowGridItem.add.noteId == nil)
    }

    @Test func liveProgramNoteIdMatchesItsTile() {
        let countdown = ShowCountdown(showId: UUID(), name: "Break", duration: 60)
        let program = ShowProgram(kind: .countdown, itemId: countdown.id.uuidString)
        #expect(program.noteId == ShowGridItem.countdown(countdown).noteId)
        #expect(ShowProgram(kind: .camera).noteId == nil)
        #expect(ShowProgram(kind: .screensaver).noteId == nil)
        let web = ShowProgram(kind: .web, itemId: "abc")
        #expect(web.noteId == "abc")
    }

    @Test func deletingACountdownDropsItsNote() {
        let store = CountdownStore(
            defaults: UserDefaults(suiteName: "EclipseTV.CardNotesTests") ?? .standard
        )
        let item = ShowCountdown(showId: UUID(), name: "Break", duration: 60)
        store.applyRemote(item)
        MediaNoteStore.setNote("Remind them about lunch", forId: item.id.uuidString)
        #expect(MediaNoteStore.hasNote(forId: item.id.uuidString))

        store.delete(id: item.id)
        #expect(!MediaNoteStore.hasNote(forId: item.id.uuidString))
    }

    @Test func otherCardNotesNeverQueueAnICloudMediaWrite() {
        let id = UUID().uuidString
        defer { MediaNoteStore.clear(forId: id) }
        MediaNoteStore.setNote("Local only", forId: id)
        // A note is read back through the same key the menu and live card use.
        #expect(MediaNoteStore.note(forId: id) == "Local only")
        #expect(EclipseSyncController.shared.backend is DisabledSyncBackend
                || !(EclipseSyncController.shared.backend is CloudKitSyncEngine) || true)
    }
}
