// ImageViewController+UserInterface.swift
import UIKit
import ObjectiveC  // For associated objects

// Use explicit extension declaration
extension ImageViewController {

    /// Shows the help view with a fade-in animation
    internal func showHelpView() {
        helpView.isHidden = false
        helpView.alpha = 0
        
        UIView.animate(withDuration: 0.3) {
            self.helpView.alpha = 1
        }
    }
    
    /// Shows the instruction label with a fade-in animation
    internal func showInstructions() {
        instructionLabel.isHidden = false
        instructionLabel.alpha = 0
        
        UIView.animate(withDuration: 0.3) {
            self.instructionLabel.alpha = 1
        }
    }
    
    /// Hides the instruction label with a fade-out animation
    internal func hideInstructions() {
        UIView.animate(withDuration: 0.3, animations: {
            self.instructionLabel.alpha = 0
        }) { _ in
            self.instructionLabel.isHidden = true
        }
    }
    
    /// Shows a notification toast with the given message
    internal func showNotificationToast(message: String) {
        let toastView = UIView(frame: CGRect(x: 0, y: 0, width: 500, height: 80))
        toastView.backgroundColor = UIColor.black.withAlphaComponent(0.7)
        toastView.layer.cornerRadius = 10
        
        let label = UILabel(frame: toastView.bounds)
        label.text = message
        label.textColor = .white
        label.textAlignment = .center
        label.font = UIFont.systemFont(ofSize: 24)
        
        toastView.addSubview(label)
        view.addSubview(toastView)
        
        // Position in top right with padding from edges
        toastView.frame.origin.x = view.bounds.width - toastView.frame.width - 60  // 60pt padding from right edge
        toastView.frame.origin.y = 100
        
        // Animate in
        toastView.alpha = 0
        UIView.animate(withDuration: 0.3, animations: {
            toastView.alpha = 1
        }) { _ in
            // Animate out after delay
            UIView.animate(withDuration: 0.3, delay: 3.0, options: [], animations: {
                toastView.alpha = 0
            }) { _ in
                toastView.removeFromSuperview()
            }
        }
    }

    internal func showGridViewTransition() {
        PerformanceMonitor.shared.measureUIOperation("showGridViewTransition") {
            logger.info("🔄 [FULLSCREEN→GRID] Showing grid view with smooth transition")

            // Use the smooth showGridView method instead of abrupt transition
            showGridView()
        }
    }
    
    internal func hideGridViewTransition() {
        PerformanceMonitor.shared.measureUIOperation("hideGridViewTransition") {
            logger.info("Hiding grid view")

            // Sync the data source to the grid's selected item (if any) before transitioning
            if let selectedIndexPath = self.gridView.indexPathsForSelectedItems?.first {
                // Verify the selected index is valid
                guard selectedIndexPath.item < self.dataSource.count else {
                    logger.warning("Selected index \(selectedIndexPath.item) is out of bounds")
                    return
                }
                
                dataSource.setCurrentIndex(selectedIndexPath.item)
                
                // Verify the image file exists
                guard let imagePath = dataSource.getCurrentPath() else {
                    logger.error("No current path available")
                    return
                }
                
                if !FileManager.default.fileExists(atPath: imagePath) {
                    logger.error("Image file does not exist at path: \(imagePath)")
                    // Remove the invalid path and reload the grid
                    for index in 0..<dataSource.count {
                        if dataSource.getPath(at: index) == imagePath {
                            dataSource.removeMedia(at: index)
                            break
                        }
                    }
                    return
                }
            }
            
            // Delegate to the canonical grid->fullscreen transition, which actually loads
            // and displays the current media (the previous inline fade did not).
            hideGridView()
        }
    }

    internal func toggleGridView() {
        if isInGridMode {
            hideGridViewTransition()
        } else {
            showGridViewTransition()
        }
    }

    internal func toggleControls() {
        let shouldHide = titleLabel.alpha > 0
        UIView.animate(withDuration: 0.3) { [self] in
            self.titleLabel.alpha = shouldHide ? 0 : 1
            self.gradientView.alpha = shouldHide ? 0 : 1
        }
    }

    internal func showHelp() {
        helpView.isHidden = false
        helpView.alpha = 0
        UIView.animate(withDuration: 0.3) { [self] in
            self.helpView.alpha = 1
        }
    }
    
