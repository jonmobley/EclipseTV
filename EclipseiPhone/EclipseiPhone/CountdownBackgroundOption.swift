//
//  CountdownBackgroundOption.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import UIKit

/// One pickable countdown background: a fixed choice or a member of this Show.
///
/// Shared by the countdown ⋯ Background menu and the Add Countdown screen so both
/// list the same choices with the same labels and glyphs.
struct CountdownBackgroundOption: Equatable {
    let background: CountdownBackground
    /// Row / menu title.
    let title: String
    /// SF Symbol shown when there is no thumbnail to show.
    let systemImage: String

    /// Library media id when this option is a Show member.
    var mediaId: String? { background.libraryItemId }

    /// Solid black — the original look, offered as "None".
    ///
    /// Not named `none`: in an optional context `.none` resolves to `Optional.none`.
    static let solidBlack = CountdownBackgroundOption(
        background: .black, title: "None", systemImage: "slash.circle"
    )
    /// Whatever the Screensaver tile holds.
    static let screensaver = CountdownBackgroundOption(
        background: .screensaver, title: "Screensaver", systemImage: "sparkles.tv"
    )
    /// The Background still from the Show tools.
    static let backgroundStill = CountdownBackgroundOption(
        background: .background, title: "Background", systemImage: "photo.artframe"
    )

    /// The three choices every Show offers, in menu order.
    static let fixed: [CountdownBackgroundOption] = [
        .solidBlack, .screensaver, .backgroundStill
    ]

    // MARK: - Show Media

    /// Members of a Show whose full-resolution file is on this device, in Show order.
    ///
    /// Imported media is named after its file (`batch_0F5ECB32….jpg`), which means
    /// nothing to an operator, so a member without an overlay title is labelled by
    /// its kind and its position among the Show's photos and videos instead — the
    /// same order the tiles sit in on the grid.
    ///
    /// - Parameters:
    ///   - itemIds: The Show's member ids, in Show order.
    ///   - library: The library entries those ids resolve against.
    ///   - overlayTitle: The `MediaTitleStore` title for an id, if any.
    ///   - isOnDevice: Whether the full-resolution file for an id is present locally.
    static func showMedia(
        itemIds: [String],
        library: [LibraryItemDTO],
        overlayTitle: (String) -> String?,
        isOnDevice: (String) -> Bool
    ) -> [CountdownBackgroundOption] {
        var ordinal = 0
        return itemIds.compactMap { id in
            guard let media = library.first(where: { $0.id == id }) else { return nil }
            ordinal += 1
            guard isOnDevice(id) else { return nil }
            return CountdownBackgroundOption(
                background: .libraryItem(id: id),
                title: label(
                    overlayTitle: overlayTitle(id),
                    isVideo: media.isVideo,
                    ordinal: ordinal
                ),
                systemImage: media.isVideo ? "film" : "photo"
            )
        }
    }

    /// Overlay title when set, otherwise `Photo 3` / `Video 3` by Show position.
    static func label(overlayTitle: String?, isVideo: Bool, ordinal: Int) -> String {
        if let overlayTitle, !overlayTitle.isEmpty { return overlayTitle }
        return "\(isVideo ? "Video" : "Photo") \(ordinal)"
    }
}

@MainActor
extension CountdownBackgroundOption {

    /// Show members with media on this device, resolved against the live stores.
    static func showMedia(inShowId showId: UUID) -> [CountdownBackgroundOption] {
        guard let album = LocalAlbumStore.shared.album(id: showId) else { return [] }
        return showMedia(
            itemIds: album.itemIds,
            library: TVLibraryStore.shared.items,
            overlayTitle: { MediaTitleStore.title(forId: $0) },
            isOnDevice: { LocalMediaStore.shared.hasMedia(forId: $0) }
        )
    }

    /// Thumbnail glyph for a Show member, or the kind's SF Symbol while it loads.
    ///
    /// `TVLibraryStore.thumbnail(for:)` returns nil on a cache miss and starts a disk
    /// load; callers that stay on screen listen for
    /// `TVLibraryStore.thumbnailDidChangeNotification` and ask again.
    func image(glyphSize: CGSize = CountdownBackgroundGlyph.menuSize) -> UIImage? {
        if let mediaId, let thumb = TVLibraryStore.shared.thumbnail(for: mediaId) {
            return CountdownBackgroundGlyph.make(from: thumb, size: glyphSize)
        }
        return UIImage(systemName: systemImage)
    }
}

// MARK: - Glyph

/// Renders a media thumbnail as a small rounded still for menus and table rows.
enum CountdownBackgroundGlyph {
    /// Fits the glyph column of a `UIMenu` row.
    static let menuSize = CGSize(width: 34, height: 24)
    /// Leading image of an inset-grouped table row.
    static let rowSize = CGSize(width: 44, height: 30)
    static let cornerRadius: CGFloat = 5

    /// `image` aspect-filled and clipped to a rounded rect, kept in its own colors.
    ///
    /// `.alwaysOriginal` matters: a menu would otherwise tint the photo as a template
    /// and show a flat blue rectangle.
    static func make(from image: UIImage, size: CGSize = menuSize) -> UIImage {
        let format = UIGraphicsImageRendererFormat.default()
        format.opaque = false
        let bounds = CGRect(origin: .zero, size: size)
        return UIGraphicsImageRenderer(size: size, format: format).image { _ in
            UIBezierPath(roundedRect: bounds, cornerRadius: cornerRadius).addClip()
            image.draw(in: aspectFillRect(for: image.size, in: bounds))
        }.withRenderingMode(.alwaysOriginal)
    }

    /// Smallest rect of `imageSize`'s aspect that covers `bounds`, centered.
    static func aspectFillRect(for imageSize: CGSize, in bounds: CGRect) -> CGRect {
        guard imageSize.width > 0, imageSize.height > 0 else { return bounds }
        let scale = max(
            bounds.width / imageSize.width,
            bounds.height / imageSize.height
        )
        let size = CGSize(
            width: imageSize.width * scale,
            height: imageSize.height * scale
        )
        return CGRect(
            x: bounds.midX - size.width / 2,
            y: bounds.midY - size.height / 2,
            width: size.width,
            height: size.height
        )
    }
}
