//
//  ShowProgramResolverTests.swift
//  EclipseiPhoneTests
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import Foundation
import Testing
@testable import EclipseiPhone

/// One resolved program, one red live stroke.
///
/// Every case here asserts on the whole grid rather than a single tile: the bug
/// these guard against is two thumbnails claiming live at once, which a per-tile
/// assertion cannot see.
struct ShowProgramResolverTests {

    // MARK: - Fixtures

    private let slideshow = Slideshow(showId: UUID(), name: "Deck", itemIds: ["a.jpg"])
    private let page = WebPage(title: "Example", url: URL(string: "https://example.com")!)
    private let pdf = SavedPDF(title: "Runsheet")
    private let countdown = ShowCountdown(showId: UUID(), name: "Break", duration: 60)
    private let poll = ShowLivePoll(
        showId: UUID(),
        pollId: "poll-1",
        title: "Session 1",
        questionCount: 3
    )
    private let still = LibraryItemDTO(
        id: "a.jpg",
        name: "a.jpg",
        isVideo: false,
        duration: 0,
        isAvailable: true
    )

    /// Every kind of tile a Show can hold, so a stray match cannot hide.
    private var grid: [ShowGridItem] {
        [
            .slideshow(slideshow), .website(page), .pdf(pdf), .countdown(countdown),
            .livePoll(poll), .media(still), .camera, .logo, .screensaver,
            .unresolved(id: "pending"), .add
        ]
    }

    private func liveTiles(_ state: ShowProgramState) -> [ShowGridItem] {
        guard let program = ShowProgramResolver.resolve(state) else { return [] }
        return grid.filter { program.matches($0) }
    }

    // MARK: - The Reported Bug

    @Test func aLiveWebsiteLeavesNoStrokeOnAStaleSlideshow() {
        var state = ShowProgramState()
        state.isOverlayLive = true
        state.webPageId = page.id
        state.slideshowId = slideshow.id
        #expect(liveTiles(state) == [.website(page)])
    }

    @Test func aLiveSlideshowLeavesNoStrokeOnItsOwnSlide() {
        var state = ShowProgramState()
        state.slideshowId = slideshow.id
        // Each slide going out sets the library's current id.
        state.mediaId = still.id
        #expect(liveTiles(state) == [.slideshow(slideshow)])
    }

    @Test func aPracticedPollLosesToAnythingThatReachesOutput() {
        var state = ShowProgramState()
        state.practicePollMembershipId = poll.id
        #expect(liveTiles(state) == [.livePoll(poll)])

        state.mediaId = still.id
        #expect(liveTiles(state) == [.media(still)])

        state.mediaId = nil
        state.slideshowId = slideshow.id
        #expect(liveTiles(state) == [.slideshow(slideshow)])
    }

    // MARK: - Priority

    @Test func nothingIsLiveWhenNoStoreOwnsOutput() {
        #expect(ShowProgramResolver.resolve(ShowProgramState()) == nil)
        #expect(liveTiles(ShowProgramState()).isEmpty)
    }

    @Test func anUnidentifiedOverlayLeavesEveryTileDark() {
        // A page put live without a bookmark id still owns the display, so the
        // library still underneath it must not take the stroke.
        var state = ShowProgramState()
        state.isOverlayLive = true
        state.mediaId = still.id
        #expect(ShowProgramResolver.resolve(state) == nil)
        #expect(liveTiles(state).isEmpty)
    }

    @Test func blackoutOwnsProgramOnlyWhileNoOverlayIsUp() {
        var state = ShowProgramState()
        state.isBlackSelected = true
        state.mediaId = still.id
        #expect(ShowProgramResolver.resolve(state) == ShowProgram(kind: .black))
        // Blackout is header chrome, not a card.
        #expect(liveTiles(state).isEmpty)

        state.isOverlayLive = true
        state.webPageId = page.id
        #expect(liveTiles(state) == [.website(page)])
    }

    @Test func cameraOutranksTheLibraryAndTheTools() {
        var state = ShowProgramState()
        state.isOverlayLive = true
        state.isCameraTileLive = true
        state.mediaId = still.id
        state.isLogoSelected = true
        #expect(liveTiles(state) == [.camera])
    }

    @Test func aPollRoomOutranksItsProjectorPage() {
        // The room's projector page is a website overlay; the card is what the
        // user put live.
        var state = ShowProgramState()
        state.isOverlayLive = true
        state.questPollMembershipId = poll.id
        state.webPageId = page.id
        #expect(liveTiles(state) == [.livePoll(poll)])
    }

    @Test func aWebVideoCardIsLiveWithoutAWebPageId() {
        var state = ShowProgramState()
        state.webVideoPageId = page.id
        #expect(liveTiles(state) == [.website(page)])
    }

    @Test func aLivePDFOutranksTheToolsBeneathIt() {
        var state = ShowProgramState()
        state.isOverlayLive = true
        state.pdfDocumentId = pdf.id
        state.isScreensaverSelected = true
        #expect(liveTiles(state) == [.pdf(pdf)])
    }

    @Test func aLiveCountdownIsTheOnlyLiveTile() {
        var state = ShowProgramState()
        state.isOverlayLive = true
        state.countdownId = countdown.id
        state.mediaId = still.id
        #expect(liveTiles(state) == [.countdown(countdown)])
    }

    @Test func toolsRankAboveTheLibraryStillTheyReplaced() {
        var state = ShowProgramState()
        state.isLogoSelected = true
        state.mediaId = still.id
        #expect(liveTiles(state) == [.logo])

        state.isLogoSelected = false
        state.isScreensaverSelected = true
        #expect(liveTiles(state) == [.screensaver])
    }

    // MARK: - Operator Agreement

    @Test func anOperatorPaintsTheSameTileAsTheDirector() {
        var state = ShowProgramState()
        state.isOverlayLive = true
        state.webPageId = page.id
        state.slideshowId = slideshow.id
        let local = ShowProgramResolver.resolve(state)
        let snapshot = ShowLiveSnapshot(
            showId: UUID(),
            liveItemId: local?.itemId,
            liveKind: local?.kind,
            isBlackout: local?.kind == .black,
            isLocked: false,
            directorName: "Director"
        )
        let mirrored = ShowProgram(snapshot: snapshot)
        #expect(mirrored == local)
        #expect(grid.filter { mirrored?.matches($0) == true } == [.website(page)])
    }

    @Test func aBlackedOutDirectorLeavesTheOperatorGridDark() {
        let snapshot = ShowLiveSnapshot(
            showId: UUID(),
            liveItemId: nil,
            liveKind: .black,
            isBlackout: true,
            isLocked: false,
            directorName: "Director"
        )
        #expect(ShowProgram(snapshot: snapshot) == nil)
    }
}
