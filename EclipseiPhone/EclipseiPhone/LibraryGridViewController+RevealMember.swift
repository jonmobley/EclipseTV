//
//  LibraryGridViewController+RevealMember.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import UIKit

extension LibraryGridViewController {

    /// Scrolls the Show grid to a just-added member so the new thumbnail is on screen.
    func revealAddedShowMember(id: String) {
        revealAddedShowMember(id: id, retry: true)
    }

    private func revealAddedShowMember(id: String, retry: Bool) {
        reloadGridIfSafe()
        collectionView.layoutIfNeeded()
        guard isShowMode, let section = sectionIndex(for: .shows) else { return }
        if let item = Self.indexOfShowMember(id, in: openShowGridItems) {
            collectionView.scrollToItem(
                at: IndexPath(item: item, section: section),
                at: .centeredVertically,
                animated: true
            )
            return
        }
        guard retry else { return }
        DispatchQueue.main.async { [weak self] in
            self?.revealAddedShowMember(id: id, retry: false)
        }
    }

    /// Index of a Show-grid member id (media / website / PDF).
    static func indexOfShowMember(_ id: String, in items: [ShowGridItem]) -> Int? {
        items.firstIndex { item in
            switch item {
            case .media(let media):
                return media.id == id
            case .website(let page):
                return page.id.uuidString.caseInsensitiveCompare(id) == .orderedSame
            case .pdf(let doc):
                return doc.id.uuidString.caseInsensitiveCompare(id) == .orderedSame
            default:
                return false
            }
        }
    }
}
