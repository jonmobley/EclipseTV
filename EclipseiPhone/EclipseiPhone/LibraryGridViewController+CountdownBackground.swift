//
//  LibraryGridViewController+CountdownBackground.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import UIKit

// MARK: - Countdown Background Menu

extension LibraryGridViewController {

    /// ⋯ submenu choosing what renders behind this countdown's clock.
    ///
    /// Only offers media that already exists — this Show's members plus the two
    /// global tool stills — so picking a background never imports a second copy.
    func countdownBackgroundMenu(for item: ShowCountdown) -> UIMenu {
        let current = CountdownStore.shared.countdown(id: item.id)?.background
            ?? item.background
        var children: [UIMenuElement] = [
            backgroundAction(
                .black, title: "None", systemImage: "slash.circle",
                item: item, current: current
            ),
            backgroundAction(
                .screensaver, title: "Screensaver", systemImage: "sparkles.tv",
                item: item, current: current
            ),
            backgroundAction(
                .background, title: "Background", systemImage: "photo.artframe",
                item: item, current: current
            )
        ]
        let media = showMediaActions(for: item, current: current)
        if !media.isEmpty {
            children.append(UIMenu(
                title: "From This Show",
                options: .displayInline,
                children: media
            ))
        }
        return UIMenu(
            title: "Background",
            image: UIImage(systemName: "photo.on.rectangle.angled"),
            children: children
        )
    }

    // MARK: - Private

    /// Members of this countdown's Show whose full-resolution file is on this device.
    private func showMediaActions(
        for item: ShowCountdown,
        current: CountdownBackground
    ) -> [UIMenuElement] {
        guard let album = LocalAlbumStore.shared.albums.first(
            where: { $0.id == item.showId }
        ) else { return [] }
        return album.itemIds.compactMap { id -> UIMenuElement? in
            guard let media = store.items.first(where: { $0.id == id }),
                  LocalMediaStore.shared.hasMedia(forId: id)
            else { return nil }
            return backgroundAction(
                .libraryItem(id: id),
                title: media.name,
                systemImage: media.isVideo ? "film" : "photo",
                item: item,
                current: current
            )
        }
    }

    private func backgroundAction(
        _ background: CountdownBackground,
        title: String,
        systemImage: String,
        item: ShowCountdown,
        current: CountdownBackground
    ) -> UIAction {
        UIAction(
            title: title,
            image: UIImage(systemName: systemImage),
            state: background == current ? .on : .off
        ) { [weak self] _ in
            CountdownStore.shared.setBackground(id: item.id, background)
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            // Ticks only repaint digits, so the hero needs an explicit nudge to
            // pick up a background chosen while this countdown is already live.
            self?.liveHeader.refreshCountdownBackground()
            self?.refreshCountdownChrome()
        }
    }
}
