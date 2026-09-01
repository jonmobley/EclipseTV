//
//  iPhoneMainViewController+AudioMiniChrome.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import UIKit

// MARK: - Ambient mini player ↔ bubble chrome

extension iPhoneMainViewController {

    /// Fades out and tears down the ambient session, returning to the idle Music bubble.
    func stopAmbientPlayback() {
        AudioPlayerController.shared.stop()
        audioMiniCollapsed = true
        isAudioMiniChromeAnimating = false
        HomeMusicSwipeHint.markEligibleAfterMiniPlayerClose()
        libraryViewController.refreshMusicSwipeHintVisibility()
        refreshAudioMiniPlayer()
    }

    /// Circle tap: expand when collapsed, stop when the footer is showing;
    /// idle opens the picker.
    func handleAudioMiniBubbleToggle() {
        if AudioPlayerController.shared.hasActiveSession {
            if audioMiniCollapsed {
                setAudioMiniCollapsed(false, animated: true)
            } else {
                stopAmbientPlayback()
            }
        } else {
            presentMusicPicker()
        }
    }

    /// Refreshes chrome and dismisses the Music picker when a session first starts.
    func handleAudioPlayerDidChange() {
        let active = AudioPlayerController.shared.hasActiveSession
        let sessionJustStarted = active && !hadActiveAudioSession
        hadActiveAudioSession = active
        refreshAudioMiniPlayer()
        if sessionJustStarted {
            dismissPresentedMusicPicker()
        }
    }

    /// Expands or collapses ambient chrome. User gestures pass `animated: true`.
    func setAudioMiniCollapsed(_ collapsed: Bool, animated: Bool) {
        guard AudioPlayerController.shared.hasActiveSession else {
            audioMiniCollapsed = true
            refreshAudioMiniPlayer()
            return
        }
        let reduceMotion = UIAccessibility.isReduceMotionEnabled
        let shouldAnimate = animated && !reduceMotion
        guard collapsed != audioMiniCollapsed else {
            if !shouldAnimate { refreshAudioMiniPlayer() }
            return
        }

        if collapsed {
            HomeMusicSwipeHint.markEligibleAfterMiniPlayerClose()
        }
        if isAudioMiniChromeAnimating {
            finishAudioMiniChromeAnimation(collapsed: collapsed)
            return
        }

        audioMiniCollapsed = collapsed
        guard shouldAnimate else {
            refreshAudioMiniPlayer()
            return
        }

        if collapsed {
            animateCollapseToBubble()
        } else {
            animateExpandToBar()
        }
    }

    /// Shows the mini bar or the persistent Music bubble, and insets Library + Music.
    ///
    /// The corner button stays up even when idle so Music is always one tap away.
    /// Circle expands the bar (or opens the picker when idle); the same circle
    /// becomes Stop while expanded; chevron collapses.
    func refreshAudioMiniPlayer() {
        if isAudioMiniChromeAnimating {
            let showBar = AudioPlayerController.shared.hasActiveSession
                && !audioMiniCollapsed
            audioMiniPlayer.reload()
            audioMiniBubble.reload(barExpanded: showBar)
            return
        }

        let active = AudioPlayerController.shared.hasActiveSession
        if !active { audioMiniCollapsed = true }

        let showBar = active && !audioMiniCollapsed
        if !showBar {
            audioMiniPlayer.collapseVolumeControl()
        }

        audioMiniPlayer.reload()
        audioMiniBubble.reload(barExpanded: showBar)
        view.bringSubviewToFront(audioMiniBubble)

        let chromeHeight: CGFloat = showBar ? AudioMiniPlayerView.preferredHeight : 0
        audioMiniHeightConstraint?.constant = showBar ? audioMiniBarHeight() : 0
        audioMiniPlayer.isHidden = !showBar
        audioMiniPlayer.alpha = 1
        audioMiniPlayer.transform = .identity
        audioMiniBubble.isHidden = false
        audioMiniBubble.alpha = 1
        audioMiniBubble.transform = .identity

        applyMiniPlayerBottomInset(chromeHeight)
        libraryViewController.refreshMusicSwipeHintVisibility()
        view.layoutIfNeeded()
    }

    // MARK: - Music picker dismiss

    /// Closes the presented Music picker (not the embedded Music page).
    private func dismissPresentedMusicPicker() {
        guard let picker = openController(ofType: AudioLibraryViewController.self),
              picker.presentingViewController != nil
                || picker.navigationController?.presentingViewController != nil
        else { return }
        let host = picker.navigationController ?? picker
        host.dismiss(animated: true)
    }

    // MARK: - Fade animations

    private func animateExpandToBar() {
        isAudioMiniChromeAnimating = true
        UIImpactFeedbackGenerator(style: .soft).impactOccurred()

        let bar = audioMiniPlayer
        let bubble = audioMiniBubble
        bar.reload()
        bubble.reload(barExpanded: true)
        bar.collapseVolumeControl()

        bar.isHidden = false
        bar.alpha = 0
        audioMiniHeightConstraint?.constant = audioMiniBarHeight()
        applyMiniPlayerBottomInset(AudioMiniPlayerView.preferredHeight)
        view.bringSubviewToFront(bubble)
        view.layoutIfNeeded()

        bubble.isHidden = false
        bubble.alpha = 1

        UIView.animate(
            withDuration: 0.2,
            delay: 0,
            options: [.curveEaseOut, .beginFromCurrentState]
        ) {
            bar.alpha = 1
            self.view.layoutIfNeeded()
        } completion: { [weak self] finished in
            self?.completeExpandAnimation(finished: finished)
        }
    }

