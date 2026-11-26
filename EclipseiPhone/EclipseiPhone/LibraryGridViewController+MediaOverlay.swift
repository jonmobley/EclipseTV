//
//  LibraryGridViewController+MediaOverlay.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//
//  Description: "Use as Overlay" for photo and video tiles: the media is
//               layered over the live picture at a chosen size and spot
//               instead of replacing it. Local to this phone.
//  Thread Safety: Main thread only - UIKit.
//

import UIKit

// MARK: - MediaOverlayPreset

/// Size and spot choices offered in the tile's Overlay menu.
enum MediaOverlayPreset {

    /// Width fractions: Small, Medium, Large.
    static let sizes: [(title: String, scale: Double)] = [
        ("Small", 0.25), ("Medium", MediaOverlayEntry.defaultScale), ("Large", 0.5)
    ]

    /// Gap from the screen edge, as a fraction of the screen.
    static let edgeInset: Double = 0.04

    /// Spots: Center plus the four corners.
    static let spots: [(title: String, corner: OverlayCorner?)] = [
        ("Center", nil),
        (OverlayCorner.topLeading.label, .topLeading),
        (OverlayCorner.topTrailing.label, .topTrailing),
        (OverlayCorner.bottomLeading.label, .bottomLeading),
        (OverlayCorner.bottomTrailing.label, .bottomTrailing)
    ]

    /// Normalized center for `corner` (nil = center) at width `scale`.
    ///
    /// Height is unknown here, so the vertical spot is a quarter in from the edge.
    static func center(for corner: OverlayCorner?, scale: Double) -> (x: Double, y: Double) {
        guard let corner else { return (0.5, 0.5) }
        let left = edgeInset + scale / 2
        let right = 1 - left
        switch corner {
        case .topLeading: return (left, 0.25)
        case .topTrailing: return (right, 0.25)
        case .bottomLeading: return (left, 0.75)
        case .bottomTrailing: return (right, 0.75)
        }
    }
}

// MARK: - Media Overlay Tiles

extension LibraryGridViewController {

    /// Whether `item` is set up as an overlay (its tap layers it over live).
    func isMediaOverlay(_ item: LibraryItemDTO) -> Bool {
        MediaOverlayStore.shared.entry(for: item.id) != nil
    }

    /// Turns the media overlay on or off over whatever is live.
    func toggleMediaOverlay(_ item: LibraryItemDTO) {
        LiveOverlayController.shared.toggle(.media(item.id))
        Haptics.impactLight()
    }

    /// The tile's Overlay entry: "Use as Overlay", or the overlay's options.
    func mediaOverlayMenu(for item: LibraryItemDTO) -> UIMenuElement {
        guard let entry = MediaOverlayStore.shared.entry(for: item.id) else {
            return UIAction(
                title: "Use as Overlay",
                image: UIImage(systemName: "square.on.square")
            ) { [weak self] _ in
                self?.useAsOverlay(item)
            }
        }
        return UIMenu(
            title: "Overlay",
            image: UIImage(systemName: "square.on.square"),
            children: overlayOptions(for: entry, item: item)
        )
    }

    // MARK: - Private

    private func useAsOverlay(_ item: LibraryItemDTO) {
        let showTop = openShowId.map { TemplateCardStore.shared.nextStackOrder(inShowId: $0) } ?? 0
        MediaOverlayStore.shared.add(
            itemId: item.id, isVideo: item.isVideo, minimumStackOrder: showTop
        )
        if !LiveOverlayController.shared.isLive(.media(item.id)) {
            toggleMediaOverlay(item)
        }
        reloadGridIfSafe()
    }

    private func overlayOptions(for entry: MediaOverlayEntry, item: LibraryItemDTO) -> [UIMenuElement] {
        let isOn = LiveOverlayController.shared.isLive(.media(item.id))
        let toggle = UIAction(
            title: isOn ? "Take Off Screen" : "Show on Screen",
            image: UIImage(systemName: isOn ? "eye.slash" : "eye")
        ) { [weak self] _ in
            self?.toggleMediaOverlay(item)
        }
        let stop = UIAction(
            title: "Stop Using as Overlay",
            image: UIImage(systemName: "square.slash")
        ) { [weak self] _ in
            LiveOverlayController.shared.remove(.media(item.id))
            MediaOverlayStore.shared.remove(itemId: item.id)
            self?.reloadGridIfSafe()
        }
        return [toggle, sizeMenu(for: entry), spotMenu(for: entry), stop]
    }

    private func sizeMenu(for entry: MediaOverlayEntry) -> UIMenu {
        let actions = MediaOverlayPreset.sizes.map { size in
            UIAction(title: size.title, state: entry.scale == size.scale ? .on : .off) { _ in
                var next = entry
                next.scale = size.scale
                MediaOverlayStore.shared.update(next)
            }
        }
        return UIMenu(title: "Size", image: UIImage(systemName: "arrow.up.left.and.arrow.down.right"),
                      children: actions)
    }

    private func spotMenu(for entry: MediaOverlayEntry) -> UIMenu {
        let actions = MediaOverlayPreset.spots.map { spot in
            let target = MediaOverlayPreset.center(for: spot.corner, scale: entry.scale)
            let isCurrent = abs(entry.centerX - target.x) < 0.001
                && abs(entry.centerY - target.y) < 0.001
            return UIAction(title: spot.title, state: isCurrent ? .on : .off) { _ in
                var next = entry
                next.centerX = target.x
                next.centerY = target.y
                MediaOverlayStore.shared.update(next)
            }
        }
        return UIMenu(title: "Position", image: UIImage(systemName: "rectangle.center.inset.filled"),
                      children: actions)
    }
}
