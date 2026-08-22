//
//  iPhoneMainViewController+AudioMiniChrome.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import UIKit

// MARK: - Ambient mini player ↔ bubble chrome

extension iPhoneMainViewController {

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
    /// An active session expands on tap; chevron collapses; long-press stops.
    func refreshAudioMiniPlayer() {
        if isAudioMiniChromeAnimating {
            audioMiniPlayer.reload()
            audioMiniBubble.reload()
            return
        }

        let active = AudioPlayerController.shared.hasActiveSession
        if !active { audioMiniCollapsed = true }

        let showBar = active && !audioMiniCollapsed
        let showBubble = !showBar

        audioMiniPlayer.reload()
        audioMiniBubble.reload()

        let height: CGFloat = showBar ? AudioMiniPlayerView.preferredHeight : 0
        audioMiniHeightConstraint?.constant = height
        audioMiniPlayer.isHidden = !showBar
        audioMiniPlayer.alpha = 1
        audioMiniPlayer.transform = .identity
        audioMiniBubble.isHidden = !showBubble
        audioMiniBubble.alpha = 1
        audioMiniBubble.transform = .identity

        applyMiniPlayerBottomInset(height)
        libraryViewController.refreshMusicSwipeHintVisibility()
        view.layoutIfNeeded()
        if showBubble {
            offerMusicBubbleTipIfNeeded()
        }
    }

    private static let musicBubbleTipKey = "EclipseTV.home.musicBubbleTipShown"

    /// One-time tip when the collapsed music circle first appears.
    private func offerMusicBubbleTipIfNeeded() {
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: Self.musicBubbleTipKey) else { return }
        defaults.set(true, forKey: Self.musicBubbleTipKey)
        showTemporaryStatus("Tap Music anytime · Hold to stop", duration: 4)
    }

    // MARK: - Morph animations

    private func animateExpandToBar() {
        isAudioMiniChromeAnimating = true
        UIImpactFeedbackGenerator(style: .soft).impactOccurred()

        let bar = audioMiniPlayer
        let bubble = audioMiniBubble
        let height = AudioMiniPlayerView.preferredHeight

        bar.reload()
        bubble.reload()

        bar.isHidden = false
        bar.alpha = 0
        audioMiniHeightConstraint?.constant = height
        applyMiniPlayerBottomInset(height)
        view.layoutIfNeeded()

        bar.transform = Self.barMorphTransform(for: bar.bounds, height: height)
        bar.layer.cornerRadius = height / 2
        bar.clipsToBounds = true

        bubble.isHidden = false
        bubble.alpha = 1
        bubble.transform = .identity

        UIView.animate(
            withDuration: 0.52,
            delay: 0,
            usingSpringWithDamping: 0.84,
            initialSpringVelocity: 0.55,
            options: [.allowUserInteraction, .beginFromCurrentState]
        ) {
            bubble.transform = CGAffineTransform(scaleX: 0.28, y: 0.28)
            bubble.alpha = 0
            bar.transform = .identity
            bar.alpha = 1
            bar.layer.cornerRadius = self.audioMiniRestingCornerRadius
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
        let height = AudioMiniPlayerView.preferredHeight

        bar.reload()
        bubble.reload()

        // Keep bar height while morphing so the trailing-scale math stays stable.
        audioMiniHeightConstraint?.constant = height
        bar.isHidden = false
        bar.alpha = 1
        bar.transform = .identity
        bar.layer.cornerRadius = audioMiniRestingCornerRadius
        bar.clipsToBounds = true
        view.layoutIfNeeded()

        let toBar = Self.barMorphTransform(for: bar.bounds, height: height)

        bubble.isHidden = false
        bubble.alpha = 0
        bubble.transform = CGAffineTransform(scaleX: 0.28, y: 0.28)

        applyMiniPlayerBottomInset(0)

        UIView.animate(
            withDuration: 0.46,
            delay: 0,
            usingSpringWithDamping: 0.9,
            initialSpringVelocity: 0.4,
            options: [.allowUserInteraction, .beginFromCurrentState]
        ) {
            bar.transform = toBar
            bar.alpha = 0
            bar.layer.cornerRadius = height / 2
            bubble.transform = .identity
            bubble.alpha = 1
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
        audioMiniBubble.isHidden = true
        audioMiniBubble.transform = .identity
        audioMiniBubble.alpha = 1
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
        audioMiniBubble.transform = .identity
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
        audioMiniPlayer.transform = .identity
        audioMiniPlayer.alpha = 1
        audioMiniPlayer.clipsToBounds = false
        audioMiniPlayer.layer.cornerRadius = audioMiniRestingCornerRadius
    }

    private var audioMiniRestingCornerRadius: CGFloat {
        isAudioMiniLandscapeCompact ? AudioMiniPlayerView.compactCornerRadius : 0
    }

    private func applyMiniPlayerBottomInset(_ height: CGFloat) {
        syncAudioMiniLayoutIfNeeded()
        // Landscape card sits over the grid, not under the live preview — never
        // steal height from the hero.
        libraryViewController.sideBySideMiniPlayerHeight = 0
        libraryViewController.miniPlayerBottomInset = height
        audioLibraryViewController.miniPlayerBottomInset = height
    }

    /// Compact trailing card in phone landscape; full-width footer otherwise.
    @discardableResult
    func syncAudioMiniLayoutIfNeeded() -> Bool {
        let compact = traitCollection.verticalSizeClass == .compact
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
            view.layoutIfNeeded()
        }
        if compact { updateLandscapeCompactWidth() }
        return axisChanged
    }

    private func updateLandscapeCompactWidth() {
        let safe = view.safeAreaInsets
        let available = view.bounds.width - safe.left - safe.right
            - AudioMiniPlayerView.compactTrailingInset * 2
        audioMiniLandscapeWidthConstraint?.constant = min(
            AudioMiniPlayerView.compactWidth,
            max(280, available)
        )
    }

    /// Scale about center, then nudge so the trailing-bottom corner stays planted
    /// (the bubble growing into the bar).
    private static func barMorphTransform(
        for bounds: CGRect,
        height: CGFloat
    ) -> CGAffineTransform {
        let width = max(bounds.width, 1)
        let h = max(bounds.height > 1 ? bounds.height : height, 1)
        let side = AudioMiniPlayerBubbleView.side
        let sx = side / width
        let sy = side / h
        return CGAffineTransform(
            translationX: (1 - sx) * width / 2,
            y: (1 - sy) * h / 2
        ).scaledBy(x: sx, y: sy)
    }
}