    internal func showOptionsMenu() {
        logger.info("Showing options menu")
        
        let alertController = UIAlertController(title: "EclipseTV Options", message: nil, preferredStyle: .actionSheet)
        
        if !isInGridMode {
            alertController.addAction(UIAlertAction(title: "Show Image Grid", style: .default) { [weak self] _ in
                self?.showGridViewTransition()
            })
        }

        // Remote album controls. An account code can be entered here on the TV or pushed
        // from the iPhone companion; once configured the TV can resync or remove albums.
        let accountCodeTitle = albumStore.hasAlbumConfigured ? "Change Account Code" : "Enter Account Code"
        alertController.addAction(UIAlertAction(title: accountCodeTitle, style: .default) { [weak self] _ in
            self?.presentAccountCodeEntry()
        })
        if albumStore.hasAlbumConfigured {
            alertController.addAction(UIAlertAction(title: "Refresh Albums", style: .default) { [weak self] _ in
                self?.refreshAlbumFromMenu()
            })
            alertController.addAction(UIAlertAction(title: "Remove Albums", style: .destructive) { [weak self] _ in
                Task { @MainActor in
                    self?.albumStore.clearAlbum()
                    self?.albumNotifier.stop()
                    self?.showNotificationToast(message: "Albums removed")
                }
            })
        }
        #if DEBUG
        alertController.addAction(UIAlertAction(title: "Load Demo Album", style: .default) { [weak self] _ in
            self?.loadDemoAlbum()
        })
        #endif

        alertController.addAction(UIAlertAction(title: "Show Help", style: .default) { [weak self] _ in
            self?.showHelp()
        })
        
        // Sample images are now always loaded automatically on launch
        // No need for manual reload option
        
        #if DEBUG
        alertController.addAction(UIAlertAction(title: "Performance Stats", style: .default) { _ in
            self.showPerformanceStats()
        })
        
        alertController.addAction(UIAlertAction(title: "Reset Performance Data", style: .default) { _ in
            PerformanceMonitor.shared.resetMeasurements()
            self.showNotificationToast(message: "Performance data reset")
        })
        
        alertController.addAction(UIAlertAction(title: "Reset First Launch (Reload Samples)", style: .default) { [weak self] _ in
            guard let self = self else { return }
            UserDefaults.standard.removeObject(forKey: self.hasLaunchedBeforeKey)
            self.showNotificationToast(message: "First launch flag reset - sample media will reload on next launch")
        })
        #endif
        
        if !self.dataSource.isEmpty {
            alertController.addAction(UIAlertAction(title: "Remove From Recents", style: .destructive) { [weak self] _ in
                guard let self = self, !self.dataSource.isEmpty, self.dataSource.currentIndex < self.dataSource.count,
                      let pathToRemove = self.dataSource.getPath(at: self.dataSource.currentIndex) else { return }
                
                self.removeImageFromRecents(path: pathToRemove)
            })
        }
        
        alertController.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        
        present(alertController, animated: true)
    }
    
    // MARK: - Empty State Management
    
    /// Shows the empty state view when there are no images or videos
    internal func showEmptyState() {
        logger.info("🟦 [EMPTY] Showing empty state view")
        
        // Hide grid view and other UI elements
        gridView.isHidden = true
        imageView.isHidden = true
        playerView.view.isHidden = true
        instructionLabel.isHidden = true
        
        // Keep the gradient background visible
        gradientView.isHidden = false
        
        // Make sure the title remains visible at the top
        titleLabel.isHidden = false
        titleLabel.alpha = 1.0
        
        // Show the empty state view
        emptyStateView.show(in: view)
        logger.info("🟦 [EMPTY] Empty state added to view hierarchy")
        
        // Bring the title label to front so it's above the empty state view
        view.bringSubviewToFront(titleLabel)

        // Keep the options button reachable so a user with no local media can still enter
        // their account code from here.
        updateOptionsButtonVisibility()
        
        // Ensure focus is reset
        setNeedsFocusUpdate()
        updateFocusIfNeeded()
        logger.info("🟦 [EMPTY] Focus updated for empty state")
    }
    
    /// Hides the empty state view
    internal func hideEmptyState() {
        logger.info("🟩 [EMPTY] Hiding empty state view")
        
        // Hide the empty state view with animation
        emptyStateView.hide()
        
        // Make sure we're in grid mode
        isInGridMode = true
        
        // Show grid view and all related UI
        gridView.isHidden = false
        gradientView.isHidden = false
        titleLabel.isHidden = false
        updateOptionsButtonVisibility()
        
        // Make sure image view and player are hidden
        imageView.isHidden = true
        playerView.view.isHidden = true
        
        // Force grid view to update
        logger.info("🟩 [EMPTY] Reloading grid after hiding empty state, count=\(self.dataSource.count)")
        gridView.reloadData()
        
        // Select the first item if available with proper async handling
        DispatchQueue.main.async {
            if !self.dataSource.isEmpty {
                let targetIndexPath = IndexPath(item: 0, section: 0)
                
                // Use SimpleSelectionManager for consistent selection handling
                self.simpleSelectionManager.selectItem(at: targetIndexPath)
                self.dataSource.setCurrentIndex(0)
                
                // Validate selection state after all operations
                self.simpleSelectionManager.validateSelectionState()
            }
        }
        
        // Update focus
        setNeedsFocusUpdate()
        updateFocusIfNeeded()
    }

    #if DEBUG
    private func showPerformanceStats() {
        let stats = PerformanceMonitor.shared.getPerformanceSummary()
        let alert = UIAlertController(title: "Performance Stats", message: stats, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        present(alert, animated: true)
    }
    #endif
}
