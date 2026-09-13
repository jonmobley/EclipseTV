//
//  LibraryGridViewController+Program.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import UIKit

// MARK: - Resolved Program

extension LibraryGridViewController {

    /// The one item or tool this device has on live output, if any.
    ///
    /// Director / standalone only — an operator phone follows the director's
    /// snapshot instead (`isShowGridItemLiveRemotely`).
    var resolvedShowProgram: ShowProgram? {
        ShowProgramResolver.resolve(showProgramState())
    }

    /// Samples every store that can own live output into one value.
    ///
    /// - Parameter includingPracticePoll: Practice is a phone rehearsal with no
    ///   room and no output, so the snapshot sent to operators leaves it out.
    func showProgramState(includingPracticePoll: Bool = true) -> ShowProgramState {
        let mgr = ExternalDisplayManager.shared
        let poll = QuestPollSessionStore.shared
        var state = ShowProgramState()
        state.isBlackSelected = isBlackSelected
        state.isOverlayLive = mgr.isOverlayLive
        state.isCameraTileLive = mgr.isCameraTileLive
        state.countdownId = mgr.isCountdownLive
            ? CountdownController.shared.liveCountdownId
            : nil
        state.questPollMembershipId = mgr.isQuestPollLive ? poll.membershipId : nil
        state.webPageId = mgr.isWebLive ? mgr.liveWebPageId : nil
        state.webVideoPageId = mgr.isWebVideoLive ? mgr.liveWebVideoPageId : nil
        state.pdfDocumentId = mgr.isPDFLive ? mgr.livePDFDocumentId : nil
        state.slideshowId = SlideshowPlaybackController.shared.activeSlideshowId
        state.isLogoSelected = isLogoSelected
        state.isScreensaverSelected = isScreensaverSelected
        state.mediaId = store.currentId
        state.practicePollMembershipId = includingPracticePoll
            ? poll.practiceMembershipId
            : nil
        return state
    }

    /// Whether `show` contains the live program item.
    ///
    /// Camera, Background, Screensaver, and Blackout are global tools and belong to no
    /// Show. Media, pages, and PDFs are members by id; slideshows, countdowns, and polls
    /// record their Show on the model, since their tokens live on the surface only.
    func showOwnsLiveProgram(_ show: LocalAlbum) -> Bool {
        guard let program = resolvedShowProgram, let itemId = program.itemId else {
            return false
        }
        switch program.kind {
        case .media, .web, .pdf:
            return show.itemIds.contains(itemId)
        case .slideshow:
            return UUID(uuidString: itemId)
                .flatMap { SlideshowStore.shared.slideshow(id: $0) }?.showId == show.id
        case .countdown:
            return UUID(uuidString: itemId)
                .flatMap { CountdownStore.shared.countdown(id: $0) }?.showId == show.id
        case .livePoll:
            return UUID(uuidString: itemId)
                .flatMap { LivePollStore.shared.poll(id: $0) }?.showId == show.id
        case .camera, .logo, .screensaver, .black:
            return false
        }
    }
}
