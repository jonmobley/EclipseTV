//
//  MediaLibraryPickerViewController+Search.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import UIKit

// MARK: - Title Search

extension MediaLibraryPickerViewController: UISearchResultsUpdating, UISearchControllerDelegate {

    /// Magnifying glass stays trailing; Add stays further trailing in Show mode.
    func updateRightBarButtons(searchActive: Bool) {
        var items: [UIBarButtonItem] = []
        if let addButton, isAddToShowMode {
            items.append(addButton)
        }
        if !searchActive {
            items.append(searchBarButton)
        }
        navigationItem.rightBarButtonItems = items.isEmpty ? nil : items
    }

    /// Reveals the nav-bar search field and focuses it.
    @objc func searchTapped() {
        let search = installedSearchController()
        navigationItem.searchController = search
        navigationItem.hidesSearchBarWhenScrolling = false
        updateRightBarButtons(searchActive: true)
        search.isActive = true
    }

    func updateSearchResults(for searchController: UISearchController) {
        searchQuery = searchController.searchBar.text ?? ""
        reload()
    }

    func didDismissSearchController(_ searchController: UISearchController) {
        let needle = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        if needle.isEmpty {
            navigationItem.searchController = nil
            self.searchController = nil
        }
        updateRightBarButtons(searchActive: navigationItem.searchController != nil)
    }

    private func installedSearchController() -> UISearchController {
        if let searchController { return searchController }
        let search = UISearchController(searchResultsController: nil)
        search.searchResultsUpdater = self
        search.delegate = self
        search.obscuresBackgroundDuringPresentation = false
        search.searchBar.placeholder = "Search titles"
        search.searchBar.autocapitalizationType = .none
        search.searchBar.returnKeyType = .search
        searchController = search
        definesPresentationContext = true
        return search
    }
}
