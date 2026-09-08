//
//  LibraryGridViewController+ItemOptions.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import UIKit

// MARK: - Per-item Options

extension LibraryGridViewController {
    func presentOptions(forItemId id: String) {
        guard let index = store.items.firstIndex(where: { $0.id == id }) else { return }
        let item = store.items[index]

        let sheet = UIAlertController(title: nil, message: nil, preferredStyle: .actionSheet)

        // Purged items can't play; only offer to re-send from Photos or remove them.
        if item.isAvailable == false {
            sheet.title = item.name
            sheet.message = "This item's file is no longer on the Apple TV."
            sheet.addAction(UIAlertAction(title: "Re-send from Photos", style: .default) { [weak self] _ in
                self?.onRequestResend?(id)
            })
            sheet.addAction(UIAlertAction(title: "Remove from Apple TV", style: .destructive) { [weak self] _ in
                self?.runCommand { self?.connectionManager.sendDeleteRequest(id: id) ?? false }
            })
            sheet.addAction(UIAlertAction(title: "Cancel", style: .cancel))
            if let popover = sheet.popoverPresentationController {
                let anchor = cellForShowMedia(id: id) ?? view
                popover.sourceView = anchor
                popover.sourceRect = anchor?.bounds ?? view.bounds
            }
            present(sheet, animated: true)
            return
        }

        sheet.addAction(UIAlertAction(title: "Make Live", style: .default) { [weak self] _ in
            guard let self,
                  let item = self.store.items.first(where: { $0.id == id }) else { return }
            self.presentMedia(item)
        })

        if item.isVideo {
            let loopOn = item.isLooping ?? false
            sheet.addAction(UIAlertAction(
                title: loopOn ? "Loop ✓" : "Loop",
                style: .default
            ) { [weak self] _ in
                self?.applyVideoSetting(id: id, isLooping: !loopOn, isMuted: nil)
            })

            let muted = item.isMuted ?? false
            sheet.addAction(UIAlertAction(
                title: muted ? "Mute ✓" : "Mute",
                style: .default
            ) { [weak self] _ in
                self?.applyVideoSetting(id: id, isLooping: nil, isMuted: !muted)
            })

            if LocalMediaStore.shared.localURL(forId: id) != nil {
                sheet.addAction(UIAlertAction(
                    title: "Choose Thumbnail…",
                    style: .default
                ) { [weak self] _ in
                    self?.onRequestVideoThumbnail?(id)
                })
            }
        }

        sheet.addAction(UIAlertAction(title: "Delete", style: .destructive) { [weak self] _ in
            self?.confirmDelete(id: id, name: item.name)
        })

        sheet.addAction(UIAlertAction(title: "Cancel", style: .cancel))

        // iPad requires a popover anchor.
        if let popover = sheet.popoverPresentationController {
            let anchor = cellForShowMedia(id: id) ?? view
            popover.sourceView = anchor
            popover.sourceRect = anchor?.bounds ?? view.bounds
        }

        present(sheet, animated: true)
    }

    /// Visible Show-grid cell for a media id, used as a popover source.
    private func cellForShowMedia(id: String) -> UIView? {
        guard let showsSection = sectionIndex(for: .shows),
              let item = openShowGridItems.firstIndex(where: {
                  if case .media(let media) = $0 { return media.id == id }
                  return false
              })
        else { return nil }
        return collectionView.cellForItem(
            at: IndexPath(item: item, section: showsSection)
        )
    }

    /// Runs a command closure; if it fails (not connected), surfaces a friendly alert.
    func runCommand(_ command: () -> Bool) {
        if command() {
            Haptics.impactLight()
        } else {
            presentNotConnectedAlert()
        }
    }

    func itemSize(for width: CGFloat) -> CGSize {
        let orientation = ExternalOutputSettings.orientation
        let columns = CGFloat(orientation.gridColumnCount(
            forWidth: width, sectionInset: sectionInset, spacing: interitemSpacing
        ))
        let totalSpacing = sectionInset * 2 + interitemSpacing * (columns - 1)
        let itemWidth = ((width - totalSpacing) / columns).rounded(.down)
        let itemHeight = (itemWidth * orientation.gridCellHeightOverWidth).rounded(.down)
        return CGSize(width: itemWidth, height: itemHeight)
    }
}
