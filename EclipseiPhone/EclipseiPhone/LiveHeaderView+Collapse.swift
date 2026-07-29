//
//  LiveHeaderView+Collapse.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import UIKit

// MARK: - Scroll-Linked Collapse Chrome

/// The host controller shrinks the hero with a uniform `CGAffineTransform` rather
/// than by resizing it, so an embedded live `WKWebView` never relayouts mid-scroll.
/// Everything here compensates for that scale: hairlines, corner radius and the
/// LIVE badge would otherwise shrink along with the artwork.
extension LiveHeaderView {

    /// Full-hero corner radius; the tucked mini preview aims for `compactCornerRadius`.
    private static let expandedCornerRadius: CGFloat = 16
    private static let compactCornerRadius: CGFloat = 12
    /// Design font size of the LIVE badge, and the size it should read as when tucked.
    private static let badgeFontSize: CGFloat = 13
    private static let compactBadgeFontSize: CGFloat = 10

    /// Records the collapse state the host is applying and refreshes derived chrome.
    /// - Parameters:
    ///   - progress: Collapse progress, 0 (full hero) to 1 (tucked mini preview).
    ///   - scale: Uniform transform scale the host applies at this progress.
    func applyCollapse(progress: CGFloat, scale: CGFloat) {
        collapseProgress = min(1, max(0, progress))
        collapseScale = max(0.05, scale)
        applyCollapseChrome()
    }

    /// Re-applies collapse-dependent chrome. Safe to call after any content change.
    func applyCollapseChrome() {
        let progress = collapseProgress
        let inverse = 1 / collapseScale

        // Transport is unusable long before the hero is fully tucked.
        let controlsFade = max(0, 1 - progress * 2.5)
        controls.alpha = controlsFade
        // Assign `isHidden` only on change — this runs inside layout passes.
        let hideControls = !wantsPlaybackControls || controlsFade <= 0.01
        if controls.isHidden != hideControls {
            controls.isHidden = hideControls
        }
        gradientLayer.opacity = Float(controlsFade)
        titleLabel.alpha = max(0, 1 - progress * 2)

        layer.borderWidth = inverse
        layer.cornerRadius = Self.expandedCornerRadius * (1 - progress)
            + Self.compactCornerRadius * inverse * progress
        applyBadgeCounterScale()
        applyInteractionForPresentation()
        accessibilityHint = isCompactPresentation ? "Double tap to expand" : nil
    }

    /// Grows the LIVE badge in local space so it stays legible once scaled down,
    /// anchored at its top-leading corner so it keeps hugging the edge.
    /// Re-applied from `layoutSubviews` because it needs a measured badge size.
    func applyBadgeCounterScale() {
        let size = liveBadge.bounds.size
        guard size.width > 1, size.height > 1 else {
            liveBadge.transform = .identity
            return
        }
        let target = (Self.compactBadgeFontSize / Self.badgeFontSize) / collapseScale
        let factor = 1 + (max(1, target) - 1) * collapseProgress
        liveBadge.transform = CGAffineTransform(
            translationX: (factor - 1) * size.width / 2,
            y: (factor - 1) * size.height / 2
        ).scaledBy(x: factor, y: factor)
    }
}
