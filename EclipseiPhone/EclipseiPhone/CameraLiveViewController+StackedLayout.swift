//
//  CameraLiveViewController+StackedLayout.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import UIKit

// MARK: - Stacked Layout

/// Portrait hold of a Landscape Show: header band · 16:9 panel · thumbnail grid.
///
/// A 16:9 panel on a portrait phone leaves black above and below. Rather than
/// float the chrome over the camera, the header (Back · LIVE · Settings) takes
/// the band above and the program / frame / still thumbnails take the band
/// below, on the same column grid as an open Show. The dock keeps its strip.
struct CameraStackedLayout: Equatable {
    /// Band for Back · LIVE · Settings, with room under LIVE for the recording
    /// timer pill, clear of the panel.
    let header: CGRect
    /// Full-width Display Mode panel directly under the header.
    let panel: CGRect
    /// Band for the thumbnail grid, from the panel down to the dock strip.
    let grid: CGRect
}

/// One tile in the stacked thumbnail grid.
enum CameraThumbGridItem: Equatable {
    /// Program monitor — what AirPlay is showing while this camera previews.
    case program
    /// An enabled overlay frame; tap toggles it on the camera.
    case frame(UUID)
    /// Background, a quick-change still, or the + that adds one.
    case still(CameraStillRibbonItem)
}

extension CameraLiveViewController {

    /// Side inset of the thumbnail grid — matches `LibraryGridViewController.sectionInset`.
    static let thumbGridSectionInset: CGFloat = 16
    /// Gap between tiles — matches `LibraryGridViewController.interitemSpacing`.
    static let thumbGridSpacing: CGFloat = 12
    /// Tile corner radius — matches `LibraryThumbnailCell`.
    static let thumbGridCornerRadius: CGFloat = 14
    /// Space between the header band and the panel below it.
    static let stackedHeaderGap: CGFloat = 12
    /// Extra band height under the LIVE pill so the recording timer pill fits in
    /// the header without landing on the camera or moving the panel mid-take.
    static let stackedTimerAllowance: CGFloat = 16

    /// Stacked geometry when the black bands have room for it, else nil.
    ///
    /// Only a wide panel (16:9) in a portrait stage leaves bands top and bottom.
    /// The grid band must fit at least one tile row, otherwise the centered
    /// overlay layout is the better use of the screen (small phones, iPad splits).
    static func stackedLayout(
        in bounds: CGRect,
        safeTop: CGFloat,
        aspect: CGFloat,
        dockSpan: CGFloat,
        tileHeight: CGFloat
    ) -> CameraStackedLayout? {
        guard aspect >= 1, bounds.width > 1, bounds.height > 1 else { return nil }
        let header = CGRect(
            x: 0,
            y: safeTop + 8,
            width: bounds.width,
            height: chromeControlSize + stackedTimerAllowance
        )
        let panel = CGRect(
            x: 0,
            y: header.maxY + stackedHeaderGap,
            width: bounds.width,
            height: (bounds.width / aspect).rounded(.down)
        )
        let gridTop = panel.maxY + thumbGridSectionInset
        let gridBottom = bounds.height - dockSpan
        guard gridBottom - gridTop >= tileHeight + thumbGridSectionInset else { return nil }
        let grid = CGRect(
            x: 0,
            y: gridTop,
            width: bounds.width,
            height: gridBottom - gridTop
        )
        return CameraStackedLayout(header: header, panel: panel, grid: grid)
    }

    /// Tile for the thumbnail grid — the same size an open Show's grid uses at this width.
    static func thumbGridTileSize(
        width: CGFloat,
        orientation: ExternalOutputOrientation
    ) -> CGSize {
        LibraryGridViewController.homeTileSize(
            containerWidth: width,
            sectionInset: thumbGridSectionInset,
            spacing: thumbGridSpacing,
            orientation: orientation
        )
    }

    /// Grid order mirrors the ribbons left to right: program, frames, then stills.
    static func thumbGridItems(
        showsProgram: Bool,
        frameIds: [UUID],
        stills: [CameraStillRibbonItem]
    ) -> [CameraThumbGridItem] {
        var items: [CameraThumbGridItem] = []
        if showsProgram {
            items.append(.program)
        }
        items.append(contentsOf: frameIds.map { .frame($0) })
        items.append(contentsOf: stills.map { .still($0) })
        return items
    }

    /// Picks stacked geometry when the bands have room; otherwise the centered panel.
    ///
    /// Sets `stackedLayout` as a side effect so the chrome passes lay out against
    /// the same decision the panel was placed with.
    func resolvePhoneCameraPanel(edge: CaptureDockEdge, dockSpan: CGFloat) -> CGRect {
        let bounds = stageView.bounds
        let orientation = ExternalOutputSettings.orientation
        stackedLayout = edge == .bottom
            ? Self.stackedLayout(
                in: bounds,
                safeTop: view.safeAreaInsets.top,
                aspect: orientation.aspectRatio,
                dockSpan: dockSpan,
                tileHeight: Self.thumbGridTileSize(
                    width: bounds.width, orientation: orientation
                ).height
            )
            : nil
        return stackedLayout?.panel ?? Self.phoneCameraPanelRect(
            in: bounds,
            aspect: orientation.aspectRatio,
            dockEdge: edge,
            dockSpan: dockSpan
        )
    }
}
