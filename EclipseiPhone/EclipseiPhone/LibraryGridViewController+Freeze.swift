//
//  LibraryGridViewController+Freeze.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import UIKit

// MARK: - Freeze and Blackout Colour

/// Freeze holds the audience screen on what it shows now, as on the Mac.
///
/// It is Lock with the picture held still: Lock's hold comes with it (tile
/// taps open a phone Preview), the AirPlay / HDMI screen keeps a still of
/// the moment, and a playing video pauses on the TV and on AirPlay. Only one
/// of Lock and Freeze is lit at a time. Tapping Lock while frozen goes back
/// to moving Lock; tapping Blackout ends Freeze first.
extension LibraryGridViewController {

    // MARK: Freeze

    /// Turns Freeze on or off (header snowflake).
    func toggleLiveOutputFreeze() {
        if sendShowLiveCommandIfOperator(.freezeToggle) {
            Haptics.impactMedium()
            return
        }
        if isLiveOutputFrozen {
            endLiveOutputFreeze(keepingLock: wasLockedBeforeFreeze)
        } else {
            guard !isBlackSelected else {
                Haptics.warning()
                showPresentationToast("Blackout is on. Turn it off to freeze.")
                return
            }
            beginLiveOutputFreeze()
        }
        Haptics.impactMedium()
    }

    /// Holds every audience screen still and brings Lock's hold with it.
    func beginLiveOutputFreeze() {
        wasLockedBeforeFreeze = isLiveOutputLocked
        isLiveOutputFrozen = true
        isLiveOutputLocked = true
        ExternalDisplayManager.shared.beginFreeze()
        freezePausedTVVideo = false
        if store.isOnline, store.playback.isPlaying {
            freezePausedTVVideo = connectionManager.sendPlaybackCommand(
                action: .pause, position: nil
            )
        }
        freezePausedHeroVideo = liveHeader.libraryVideoPlaybackState.isPlaying
        if freezePausedHeroVideo {
            liveHeader.pauseLibraryVideoPreview()
        }
        applyFreezeChrome()
    }

    /// Lets the audience screens move again.
    /// - Parameter keepingLock: Leave Lock on afterwards (Lock tapped while
    ///   frozen, or Lock was on before Freeze)
    func endLiveOutputFreeze(keepingLock: Bool) {
        guard isLiveOutputFrozen else { return }
        isLiveOutputFrozen = false
        isLiveOutputLocked = keepingLock
        wasLockedBeforeFreeze = false
        ExternalDisplayManager.shared.endFreeze()
        if freezePausedTVVideo, store.isOnline {
            _ = connectionManager.sendPlaybackCommand(action: .play, position: nil)
        }
        freezePausedTVVideo = false
        if freezePausedHeroVideo {
            liveHeader.resumeLibraryVideoPreview()
        }
        freezePausedHeroVideo = false
        applyFreezeChrome()
    }

    /// Header, hero and tiles after Freeze or Lock changed.
    func applyFreezeChrome() {
        onLiveOutputFreezeChanged?(isLiveOutputFrozen)
        liveHeader.setOutputFrozen(isLiveOutputFrozen)
        applyLiveOutputLockChrome()
        clearHeroPhonePreview()
        broadcastShowLiveSnapshotIfNeeded()
        refreshLiveHeader()
    }

    // MARK: Blackout Colour

    /// Picks Blackout's colour. While Blackout is on, the screen changes at once.
    /// - Parameter kind: Black or White
    func selectOutputBlankKind(_ kind: OutputBlankKind) {
        if sendShowLiveCommandIfOperator(.blankKindSet, value: kind == .white ? 1 : 0) {
            Haptics.impactLight()
            return
        }
        guard OutputBlankKind.current != kind else { return }
        OutputBlankKind.current = kind
        onOutputBlankKindChanged?(kind)
        ExternalDisplayManager.shared.applyBlankCover()
        if isBlackSelected, AirPlayOverlayPark.isParkedForBlackout {
            AirPlayOverlayPark.park(using: connectionManager)
        }
        Haptics.impactLight()
        broadcastShowLiveSnapshotIfNeeded()
        refreshLiveHeader()
    }
}
