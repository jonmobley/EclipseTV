//
//  LibraryGridViewController+HomeRecentFilter.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import UIKit

// MARK: - Home Recent Format Filter

extension LibraryGridViewController {

    /// Chips only when the library has both Landscape and Vertical Shows.
    var showsHomeRecentFormatFilter: Bool {
        HomeGridItem.hasBothOrientations(in: LocalAlbumStore.shared.albums)
    }

    /// All / Horizontal / Vertical chips for the Recent header. All is default.
    func homeRecentFilterActions() -> [HomeSectionHeaderView.Action] {
        guard showsHomeRecentFormatFilter else { return [] }
        return ShowFormatFilter.allCases.map { filter in
            filterAction(title: filter.title, orientation: filter.orientation)
        }
    }

    /// Applies a Recent format filter and reloads only the Home page.
    func setHomeRecentOrientationFilter(_ orientation: ExternalOutputOrientation?) {
        let allowed = showsHomeRecentFormatFilter ? orientation : nil
        guard homeRecentOrientationFilter != allowed else { return }
        homeRecentOrientationFilter = allowed
        homeCollectionView.reloadData()
        homeCollectionView.collectionViewLayout.invalidateLayout()
    }

    private func filterAction(
        title: String,
        orientation: ExternalOutputOrientation?
    ) -> HomeSectionHeaderView.Action {
        HomeSectionHeaderView.Action(
            title: title,
            isSelected: homeRecentOrientationFilter == orientation
        ) { [weak self] in
            self?.setHomeRecentOrientationFilter(orientation)
        }
    }
}
