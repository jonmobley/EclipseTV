//
//  HeroPhonePreview.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import Foundation

/// Rules for showing a tapped tile in the live hero on this phone only.
///
/// While Live Lock or Blackout holds the audience's screen, a tile tap must not
/// change what the room sees. Instead of opening a fullscreen Preview, the tapped
/// item takes over the hero with a PREVIEW badge, so the operator can look ahead
/// without leaving the Show. The TV never hears about it. Tapping the previewed
/// tile again (or the hero's expand control) opens it full screen; Back to Live,
/// tapping the live tile, or ending Lock / Blackout puts the hero back on program.
enum HeroPhonePreview {

    /// Where a tile tap lands.
    enum TapSurface: Equatable {
        /// Normal tap: the item goes live.
        case live
        /// Lock / Blackout with a live hero: the item shows in the hero, phone only.
        case hero
        /// No destination (or no hero to borrow): fullscreen phone Preview.
        case fullscreen
    }

    /// What a hero-preview tap on a tile does, given what the hero shows now.
    enum TapAction: Equatable {
        /// Show the tapped item in the hero.
        case preview
        /// The tile is already previewed: open it full screen.
        case openFullscreen
        /// The tile is what is live (or held by Blackout): drop the preview.
        case backToLive
    }

    /// Surface for a tap, from the same flags `prefersPhonePreviewOnTap` reads.
    ///
    /// The hero is only borrowed while Lock or Blackout is the reason for the
    /// Preview. With nothing connected there is no live hero to borrow, and an
    /// operator's hero is a monitor of the director's program, so both keep the
    /// fullscreen Preview.
    static func tapSurface(
        isLiveOutputLocked: Bool,
        isBlackoutHolding: Bool,
        hasOutputDestination: Bool,
        showsLiveHero: Bool,
        isRemoteOperator: Bool
    ) -> TapSurface {
        let prefersPreview = LiveOutputRouting.prefersPhonePreviewOnTap(
            isLiveOutputLocked: isLiveOutputLocked,
            hasOutputDestination: hasOutputDestination,
            isBlackoutHolding: isBlackoutHolding
        )
        guard prefersPreview else { return .live }
        guard isLiveOutputLocked || isBlackoutHolding,
              hasOutputDestination,
              showsLiveHero,
              !isRemoteOperator else { return .fullscreen }
        return .hero
    }

    /// Tile kinds that can stand in the hero as a phone preview.
    ///
    /// Tools (camera, poll, countdown, prompter) have no private preview, and a
    /// slideshow plays rather than shows, so those keep their own tap rules.
    static func canPreview(_ item: ShowGridItem) -> Bool {
        switch item {
        case .media, .pdf, .logo, .screensaver:
            return true
        case .website(let page):
            // A video link has no phone picture to show; it keeps its own rules.
            return page.videoLink == nil
        case .slideshow, .livePoll, .camera, .cameraPreset, .ptzCamera, .countdown,
             .prompter, .template, .unresolved, .add:
            return false
        }
    }

    /// Tap action for a tile whose selection id is `tappedId`.
    static func tapAction(
        tappedId: String?,
        previewedId: String?,
        isLiveOrHeld: Bool
    ) -> TapAction {
        if let tappedId, tappedId == previewedId { return .openFullscreen }
        if isLiveOrHeld { return .backToLive }
        return .preview
    }
}
