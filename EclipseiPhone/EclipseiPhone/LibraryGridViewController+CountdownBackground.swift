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
        var children: [UIMenuElement] = CountdownBackgroundOption.fixed.map {
            backgroundAction($0, item: item, current: current)
        }
        // Show members carry their thumbnail as the glyph and a readable label —
        // the raw import filename identifies nothing from the room.
        let media = CountdownBackgroundOption.showMedia(inShowId: item.showId).map {
            backgroundAction($0, item: item, current: current)
        }
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

    private func backgroundAction(
        _ option: CountdownBackgroundOption,
        item: ShowCountdown,
        current: CountdownBackground
    ) -> UIAction {
        UIAction(
            title: option.title,
            image: option.image(),
            state: option.background == current ? .on : .off
        ) { [weak self] _ in
            CountdownStore.shared.setBackground(id: item.id, option.background)
            Haptics.impactLight()
            // Ticks only repaint digits, so the hero needs an explicit nudge to
            // pick up a background chosen while this countdown is already live.
            self?.liveHeader.refreshCountdownBackground()
            self?.refreshCountdownChrome()
        }
    }
}
