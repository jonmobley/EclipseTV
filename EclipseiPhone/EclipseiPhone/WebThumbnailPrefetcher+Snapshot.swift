//
//  WebThumbnailPrefetcher+Snapshot.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import UIKit
import WebKit
import os.log

// MARK: - Snapshot Capture

extension WebThumbnailPrefetcher {

    /// Captures a Display Mode–aspect preview for `pageId`.
    func takeSnapshot(
        from webView: WKWebView,
        pageId: UUID,
        completion: (() -> Void)? = nil,
        settleRetries: Int = 6
    ) {
        // Wait out a transition (browser opening, rotating, closing) rather than
        // render a card that is still moving; see `isSettledOnScreen`.
        if webView.transform != .identity,
           let panel = webView.superview,
           !Self.isSettledOnScreen(panel),
           settleRetries > 0 {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self, weak webView] in
                guard let self, let webView else { completion?(); return }
                self.takeSnapshot(
                    from: webView,
                    pageId: pageId,
                    completion: completion,
                    settleRetries: settleRetries - 1
                )
            }
            return
        }
        let scroll = webView.scrollView
        scroll.contentInsetAdjustmentBehavior = .never
        scroll.contentInset = .zero
        scroll.verticalScrollIndicatorInsets = .zero
        scroll.horizontalScrollIndicatorInsets = .zero

        // Phone stage uses bounds + scale transform. WK snapshots of that often
        // paint only a corner; the panel's drawHierarchy is the full 16:9 / 9:16.
        if webView.transform != .identity,
           let panelImage = snapshotDisplayPanel(containing: webView) {
            WebThumbnailStore.shared.saveSnapshot(panelImage, for: pageId)
            completion?()
            return
        }

        let restore = beginFlatSnapshotViewport(webView)
        let size = webView.bounds.size
        guard size.width > 1, size.height > 1 else {
            restore()
            completion?()
            return
        }

        let config = WKSnapshotConfiguration()
        config.rect = CGRect(origin: .zero, size: size)
        webView.takeSnapshot(with: config) { image, error in
            Task { @MainActor in
                restore()
                if let image {
                    WebThumbnailStore.shared.saveSnapshot(image, for: pageId)
                } else if let error {
                    let log = Logger(
                        subsystem: "com.eclipseapp.ios",
                        category: "WebThumbnailPrefetch"
                    )
                    log.error("Snapshot failed: \(error.localizedDescription)")
                }
                completion?()
            }
        }
    }

    /// Renders the 16:9 / 9:16 host card (visual page), not the transformed web view.
    private func snapshotDisplayPanel(containing webView: WKWebView) -> UIImage? {
        guard let panel = webView.superview else { return nil }
        let size = panel.bounds.size
        let logical = ExternalOutputSettings.webLogicalSize
        guard size.width > 8, size.height > 8,
              aspectMatchesDisplayMode(size, logical: logical) else { return nil }
        // drawHierarchy paints what is on screen. Mid-transition (browser sliding in,
        // rotating to Landscape, closing) the card is drawn smaller than its bounds,
        // which saved a small card in the corner of a black preview. Let the
        // caller fall back to a WebKit snapshot, which ignores on-screen motion.
        guard Self.isSettledOnScreen(panel) else { return nil }

        let savedAlpha = panel.alpha
        if savedAlpha < 0.05 { panel.alpha = 1 }

        let format = UIGraphicsImageRendererFormat.default()
        format.opaque = true
        format.scale = min(UITraitCollection.current.displayScale, 2)
        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        let image = renderer.image { _ in
            panel.drawHierarchy(
                in: CGRect(origin: .zero, size: size),
                afterScreenUpdates: true
            )
        }
        panel.alpha = savedAlpha
        return image
    }

    /// Clears scale transform so a WK fallback snapshot isn't a tiny corner.
    private func beginFlatSnapshotViewport(_ webView: WKWebView) -> () -> Void {
        let saved = (
            transform: webView.transform,
            bounds: webView.bounds,
            center: webView.center,
            mask: webView.autoresizingMask,
            translates: webView.translatesAutoresizingMaskIntoConstraints
        )
        let logical = ExternalOutputSettings.webLogicalSize
        let isOffscreen = (webView.superview?.alpha ?? 1) < 0.05

        webView.transform = .identity
        webView.translatesAutoresizingMaskIntoConstraints = true
        if isOffscreen {
            let size = CGSize(width: logical.width / 2, height: logical.height / 2)
            webView.frame = CGRect(origin: .zero, size: size)
        } else if let parent = webView.superview, parent.bounds.width > 1 {
            webView.frame = parent.bounds
        } else {
            webView.bounds = CGRect(origin: .zero, size: logical)
        }

        return {
            webView.transform = saved.transform
            webView.bounds = saved.bounds
            webView.center = saved.center
            webView.autoresizingMask = saved.mask
            webView.translatesAutoresizingMaskIntoConstraints = saved.translates
        }
    }

    /// True when `view` is in a window, drawn at its own size, and nothing it sits
    /// in is animating, so an on-screen render matches its bounds.
    static func isSettledOnScreen(_ view: UIView) -> Bool {
        guard let window = view.window else { return false }
        let onScreen = view.convert(view.bounds, to: nil)
        guard onScreenSizeMatches(onScreen.size, bounds: view.bounds.size) else { return false }
        if let presented = window.layer.presentation(),
           !CATransform3DEqualToTransform(presented.transform, window.layer.transform) {
            return false
        }
        var current: UIView? = view
        while let layerOwner = current {
            if let keys = layerOwner.layer.animationKeys(), !keys.isEmpty { return false }
            current = layerOwner.superview
        }
        return true
    }

    /// On-screen size within a point of the layout size (no scale applied by ancestors).
    static func onScreenSizeMatches(_ onScreen: CGSize, bounds: CGSize) -> Bool {
        abs(onScreen.width - bounds.width) <= 1 && abs(onScreen.height - bounds.height) <= 1
    }

    private func aspectMatchesDisplayMode(_ size: CGSize, logical: CGSize) -> Bool {
        guard size.width > 1, size.height > 1 else { return false }
        let sizeAspect = size.width / size.height
        let logicalAspect = logical.width / logical.height
        return abs(sizeAspect - logicalAspect) / logicalAspect < 0.15
    }
}
