//
//  LibraryGridViewController+HeroWebInteraction.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//
//  Description: When the live website in the hero may be scrolled and pinched,
//               with the TV following (`HeroWebViewportSync`).
//  Thread Safety: Main actor only.
//

import UIKit

// MARK: - Hero Website Interaction

extension LibraryGridViewController {

    /// Whether the hero's website is this Show's live program and may move the TV.
    ///
    /// Same rules as the hero's other direct adjustments: never while output is
    /// locked, during Blackout, for a phone Preview or another Show's live, or while
    /// following a director. A QuestPoll stage is a website too, but never scrolls.
    var allowsHeroWebInteraction: Bool {
        let mgr = ExternalDisplayManager.shared
        return showsLiveHero
            && mgr.isWebLive
            && !mgr.isQuestPollLive
            && heroPhonePreview == nil
            && !isBlackoutHolding
            && !isLiveFromOtherShow
            && !isLiveOutputLocked
            && !ShowLiveSession.shared.isRemoteOperator
    }

    /// Whether scrolling or pinching the hero's live PDF may move the TV: the same
    /// rules as the website. Otherwise the PDF still moves on the phone only.
    var allowsHeroPDFOutput: Bool {
        let mgr = ExternalDisplayManager.shared
        return showsLiveHero
            && mgr.isPDFLive
            && heroPhonePreview == nil
            && !isBlackoutHolding
            && !isLiveFromOtherShow
            && !isLiveOutputLocked
            && !ShowLiveSession.shared.isRemoteOperator
    }

    /// Re-reads `allowsHeroWebInteraction` (and the PDF's output rule) onto the hero.
    func syncHeroWebInteraction() {
        liveHeader.pdfPreviewDriver?.allowsOutput = { [weak self] in
            self?.allowsHeroPDFOutput ?? false
        }
        liveHeader.webPreviewSync.drivesOutput = { [weak self] in
            self?.allowsHeroWebInteraction ?? false
        }
        liveHeader.allowsWebPreviewInteraction = allowsHeroWebInteraction
    }
}
