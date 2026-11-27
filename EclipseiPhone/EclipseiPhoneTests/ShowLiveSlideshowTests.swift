//
//  ShowLiveSlideshowTests.swift
//  EclipseiPhoneTests
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import Foundation
import Testing
@testable import EclipseiPhone

/// A second phone running the Show as a remote sees the same slide strip and
/// Fit / Fill button as the phone that owns the TV.
struct ShowLiveSlideshowTests {

    private let showId = UUID()
    private let slideshowId = UUID()

    private func snapshot(
        kind: ShowLiveItemKind? = .slideshow,
        isBlackout: Bool = false,
        slideshow: ShowLiveSlideshowState? = nil,
        screenFit: ShowLiveScreenFitState? = nil
    ) -> ShowLiveSnapshot {
        ShowLiveSnapshot(
            showId: showId,
            liveItemId: slideshowId.uuidString,
            liveKind: kind,
            isBlackout: isBlackout,
            isLocked: false,
            directorName: "Stage iPhone",
            slideshow: slideshow,
            screenFit: screenFit
        )
    }

    @Test func remoteReadsTheDirectorsSlides() throws {
        let view = try #require(LiveSlideshowView(snapshot: snapshot(
            slideshow: ShowLiveSlideshowState(slideIds: ["a", "b", "c"], index: 1)
        )))
        #expect(view.slideshowId == slideshowId)
        #expect(view.slideIds == ["a", "b", "c"])
        #expect(view.currentSlideId == "b")
    }

    @Test func noStripWithoutASlideshowOnProgram() {
        let slides = ShowLiveSlideshowState(slideIds: ["a", "b"], index: 0)
        #expect(LiveSlideshowView(snapshot: nil) == nil)
        #expect(LiveSlideshowView(snapshot: snapshot(kind: .media, slideshow: slides)) == nil)
        #expect(LiveSlideshowView(snapshot: snapshot(isBlackout: true, slideshow: slides)) == nil)
        // An older director reports the slideshow but not its slides.
        #expect(LiveSlideshowView(snapshot: snapshot(slideshow: nil)) == nil)
        // A place outside the slides is a bad report, not slide 0.
        #expect(LiveSlideshowView(snapshot: snapshot(
            slideshow: ShowLiveSlideshowState(slideIds: ["a"], index: 4)
        )) == nil)
    }

    @Test func ownPlayerClampsItsPlace() throws {
        #expect(LiveSlideshowView(playbackSlideshowId: nil, slideIds: ["a"], index: 0) == nil)
        #expect(LiveSlideshowView(playbackSlideshowId: slideshowId, slideIds: [], index: 0) == nil)
        let view = try #require(
            LiveSlideshowView(playbackSlideshowId: slideshowId, slideIds: ["a", "b"], index: 9)
        )
        #expect(view.index == 1)
    }

    @Test func stepsStopAtTheEndsUnlessLooping() throws {
        let first = try #require(
            LiveSlideshowView(playbackSlideshowId: slideshowId, slideIds: ["a", "b"], index: 0)
        )
        #expect(first.canStep(by: 1, loops: false))
        #expect(!first.canStep(by: -1, loops: false))
        #expect(first.canStep(by: -1, loops: true))
        #expect(!first.canStep(by: 0, loops: true))
    }

    @Test func slideAndFitChangesAreProgramChangesNotTicks() {
        let before = snapshot(
            slideshow: ShowLiveSlideshowState(slideIds: ["a", "b"], index: 0),
            screenFit: ShowLiveScreenFitState(isFill: false, showsReset: false)
        )
        var nextSlide = before
        nextSlide.slideshow?.index = 1
        var filled = before
        filled.screenFit?.isFill = true
        #expect(before.isSameProgram(as: before))
        #expect(!nextSlide.isSameProgram(as: before))
        #expect(!filled.isSameProgram(as: before))
    }

    @Test func newFieldsCrossTheWireAndOldReportsStillDecode() throws {
        let sent = snapshot(
            slideshow: ShowLiveSlideshowState(slideIds: ["a", "b"], index: 1),
            screenFit: ShowLiveScreenFitState(isFill: true, showsReset: false)
        )
        let data = try JSONEncoder().encode(
            ShowLiveEnvelope(kind: .state, snapshot: sent)
        )
        let received = try JSONDecoder().decode(ShowLiveEnvelope.self, from: data)
        #expect(received.snapshot == sent)

        // A report from a build before slides and Fit / Fill were mirrored.
        let legacy = """
        {"kind":"state","snapshot":{"showId":"\(showId.uuidString)",\
        "liveItemId":"\(slideshowId.uuidString)","liveKind":"slideshow",\
        "isBlackout":false,"isLocked":false,"directorName":"Stage iPhone"}}
        """
        let old = try JSONDecoder().decode(ShowLiveEnvelope.self, from: Data(legacy.utf8))
        #expect(old.snapshot?.slideshow == nil)
        #expect(old.snapshot?.screenFit == nil)
        #expect(old.snapshot?.liveKind == .slideshow)
    }

    @Test func newCommandVerbsHaveStableNames() throws {
        let verbs: [ShowLiveCommandVerb: String] = [
            .slideStep: "slideStep",
            .slideGoTo: "slideGoTo",
            .screenFitToggle: "screenFitToggle"
        ]
        for (verb, name) in verbs {
            #expect(verb.rawValue == name)
            let data = try JSONEncoder().encode(
                ShowLiveEnvelope(kind: .command, command: ShowLiveCommand(verb: verb, value: 1))
            )
            let back = try JSONDecoder().decode(ShowLiveEnvelope.self, from: data)
            #expect(back.command?.verb == verb)
        }
    }
}
