//
//  ShowProgramResolver.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import Foundation

/// Everything that can own live output, sampled at one instant.
///
/// Plain values rather than the singletons themselves, so the priority order can
/// be tested on its own. Each overlay id arrives already narrowed by its own "is
/// this kind live" check: pass `webPageId` only while
/// `ExternalDisplayManager.isWebLive`, `countdownId` only while `isCountdownLive`,
/// and so on.
struct ShowProgramState {

    /// Blackout is selected in the Show header.
    var isBlackSelected = false
    /// Any overlay (camera, web, web video, PDF, countdown) owns output.
    var isOverlayLive = false
    /// Camera tile owns output — the live feed or a parked quick-change still.
    var isCameraTileLive = false
    var countdownId: UUID?
    /// Live Poll card whose room is on program.
    var questPollMembershipId: UUID?
    var webPageId: UUID?
    var webVideoPageId: UUID?
    var pdfDocumentId: UUID?
    var slideshowId: UUID?
    var isLogoSelected = false
    var isScreensaverSelected = false
    /// Library still or video that is live.
    var mediaId: String?
    /// Live Poll card being rehearsed on the phone, with no room and no output.
    var practicePollMembershipId: UUID?
}

/// Picks the single owner of live output out of `ShowProgramState`.
enum ShowProgramResolver {

    /// Resolves program in priority order, or nil when nothing is live.
    ///
    /// The order is the one the director already broadcasts to operators, so a
    /// follow phone and the device it follows cannot disagree about what is live.
    static func resolve(_ state: ShowProgramState) -> ShowProgram? {
        // Blackout is program only while it is really blanking output: an overlay
        // survives the blackout tap and keeps ownership underneath it.
        if state.isBlackSelected && !state.isOverlayLive {
            return ShowProgram(kind: .black)
        }
        if let overlay = resolveOverlay(state) {
            return overlay
        }
        // An overlay is up that no store claims — a page put live without a
        // bookmark id, say. It still owns the display, so no tile is live rather
        // than falling through to a library still nobody can see.
        if state.isOverlayLive {
            return nil
        }
        return resolveLibrary(state)
    }

    // MARK: - Private

    /// Overlays outrank the library: `ExternalDisplayManager.present` tears an
    /// overlay down when a still or a slideshow goes live, so an overlay that is
    /// still up is the newer selection.
    private static func resolveOverlay(_ state: ShowProgramState) -> ShowProgram? {
        if state.isCameraTileLive {
            return ShowProgram(kind: .camera)
        }
        if let id = state.countdownId {
            return ShowProgram(kind: .countdown, itemId: id.uuidString)
        }
        // Before the generic web page: the projector page is a website overlay,
        // and the poll card is the tile the user thinks of as live.
        if let id = state.questPollMembershipId {
            return ShowProgram(kind: .livePoll, itemId: id.uuidString)
        }
        if let id = state.webPageId ?? state.webVideoPageId {
            return ShowProgram(kind: .web, itemId: id.uuidString)
        }
        if let id = state.pdfDocumentId {
            return ShowProgram(kind: .pdf, itemId: id.uuidString)
        }
        return nil
    }

    /// Practice is last: it is a rehearsal on the phone, so anything that reaches
    /// real output supersedes it even when nothing cleared it.
    private static func resolveLibrary(_ state: ShowProgramState) -> ShowProgram? {
        if let id = state.slideshowId {
            return ShowProgram(kind: .slideshow, itemId: id.uuidString)
        }
        if state.isLogoSelected {
            return ShowProgram(kind: .logo)
        }
        if state.isScreensaverSelected {
            return ShowProgram(kind: .screensaver)
        }
        if let id = state.mediaId {
            return ShowProgram(kind: .media, itemId: id)
        }
        if let id = state.practicePollMembershipId {
            return ShowProgram(kind: .livePoll, itemId: id.uuidString)
        }
        return nil
    }
}
