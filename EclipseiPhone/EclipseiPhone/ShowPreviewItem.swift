//
//  ShowPreviewItem.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import Foundation

/// One swipe page in a Show's browse-only Preview gallery.
enum ShowPreviewItem: Equatable {
    /// Library still; Photos-style fit and pinch zoom.
    case still(LocalMediaPreviewItem)
    /// Screensaver or Background in a Display Mode fill panel.
    case displayMode(DisplayModePreviewSpec)

    /// Stable id: library item id or `ShowToolToken`.
    var id: String {
        switch self {
        case .still(let item): return item.id
        case .displayMode(let spec): return spec.id
        }
    }
}

/// Display Mode page payload (Screensaver / Background).
struct DisplayModePreviewSpec: Equatable {
    let id: String
    let fileURL: URL
    let isVideo: Bool
    let usesSeamlessLoop: Bool
}

/// Builds the swipe set: stills, Screensaver, and Background in grid order.
enum ShowPreviewGallery {

    /// Photos, Screensaver, and Background. Skips Camera, PDF, web, slideshow,
    /// Add, and library videos.
    static func items(
        from grid: [ShowGridItem],
        screensaver: (url: URL, isVideo: Bool)?,
        logoURL: URL?,
        localStillURL: (String) -> URL?
    ) -> [ShowPreviewItem] {
        grid.compactMap { item in
            switch item {
            case .screensaver:
                return displayModeItem(
                    id: ShowToolToken.screensaver, media: screensaver
                )
            case .logo:
                guard let logoURL else { return nil }
                return .displayMode(DisplayModePreviewSpec(
                    id: ShowToolToken.logo,
                    fileURL: logoURL,
                    isVideo: false,
                    usesSeamlessLoop: false
                ))
            case .media(let dto):
                return stillItem(dto, localStillURL: localStillURL)
            case .slideshow, .livePoll, .camera, .website, .pdf, .add:
                return nil
            }
        }
    }

    /// Resolves Screensaver / Background / stills from the live stores.
    @MainActor
    static func items(from grid: [ShowGridItem]) -> [ShowPreviewItem] {
        items(
            from: grid,
            screensaver: screensaverMedia(),
            logoURL: LogoStore.shared.fileURL,
            localStillURL: { LocalMediaStore.shared.localURL(forId: $0) }
        )
    }

    // MARK: - Private

    private static func stillItem(
        _ dto: LibraryItemDTO,
        localStillURL: (String) -> URL?
    ) -> ShowPreviewItem? {
        guard !dto.isVideo, let url = localStillURL(dto.id) else { return nil }
        return .still(LocalMediaPreviewItem(id: dto.id, fileURL: url, isVideo: false))
    }

    private static func displayModeItem(
        id: String,
        media: (url: URL, isVideo: Bool)?
    ) -> ShowPreviewItem? {
        guard let media else { return nil }
        return .displayMode(DisplayModePreviewSpec(
            id: id,
            fileURL: media.url,
            isVideo: media.isVideo,
            usesSeamlessLoop: media.isVideo && id == ShowToolToken.screensaver
        ))
    }

    @MainActor
    private static func screensaverMedia() -> (url: URL, isVideo: Bool)? {
        guard let source = ScreensaverStore.shared.presentationSource else { return nil }
        switch source.content {
        case .image(let url, _):
            return (url, false)
        case .screensaver(let url), .video(let url, _, _):
            return (url, true)
        case .camera, .web, .pdf, .black, .unavailable:
            return nil
        }
    }
}
