//
//  PDFReaderViewportLayout.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import UIKit

/// Viewport geometry for the phone PDF reader (`PDFRemoteViewController`).
///
/// The reader letterboxes itself to the Display Mode aspect only while a
/// projector is in the room, so the page the host scrolls and zooms is framed
/// the way the audience sees it. With no projector there is no panel to match,
/// and a 16:9 letterbox on a portrait phone leaves the page a sliver of the
/// screen — so the reader takes the whole stage and reads full height instead.
enum PDFReaderViewportLayout {

    // MARK: - Policy

    /// Whether the reader should frame the page the way the projector does.
    ///
    /// Reads the one projector affordance signal (`LiveOutputRouting`), so the
    /// reader agrees with the grid's badges and gates about whether a display is
    /// available rather than asking the question a second, different way.
    @MainActor
    static var matchesProjectorFraming: Bool {
        LiveOutputRouting.projectorAvailable
    }

    // MARK: - Geometry

    /// Breathing room between the letterboxed panel and the stage edges, so the
    /// panel reads as a frame around what the room sees. Dropped along with the
    /// letterbox when there is no projector.
    static let projectorPanelInset: CGFloat = 12

    /// Frame for the reader's PDF panel inside `stageBounds`.
    ///
    /// - Parameters:
    ///   - stageBounds: Bounds of the reader stage (the safe area).
    ///   - matchesProjectorFraming: Whether to letterbox to the Display Mode aspect.
    /// - Returns: The inset Display Mode panel when mirroring a projector,
    ///   otherwise the full stage. `.zero` when neither fits.
    static func panelRect(
        in stageBounds: CGRect,
        matchesProjectorFraming: Bool
    ) -> CGRect {
        guard stageBounds.width > 0, stageBounds.height > 0 else { return .zero }
        guard matchesProjectorFraming else { return stageBounds }
        let framed = stageBounds.insetBy(
            dx: projectorPanelInset,
            dy: projectorPanelInset
        )
        guard framed.width > 0, framed.height > 0 else { return .zero }
        return ExternalOutputSettings.displayModePanelRect(in: framed)
    }
}