    private func animateCollapseToBubble() {
        isAudioMiniChromeAnimating = true
        UIImpactFeedbackGenerator(style: .light).impactOccurred()

        let bar = audioMiniPlayer
        let bubble = audioMiniBubble
        bar.reload()
        bubble.reload(barExpanded: false)
        bar.collapseVolumeControl()

        audioMiniHeightConstraint?.constant = audioMiniBarHeight()
        bar.isHidden = false
        bar.alpha = 1
        bubble.isHidden = false
        bubble.alpha = 1
        view.bringSubviewToFront(bubble)
        view.layoutIfNeeded()
        applyMiniPlayerBottomInset(0)

        UIView.animate(
            withDuration: 0.2,
            delay: 0,
            options: [.curveEaseOut, .beginFromCurrentState]
        ) {
            bar.alpha = 0
            self.view.layoutIfNeeded()
        } completion: { [weak self] finished in
            self?.completeCollapseAnimation(finished: finished)
        }
    }

    private func completeExpandAnimation(finished: Bool) {
        defer { isAudioMiniChromeAnimating = false }
        guard finished, !audioMiniCollapsed else {
            refreshAudioMiniPlayer()
            return
        }
        audioMiniBubble.isHidden = false
        audioMiniBubble.alpha = 1
        view.bringSubviewToFront(audioMiniBubble)
        resetBarChromeAppearance()
        libraryViewController.refreshMusicSwipeHintVisibility()
    }

    private func completeCollapseAnimation(finished: Bool) {
        defer { isAudioMiniChromeAnimating = false }
        guard finished, audioMiniCollapsed else {
            refreshAudioMiniPlayer()
            return
        }
        audioMiniHeightConstraint?.constant = 0
        audioMiniPlayer.isHidden = true
        resetBarChromeAppearance()
        audioMiniBubble.isHidden = false
        audioMiniBubble.alpha = 1
        libraryViewController.refreshMusicSwipeHintVisibility()
    }

    /// Snaps chrome when a second gesture arrives mid-animation.
    private func finishAudioMiniChromeAnimation(collapsed: Bool) {
        audioMiniCollapsed = collapsed
        audioMiniPlayer.layer.removeAllAnimations()
        audioMiniBubble.layer.removeAllAnimations()
        view.layer.removeAllAnimations()
        isAudioMiniChromeAnimating = false
        resetBarChromeAppearance()
        refreshAudioMiniPlayer()
    }

    private func resetBarChromeAppearance() {
        audioMiniPlayer.alpha = 1
        audioMiniPlayer.clipsToBounds = false
        audioMiniPlayer.layer.cornerRadius = audioMiniRestingCornerRadius
    }

    private var audioMiniRestingCornerRadius: CGFloat {
        isAudioMiniLandscapeCompact ? AudioMiniPlayerView.compactCornerRadius : 0
    }

    private func applyMiniPlayerBottomInset(_ height: CGFloat) {
        syncAudioMiniLayoutIfNeeded()
        // Compact card sits over the grid, not under the live preview — never
        // steal height from the hero.
        libraryViewController.sideBySideMiniPlayerHeight = 0
        libraryViewController.miniPlayerBottomInset = height
        audioLibraryViewController.miniPlayerBottomInset = height
    }

    /// Compact trailing card in phone landscape and on iPad; full-width on phone portrait.
    @discardableResult
    func syncAudioMiniLayoutIfNeeded() -> Bool {
        let compact = AudioMiniPlayerView.usesCompactCard(
            verticalSizeClass: traitCollection.verticalSizeClass,
            horizontalSizeClass: traitCollection.horizontalSizeClass
        )
        let axisChanged = compact != isAudioMiniLandscapeCompact
        if axisChanged {
            isAudioMiniLandscapeCompact = compact
            if compact {
                NSLayoutConstraint.deactivate(audioMiniPortraitConstraints)
                NSLayoutConstraint.activate(audioMiniLandscapeConstraints)
            } else {
                NSLayoutConstraint.deactivate(audioMiniLandscapeConstraints)
                NSLayoutConstraint.activate(audioMiniPortraitConstraints)
            }
            audioMiniPlayer.applyFloatingChrome(compact)
            audioMiniPlayer.layer.cornerRadius = audioMiniRestingCornerRadius
            updateAudioMiniBarHeightIfNeeded()
            view.layoutIfNeeded()
        }
        if compact { updateLandscapeCompactWidth() }
        updateAudioMiniBarHeightIfNeeded()
        return axisChanged
    }

    /// Full-width footer covers the home indicator; compact card does not.
    private func audioMiniBarHeight() -> CGFloat {
        AudioMiniPlayerView.barHeight(
            floating: isAudioMiniLandscapeCompact,
            safeAreaBottom: view.safeAreaInsets.bottom
        )
    }

    /// Applies footer height after rotation / safe-area changes without fighting
    /// the expand animation.
    private func updateAudioMiniBarHeightIfNeeded() {
        guard !isAudioMiniChromeAnimating else { return }
        let showBar = AudioPlayerController.shared.hasActiveSession && !audioMiniCollapsed
        let next: CGFloat = showBar ? audioMiniBarHeight() : 0
        guard audioMiniHeightConstraint?.constant != next else { return }
        audioMiniHeightConstraint?.constant = next
    }

    private func updateLandscapeCompactWidth() {
        let safe = view.safeAreaInsets
        let available = view.bounds.width - safe.left - safe.right
            - AudioMiniPlayerView.compactTrailingInset * 2
            - AudioMiniPlayerBubbleView.side
            - AudioMiniPlayerView.circleFooterGap
        audioMiniLandscapeWidthConstraint?.constant = min(
            AudioMiniPlayerView.compactWidth,
            max(280, available)
        )
    }
}
