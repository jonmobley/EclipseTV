//
//  PDFReaderViewportLayout.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import UIKit

/// Viewport geometry for the phone PDF reader (`PDFRemoteViewController`).
///
/// The reader always frames the page the way the audience sees it: a panel in
/// the output shape (Display Mode aspect, or a custom screen size), whether or
/// not a projector is attached yet, in both phone orientations. The panel is
/// the exact mirror of the TV. The rest of the stage shows the surrounding page
/// dimmed (`PDFAudienceFrameView`), so a 16:9 panel on a portrait phone is no
/// longer a sliver with nothing around it.
enum PDFReaderViewportLayout {

    // MARK: - Geometry

    /// Breathing room between the audience frame and the stage edges, so the
    /// frame reads as a frame and some dimmed page shows around it.
    static let framePanelInset: CGFloat = 12

    /// Frame for the reader's audience panel inside `stageBounds`.
    ///
    /// - Parameters:
    ///   - stageBounds: Bounds of the reader stage (the safe area above the ribbon).
    ///   - aspect: Output width ÷ height; defaults to the current output shape.
    /// - Returns: The largest centered rect of `aspect` inside the inset stage,
    ///   or `.zero` when it does not fit.
    static func panelRect(
        in stageBounds: CGRect,
        aspect: CGFloat = ExternalOutputSettings.outputAspectRatio
    ) -> CGRect {
        guard stageBounds.width > 0, stageBounds.height > 0 else { return .zero }
        let framed = stageBounds.insetBy(dx: framePanelInset, dy: framePanelInset)
        guard framed.width > 0, framed.height > 0 else { return .zero }
        return ExternalOutputSettings.panelRect(in: framed, aspect: aspect)
    }

    /// Frame for the dimmed context view behind the panel: the panel's column,
    /// full stage height, so the page above and below the frame lines up with it.
    static func contextRect(for panel: CGRect, in stageBounds: CGRect) -> CGRect {
        guard panel.width > 0, stageBounds.height > 0 else { return .zero }
        return CGRect(x: panel.minX, y: stageBounds.minY, width: panel.width, height: stageBounds.height)
    }

    /// Scroll offset for the context view so its page sits where the panel's
    /// page sits on screen (the context view starts `panelTop` points higher).
    static func contextOffset(forPanelOffset offset: CGPoint, panelTop: CGFloat) -> CGPoint {
        CGPoint(x: offset.x, y: offset.y - panelTop)
    }
}
