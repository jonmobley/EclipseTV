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
        completion: (() -> Void)? = nil
    ) {
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

    private func aspectMatchesDisplayMode(_ size: CGSize, logical: CGSize) -> Bool {
        guard size.width > 1, size.height > 1 else { return false }
        let sizeAspect = size.width / size.height
        let logicalAspect = logical.width / logical.height
        return abs(sizeAspect - logicalAspect) / logicalAspect < 0.15
    }
}
