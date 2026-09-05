//
//  LibraryGridViewController+LiveLock.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import UIKit

// MARK: - Live Output Lock

extension LibraryGridViewController {

    /// Toggles lock: live output stays put; media / Screensaver / Background
    /// taps open phone Preview instead.
    func toggleLiveOutputLock() {
        isLiveOutputLocked.toggle()
        applyLiveOutputLockChrome()
        // Operators mirror the director's lock, so they must hear about it.
        broadcastShowLiveSnapshotIfNeeded()
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
    }

    /// Updates header, hero stroke, and visible tile accents for the lock state.
    func applyLiveOutputLockChrome() {
        onLiveOutputLockChanged?(isLiveOutputLocked)
        liveHeader.setOutputLocked(isLiveOutputLocked)
        let visible = collectionView.indexPathsForVisibleItems
        if !visible.isEmpty {
            collectionView.reconfigureItems(at: visible)
        }
    }

    /// Returns `true` when a live-changing action should abort (toast + haptic).
    @discardableResult
    func blockLiveChangeIfLocked() -> Bool {
        guard isLiveOutputLocked else { return false }
        UINotificationFeedbackGenerator().notificationOccurred(.warning)
        showPresentationToast("Live output is locked")
        return true
    }
}
