//
//  LibraryGridViewController+LiveProgram.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import Foundation

/// What program output is showing right now: one kind and, where it applies, the
/// id of the item. Resolved in one place so the director snapshot, the foreign-Show
/// mini preview, and the Home Show cards cannot disagree about what is live.
struct LiveProgram: Equatable {
    var kind: ShowLiveItemKind
    /// Media id, or the UUID string of a page / PDF / slideshow / countdown / poll.
    var itemId: String?

    var isBlackout: Bool { kind == .black }
}

// MARK: - Tile matching

extension ShowGridItem {

    /// Whether this tile is the item `program` says is live. Shared by the local
    /// tiles and the operator's follow view so both light the same card.
    func matches(_ program: LiveProgram) -> Bool {
        switch self {
        case .slideshow(let show):
            return program.kind == .slideshow && program.itemId == show.id.uuidString
        case .screensaver:
            return program.kind == .screensaver
        case .logo:
            return program.kind == .logo
        case .camera:
            return program.kind == .camera
        case .livePoll(let poll):
            return program.kind == .livePoll && program.itemId == poll.id.uuidString
        case .countdown(let countdown):
            return program.kind == .countdown
                && program.itemId == countdown.id.uuidString
        case .media(let media):
            return program.kind == .media && program.itemId == media.id
        case .website(let page):
            return program.kind == .web && program.itemId == page.id.uuidString
        case .pdf(let doc):
            return program.kind == .pdf && program.itemId == doc.id.uuidString
        case .unresolved, .add:
            return false
        }
    }
}

// MARK: - Resolver

extension LibraryGridViewController {

    /// The live program item, or nil when nothing is on output.
    ///
    /// Priority: Blackout, then the overlays (camera, countdown, poll, website, web
    /// video, PDF) — these own the screen while set — then a running slideshow, the
    /// Background / Screensaver tools, and finally the library item. Black, Background,
    /// and Screensaver are cleared whenever an overlay goes live, so listing overlays
    /// first only matters for the brief window before those flags settle.
    func currentLiveProgram() -> LiveProgram? {
        let mgr = ExternalDisplayManager.shared
        if isBlackSelected && !mgr.isOverlayLive {
            return LiveProgram(kind: .black, itemId: nil)
        }
        if mgr.isCameraTileLive {
            return LiveProgram(kind: .camera, itemId: nil)
        }
        if mgr.isCountdownLive, let id = CountdownController.shared.liveCountdownId {
            return LiveProgram(kind: .countdown, itemId: id.uuidString)
        }
        if mgr.isQuestPollLive, let id = QuestPollSessionStore.shared.membershipId {
            return LiveProgram(kind: .livePoll, itemId: id.uuidString)
        }
        if mgr.isWebLive, let pageId = mgr.liveWebPageId {
            return LiveProgram(kind: .web, itemId: pageId.uuidString)
        }
        if mgr.isWebVideoLive, let pageId = mgr.liveWebVideoPageId {
            return LiveProgram(kind: .web, itemId: pageId.uuidString)
        }
        if mgr.isPDFLive, let docId = mgr.livePDFDocumentId {
            return LiveProgram(kind: .pdf, itemId: docId.uuidString)
        }
        if let slideshowId = SlideshowPlaybackController.shared.activeSlideshowId {
            return LiveProgram(kind: .slideshow, itemId: slideshowId.uuidString)
        }
        if isLogoSelected {
            return LiveProgram(kind: .logo, itemId: nil)
        }
        if isScreensaverSelected {
            return LiveProgram(kind: .screensaver, itemId: nil)
        }
        if let id = store.currentId {
            return LiveProgram(kind: .media, itemId: id)
        }
        return nil
    }

    /// Whether `show` contains the live program item.
    ///
    /// Camera, Background, Screensaver, and Blackout are global tools and belong to no
    /// Show. Media, pages, and PDFs are members by id; slideshows, countdowns, and polls
    /// record their Show on the model, since their tokens live on the surface only.
    func showOwnsLiveProgram(_ show: LocalAlbum) -> Bool {
        guard let program = currentLiveProgram(), let itemId = program.itemId else {
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
