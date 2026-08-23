//
//  LibraryGridViewController+HeroCollapse.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import UIKit

// MARK: - Pinned Live Hero

/// Portrait Show preview stays expanded. The grid's top inset is the full hero
/// footprint, so tiles scroll under the card. The trailing mini slot is only for
/// live-from-another-Show (`foreignLiveHeader`).
extension LibraryGridViewController {

    /// Trailing mini-preview width (Landscape / 16:9 content).
    static let compactHeroWidthLandscape = LiveHeroMiniSlot.landscapeWidth
    /// Trailing mini-preview width (Vertical / 9:16 content).
    static let compactHeroWidthVertical = LiveHeroMiniSlot.verticalWidth

    /// Keeps this Show's hero expanded. Call after layout / Show changes.
    func updateHeroCollapse() {
        expandPinnedLiveHero()
    }

    /// Where the tucked mini preview sits, in the controller view's coordinates.
    func compactHeroTargetRect() -> CGRect? {
        LiveHeroMiniSlot.targetRect(
            viewSize: view.bounds.size,
            safeAreaTop: view.safeAreaInsets.top,
            headerInset: headerInset,
            expandedHero: expandedHeroLayoutFrame(),
            isVerticalMode: ExternalOutputSettings.isVerticalMode
        )
    }

    // MARK: - Private

    private func expandPinnedLiveHero() {
        heroCollapseProgress = 0
        liveHeader.transform = .identity
        liveHeader.applyCollapse(progress: 0, scale: 1)
    }

    /// Hero frame with any leftover transform ignored — `center` is the layer
    /// position and `bounds` the layout size, neither of which a transform touches.
    private func expandedHeroLayoutFrame() -> CGRect {
        CGRect(
            x: liveHeader.center.x - liveHeader.bounds.width / 2,
            y: liveHeader.center.y - liveHeader.bounds.height / 2,
            width: liveHeader.bounds.width,
            height: liveHeader.bounds.height
        )
    }
}

/// Geometry for the trailing live mini preview (foreign-Show live only).
enum LiveHeroMiniSlot {
    static let landscapeWidth: CGFloat = 148
    static let verticalWidth: CGFloat = 84

    /// Compact card in the top-trailing corner, matching the expanded hero's aspect.
    static func targetRect(
        viewSize: CGSize,
        safeAreaTop: CGFloat,
        headerInset: CGFloat,
        expandedHero: CGRect,
        isVerticalMode: Bool
    ) -> CGRect? {
        guard expandedHero.width > 1, expandedHero.height > 1 else { return nil }
        let width = isVerticalMode ? verticalWidth : landscapeWidth
        guard width < expandedHero.width else { return nil }
        let height = (expandedHero.height * (width / expandedHero.width)).rounded(.down)
        return CGRect(
            x: viewSize.width - headerInset - width,
            y: safeAreaTop + headerInset,
            width: width,
            height: height
        )
    }
}
