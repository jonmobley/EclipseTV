//
//  ImageViewController+GridDelegates.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

// ImageViewController+GridDelegates.swift
import UIKit
import os.log

// MARK: - HelpViewDelegate

extension ImageViewController: HelpViewDelegate {
    func didTapCloseButton() {
        UIView.animate(withDuration: 0.3, animations: {
            self.helpView.alpha = 0
        }) { _ in
            self.helpView.isHidden = true
        }
    }
}

// MARK: - UICollectionViewDelegateFlowLayout

extension ImageViewController: UICollectionViewDelegateFlowLayout {
    func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, referenceSizeForHeaderInSection section: Int) -> CGSize {
        return CGSize(width: collectionView.bounds.width, height: 120)
    }

    func collectionView(_ collectionView: UICollectionView, viewForSupplementaryElementOfKind kind: String, at indexPath: IndexPath) -> UICollectionReusableView {
        guard kind == UICollectionView.elementKindSectionHeader else {
            return UICollectionReusableView()
        }

        let headerView = collectionView.dequeueReusableSupplementaryView(ofKind: kind, withReuseIdentifier: "HeaderView", for: indexPath)

        // Reset any reused content
        headerView.subviews.forEach { $0.removeFromSuperview() }

        // Each album section gets its own header label; the library section keeps the
        // shared "Eclipse" title (whose alpha is animated during transitions).
        if indexPath.section != ImageViewController.librarySectionIndex {
            // Apple "shelf" style: a left-aligned title sitting just above the row,
            // lined up with the row's leading content inset (see AdaptiveFlowLayout).
            let albumLabel = UILabel()
            albumLabel.text = albumStore.album(at: indexPath.section - 1)?.name ?? "Album"
            albumLabel.textColor = .white
            albumLabel.font = UIFont.systemFont(ofSize: 38, weight: .semibold)
            albumLabel.textAlignment = .left
            albumLabel.translatesAutoresizingMaskIntoConstraints = false
            headerView.addSubview(albumLabel)
            NSLayoutConstraint.activate([
                albumLabel.leadingAnchor.constraint(equalTo: headerView.leadingAnchor, constant: 120),
                albumLabel.trailingAnchor.constraint(lessThanOrEqualTo: headerView.trailingAnchor, constant: -120),
                albumLabel.bottomAnchor.constraint(equalTo: headerView.bottomAnchor, constant: -12)
            ])
            return headerView
        }

        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        headerView.addSubview(titleLabel)
        NSLayoutConstraint.activate([
            titleLabel.centerXAnchor.constraint(equalTo: headerView.centerXAnchor),
            titleLabel.topAnchor.constraint(equalTo: headerView.topAnchor, constant: 20)
        ])
        return headerView
    }
}

// MARK: - MediaDataSourceDelegate Implementation

extension ImageViewController: MediaDataSourceDelegate {

    func mediaDataDidChange() {
        DispatchQueue.main.async {
            // Always reload the grid when data changes
            self.gridView.reloadData()

            // Validate selection state after data reload to prevent multiple blue strokes
            // Use another async dispatch to ensure reload is complete
            DispatchQueue.main.async {
                self.simpleSelectionManager.validateSelectionState()
                // Also validate synchronization between visual and data selection
                self.validateSelectionSync()
            }

            self.logger.info("MediaDataSourceDelegate.mediaDataDidChange() called - data source count: \(self.dataSource.count)")
        }
    }

    func mediaData(_ dataSource: MediaDataSource, didAddItemAt index: Int) {
        DispatchQueue.main.async {
            // Animate insertion
            let indexPath = IndexPath(item: index, section: 0)
            self.gridView.performBatchUpdates({
                self.gridView.insertItems(at: [indexPath])
            }) { _ in
                // Select the new item
                self.simpleSelectionManager.selectItem(at: indexPath)
                self.setNeedsFocusUpdate()
                self.updateFocusIfNeeded()
            }
        }
    }

    func mediaData(_ dataSource: MediaDataSource, didRemoveItemAt index: Int) {
        DispatchQueue.main.async {
            self.logger.debug("🗑️ Starting deletion process for index \(index)")

            // CRITICAL: Disable focus updates during deletion to prevent tvOS from interfering
            self.gridView.remembersLastFocusedIndexPath = false

            // Animate removal
            let indexPath = IndexPath(item: index, section: 0)
            self.gridView.performBatchUpdates({
                self.gridView.deleteItems(at: [indexPath])
            }) { completed in
                // Handle selection after item deletion
                self.logger.debug("🗑️ Collection view delete animation completed: \(completed)")

                if !dataSource.isEmpty {
                    let newSelectedIndex: Int

                    if index >= dataSource.count {
                        // Deleted the last item - select the new last item (previous item)
                        newSelectedIndex = dataSource.count - 1
                        self.logger.debug("🗑️ Deleted last item at index \(index), selecting new last item at index \(newSelectedIndex)")
                    } else {
                        // Deleted a non-last item - keep the same index position
                        newSelectedIndex = index
                        self.logger.debug("🗑️ Deleted middle item at index \(index), keeping selection at same position")
                    }

                    self.logger.debug("🗑️ About to update selection - current focus: \(self.gridView.indexPathsForVisibleItems)")

                    // Update data source to match UI selection
                    dataSource.setCurrentIndex(newSelectedIndex)

                    // Clear any existing selection immediately to prevent conflicts
                    self.simpleSelectionManager.clearSelection()

                    // Use a longer delay and force layout completion
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                        self.logger.debug("🗑️ Applying delayed selection to index \(newSelectedIndex)")

                        // Force layout update before setting selection
                        self.gridView.layoutIfNeeded()

                        let newIndexPath = IndexPath(item: newSelectedIndex, section: 0)
                        self.simpleSelectionManager.selectItem(at: newIndexPath)

                        // Re-enable focus updates after selection is complete
                        self.gridView.remembersLastFocusedIndexPath = true

                        // Force focus update
                        self.setNeedsFocusUpdate()
                        self.updateFocusIfNeeded()

                        // Validate selection synchronization after deletion
                        self.validateSelectionSync()

                        self.logger.debug("🗑️ Selection update complete - focus system re-enabled")
                    }
                } else {
                    self.logger.debug("🗑️ Data source is empty after deletion")
                    // Re-enable focus updates even if data source is empty
                    self.gridView.remembersLastFocusedIndexPath = true
                }
            }
        }
    }

    func mediaData(_ dataSource: MediaDataSource, didMoveItemFrom sourceIndex: Int, to targetIndex: Int) {
        DispatchQueue.main.async {
            // Animate move
            let sourceIndexPath = IndexPath(item: sourceIndex, section: 0)
            let targetIndexPath = IndexPath(item: targetIndex, section: 0)

            self.gridView.performBatchUpdates({
                self.gridView.moveItem(at: sourceIndexPath, to: targetIndexPath)
            }) { _ in
                // Maintain selection on moved item
                let currentIndexPath = IndexPath(item: dataSource.currentIndex, section: 0)
                self.simpleSelectionManager.selectItem(at: currentIndexPath)
            }
        }
    }
}
