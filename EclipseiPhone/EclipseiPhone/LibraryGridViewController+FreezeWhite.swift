//
//  LibraryGridViewController+FreezeWhite.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import UIKit

// MARK: - Freeze and White

/// Freeze holds the audience's picture still while the phone keeps working;
/// White turns the audience screen solid white (lighting, projector alignment).
///
/// Both act on the external (AirPlay / cable) screen through
/// `ExternalDisplayHoldOverlay`. Lock and Freeze exclude each other, as do
/// Blackout and White (rules in `LiveOutputHoldState`).
extension LibraryGridViewController {

    // MARK: Freeze

    /// Header Freeze control: holds the audience screen still, or lets it go.
    ///
    /// Freezing turns Lock off. Un-freezing shows whatever is live now.
    func toggleFreeze() {
        if sendShowLiveCommandIfOperator(.freezeToggle) {
            Haptics.impactLight()
            return
        }
        let overlay = ExternalDisplayHoldOverlay.shared
        syncOutputHold()
        if outputHold.isFrozen {
            overlay.hideFreeze()
            outputHold.toggleFreeze()
        } else {
            guard outputHold.canFreeze else {
                Haptics.warning()
                showPresentationToast("Turn off Blackout or White to freeze")
                return
            }
            guard ExternalDisplayManager.shared.holdOverlayWindow != nil else {
                Haptics.warning()
                showPresentationToast("Connect a screen to freeze it")
                return
            }
            if isLiveOutputLocked { toggleLiveOutputLock() }
            guard overlay.showFreeze(on: ExternalDisplayManager.shared.holdOverlayWindow)
            else { return }
            syncOutputHold()
            outputHold.toggleFreeze()
        }
        Haptics.impactMedium()
        applyOutputHoldChrome()
    }

    // MARK: White

    /// Header Blackout menu › White: solid white on the audience screen, or off.
    ///
    /// Turning White on ends Blackout and Freeze.
    func toggleWhiteLive() {
        if sendShowLiveCommandIfOperator(.whiteToggle) {
            Haptics.impactLight()
            return
        }
        let overlay = ExternalDisplayHoldOverlay.shared
        syncOutputHold()
        if outputHold.isWhite {
            overlay.hideWhite()
            outputHold.toggleWhite()
        } else {
            guard let window = ExternalDisplayManager.shared.holdOverlayWindow else {
                Haptics.warning()
                showPresentationToast("Connect a screen to show white")
                return
            }
            // Black ends first (its restore runs under the white cover).
            if isBlackSelected { endBlackoutHold() }
            overlay.hideFreeze()
            overlay.showWhite(on: window)
            syncOutputHold()
            outputHold.toggleWhite()
        }
        Haptics.impactMedium()
        refreshLiveHeader()
    }

    /// Header Blackout menu › Black: black screen, ending White first.
    func selectBlackLive() {
        if outputHold.isWhite, !ShowLiveSession.shared.isRemoteOperator {
            ExternalDisplayHoldOverlay.shared.hideWhite()
            outputHold.toggleWhite()
        }
        if !isBlackSelected { toggleBlackLive() }
        applyOutputHoldChrome()
    }

    // MARK: State

    /// Copies Lock and Blackout into the hold state so its rules see them.
    func syncOutputHold() {
        outputHold.setLocked(isLiveOutputLocked)
        outputHold.setBlack(isBlackSelected)
    }

    /// Drops overlays the rules no longer allow, then tells the header.
    ///
    /// Runs on every live refresh: Lock on or Blackout on (from any path, such as a
    /// countdown ending) must not leave a still or white cover over the screen.
    func applyOutputHoldChrome() {
        let overlay = ExternalDisplayHoldOverlay.shared
        if ShowLiveSession.shared.isRemoteOperator {
            let snap = ShowLiveSession.shared.snapshot
            onFreezeChanged?(snap?.isFrozen ?? false)
            onWhiteChanged?(snap?.isWhite ?? false)
            return
        }
        syncOutputHold()
        if !outputHold.isFrozen, overlay.isFreezeShown { overlay.hideFreeze() }
        if !outputHold.isWhite, overlay.isWhiteShown { overlay.hideWhite() }
        if ExternalDisplayManager.shared.holdOverlayWindow == nil {
            outputHold.clearFreeze()
            outputHold.clearWhite()
        }
        onFreezeChanged?(outputHold.isFrozen)
        onWhiteChanged?(outputHold.isWhite)
        broadcastShowLiveSnapshotIfNeeded()
    }
}
