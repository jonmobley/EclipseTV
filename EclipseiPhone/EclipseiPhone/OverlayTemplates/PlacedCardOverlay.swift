//
//  PlacedCardOverlay.swift
//  Eclipse (iPhone/iPad port of the Mac file of the same name;
//  keep the Codable shapes identical to EclipsePro)
//
//  Description: Read-only card overlay for the audience/external display. Renders
//               `OverlayCardView` at its free-placement scale and positions it at
//               the resolved center (free placement, or corner dock when none is
//               set), matching the operator preview and the cast canvas.
//  Thread Safety: Main thread only - SwiftUI view component.
//

import SwiftUI

// MARK: - PlacedCardOverlay

/// A positioned, non-interactive card overlay.
///
/// The card is measured after layout so it can be centered accurately; when the
/// config has no explicit placement it docks to its `corner`. Until measured it
/// stays invisible at the resolved placement (never stage-center) so program
/// switches cannot flash or slide from mid-frame.
///
/// Thread Safety: Main thread only - SwiftUI view component.
struct PlacedCardOverlay: View {

    // MARK: - Properties

    let config: OverlayCardConfig
    let contentFrame: CGRect
    /// Called with the card's drawn frame in the layer's coordinate space
    /// (`LiveOverlayLayerView.coordinateSpace`), for touch hit-testing.
    var onFrame: ((CGRect) -> Void)?

    @State private var cardSize: CGSize = .zero

    // MARK: - Body

    var body: some View {
        let scale = OverlayCardLayout.containerScale(contentFrame)
        let effectiveScale = scale * (config.placement?.scale ?? 1)
        let measured = cardSize != .zero
        OverlayCardView(config: config, scale: effectiveScale)
            .fixedSize()
            .onGeometryChange(for: CGSize.self) { $0.size } action: { cardSize = $0 }
            .opacity(measured ? 1 : 0)
            .onGeometryChange(for: CGRect.self) {
                $0.frame(in: .named(LiveOverlayLayerView.coordinateSpace))
            } action: { onFrame?($0) }
            .position(center)
            // Measure settle and remounts must not inherit program crossfade.
            .animation(nil, value: cardSize)
            .animation(nil, value: center.x)
            .animation(nil, value: center.y)
    }

    // MARK: - Layout

    /// Resolved, in-bounds center for the card in container coordinates.
    ///
    /// Uses a 1×1 stand-in size before measure so docked cards land near their
    /// corner (not stage center); free placement uses stored center immediately.
    private var center: CGPoint {
        let sizeForLayout = cardSize == .zero
            ? CGSize(width: 1, height: 1)
            : cardSize
        let base = OverlayCardLayout.basePlacement(
            config: config,
            cardSize: sizeForLayout,
            contentFrame: contentFrame
        )
        let point = OverlayCardLayout.denormalized(
            CGPoint(x: base.centerX, y: base.centerY),
            in: contentFrame
        )
        return OverlayCardLayout.clampedCenter(
            point,
            cardSize: sizeForLayout,
            in: contentFrame
        )
    }
}
