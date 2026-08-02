//
//  LibraryGridViewController+MediaFit.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import UIKit

// MARK: - Screen Fit (Fit / Fill) Long-Press Option

extension LibraryGridViewController {

    /// Fit / Fill submenu controlling how a still is framed on the external display.
    ///
    /// Offered on long-press for stills only — video framing is fixed to aspect fit.
    func screenFitMenu(for item: LibraryItemDTO) -> UIMenu {
        let current = MediaFitSettings.mode(forId: item.id)
        let actions = MediaFitMode.allCases.map { mode in
            UIAction(
                title: mode.rawValue,
                image: UIImage(systemName: mode.iconName),
                state: mode == current ? .on : .off
            ) { [weak self] _ in
                self?.applyScreenFit(mode, to: item)
            }
        }
        return UIMenu(
            title: "Screen Fit",
            subtitle: current.rawValue,
            image: UIImage(systemName: "aspectratio"),
            children: actions
        )
    }

    /// Saves the choice, tells the Apple TV, and re-pushes the still when it's the live
    /// item so every screen reframes without waiting for the next selection.
    private func applyScreenFit(_ mode: MediaFitMode, to item: LibraryItemDTO) {
        guard MediaFitSettings.mode(forId: item.id) != mode else { return }
        MediaFitSettings.setMode(mode, forId: item.id)
        UISelectionFeedbackGenerator().selectionChanged()
        connectionManager.sendImageFit(id: item.id, isFill: mode == .fill)
        reloadLibraryGrid()
        refreshLiveHeader()

        let manager = ExternalDisplayManager.shared
        guard store.currentId == item.id,
              !manager.isOverlayLive,
              !manager.isJoinedLive else { return }
        manager.present(.forLibraryItem(item, thumbnail: store.thumbnail(for: item.id)))
    }
}
