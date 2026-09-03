//
//  LiveHeaderView+Collapse.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import UIKit

// MARK: - Compact Presentation Chrome

/// Compact chrome is for the foreign-Show mini preview (progress 1). The open
/// Show's hero stays expanded (progress 0). Hairlines, corner radius, and the
/// LIVE badge counter-scale when a host applies a uniform transform.
extension LiveHeaderView {

    /// Full-hero corner radius; the tucked mini preview aims for `compactCornerRadius`.
    private static let expandedCornerRadius: CGFloat = 16
    private static let compactCornerRadius: CGFloat = 12
    /// Design font size of the LIVE badge, and the size it should read as when tucked.
    private static let badgeFontSize: CGFloat = 13
    private static let compactBadgeFontSize: CGFloat = 10
    /// Screen-space shadow once the mini preview is fully tucked (counter-scaled locally).
    private static let floatShadowOpacity: Float = 0.38
    private static let floatShadowRadius: CGFloat = 16
    private static let floatShadowYOffset: CGFloat = 6

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
        if let fullscreen = libraryVideoFullscreenButton {
            fullscreen.alpha = controlsFade
            let hideFullscreen = controlsFade <= 0.01
            if fullscreen.isHidden != hideFullscreen {
                fullscreen.isHidden = hideFullscreen
            }
        }
        if let ribbon = slideshowRibbonButton {
            ribbon.alpha = controlsFade
            let hideRibbon = controlsFade <= 0.01
            if ribbon.isHidden != hideRibbon {
                ribbon.isHidden = hideRibbon
            }
        }
        if let fit = screenFitButton {
            fit.alpha = controlsFade
            let hideFit = controlsFade <= 0.01
            if fit.isHidden != hideFit {
                fit.isHidden = hideFit
            }
        }
        gradientLayer.opacity = Float(controlsFade)
        titleLabel.alpha = max(0, 1 - progress * 2)

        // Locked preview keeps a thicker amber stroke; both widths counter-scale so
        // the hairline stays constant under the host's uniform transform.
        let baseBorder: CGFloat = isOutputLocked ? 3 : 1
        layer.borderWidth = baseBorder * inverse
        let radius = Self.expandedCornerRadius * (1 - progress)
            + Self.compactCornerRadius * inverse * progress
        layer.cornerRadius = radius
        applyFloatingLift(progress: progress, inverse: inverse, radius: radius)
        applyBadgeCounterScale()
        applyInteractionForPresentation()
        accessibilityHint = isCompactPresentation ? "Double tap to expand" : nil
    }

    /// Drop shadow for the tucked mini preview. Parent `masksToBounds` must turn off
    /// for the shadow to paint, so content corners clip on the fill layers instead.
    private func applyFloatingLift(
        progress: CGFloat,
        inverse: CGFloat,
        radius: CGFloat
    ) {
        // After transport has faded — earlier and square controls can peek past
        // the rounded corners while masksToBounds is off for the shadow.
        let lift = min(1, max(0, (progress - 0.4) / 0.6))
        if lift <= 0.01 {
            layer.masksToBounds = true
            layer.shadowOpacity = 0
            layer.shadowPath = nil
            syncContentCornerRadius(0)
            return
        }

        layer.masksToBounds = false
        syncContentCornerRadius(radius)
        layer.shadowColor = UIColor.black.cgColor
        layer.shadowOpacity = Self.floatShadowOpacity * Float(lift)
        // Host scales the whole view — inflate local shadow so screen size stays put.
        layer.shadowRadius = Self.floatShadowRadius * inverse
        layer.shadowOffset = CGSize(width: 0, height: Self.floatShadowYOffset * inverse)
        guard bounds.width > 1, bounds.height > 1 else {
            layer.shadowPath = nil
            return
        }
        layer.shadowPath = UIBezierPath(
            roundedRect: bounds,
            cornerRadius: radius
        ).cgPath
    }

    /// Rounds fill layers while the hero's own layer leaves `masksToBounds` off for shadow.
    private func syncContentCornerRadius(_ radius: CGFloat) {
        imageView.layer.cornerRadius = radius
        imageView.clipsToBounds = true
        gradientLayer.cornerRadius = radius
        gradientLayer.masksToBounds = true
        webPreviewHost?.layer.cornerRadius = radius
        screensaverPreview?.layer.cornerRadius = radius
        cameraPreviewHost?.layer.cornerRadius = radius
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
