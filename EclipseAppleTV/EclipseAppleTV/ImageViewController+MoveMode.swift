// ImageViewController+MoveMode.swift
import UIKit

// MARK: - Image Move Mode Extension
extension ImageViewController {
    
    // Show options menu with move functionality
    @objc func handleLongPress(_ gesture: UILongPressGestureRecognizer) {
        // Only trigger once when gesture begins
        if gesture.state == .began {
            guard let cell = gesture.view as? ImageThumbnailCell else { return }
            let index = cell.tag
            
            guard index < dataSource.count else { return }
            
            // Check if it's a video file
            guard let imagePath = dataSource.getPath(at: index) else { return }
            let url = URL(fileURLWithPath: imagePath)
            let isVideo = url.pathExtension.lowercased() == "mp4" || url.pathExtension.lowercased() == "mov"
            
            if isVideo {
                showVideoOptionsMenu(forVideoAt: index)
            } else {
                showDeleteMenu(forImageAt: index)
            }
        }
    }
    
    // Show options menu with move functionality
    internal func showDeleteMenu(forImageAt index: Int) {
        guard index < dataSource.count else { return }
        
        let alertController = UIAlertController(title: "Image Options", message: nil, preferredStyle: .actionSheet)
        
        // Move option
        alertController.addAction(UIAlertAction(title: "Move", style: .default) { [weak self] _ in
            self?.startMoveMode(forImageAt: index)
        })
        
        // Delete option
        alertController.addAction(UIAlertAction(title: "Delete Image", style: .destructive) { [weak self] _ in
            guard let self = self else { return }
            
            if index < self.dataSource.count {
                self.dataSource.removeMedia(at: index)
            }
            
            // Process any queued content after deletion
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
                self?.processQueuedContent()
            }
        })
        
        // Cancel option
        alertController.addAction(UIAlertAction(title: "Cancel", style: .cancel) { [weak self] _ in
            // Process any queued content after canceling
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
                self?.processQueuedContent()
            }
        })
        
        present(alertController, animated: true)
    }

    // Show video-specific options menu
    internal func showVideoOptionsMenu(forVideoAt index: Int) {
        guard index < dataSource.count else { return }
        
        guard let videoPath = dataSource.getPath(at: index) else { return }
        
        // Get settings from the new system (viewModel/AppState) for consistency
        let mediaItem = MediaItem(path: videoPath)
        let settings = viewModel.getVideoSettings(for: mediaItem)
        var isMuted = settings.isMuted
        var isLooping = settings.isLooping
        
        let alertController = UIAlertController(title: "Video Options", message: nil, preferredStyle: .actionSheet)
        
        // Create mute action - we'll save a reference to update it later
        let muteAction = UIAlertAction(title: isMuted ? "Audio: Muted" : "Audio: On", style: .default) { [weak self, weak alertController] _ in
            guard let self = self, let alertController = alertController else { return }
            
            // Toggle the setting
            isMuted = !isMuted
            
            // Update both old and new systems for compatibility
            self.setVideoSetting(for: videoPath, setting: "mute", value: isMuted)
            
            // Update the new system (viewModel/AppState)
            let mediaItem = MediaItem(path: videoPath)
            self.viewModel.updateVideoSetting(for: mediaItem, keyPath: \.isMuted, value: isMuted)
            
            // Apply settings to currently playing video if this is the active video
            if let currentPath = self.dataSource.getCurrentPath(), currentPath == videoPath {
                self.applySettingsToCurrentVideo()
            }
            
            // Show confirmation
            let message = !isMuted ? "Audio turned on" : "Audio muted"
            self.showNotificationToast(message: message)
            
            // Update the button title in place
            if let muteButton = alertController.actions.first(where: { $0.title?.contains("Audio:") == true }) {
                muteButton.setValue(isMuted ? "Audio: Muted" : "Audio: On", forKey: "title")
            }
            
            // Update the cell to show the new indicator state
            let indexPath = IndexPath(item: index, section: 0)
            if let cell = self.gridView.cellForItem(at: indexPath) as? ImageThumbnailCell {
                // Get current settings
                let duration = cell.getDuration()
                let isLooping = self.getVideoSetting(for: videoPath, setting: "loop")
                
                // Update cell with new settings
                cell.configure(with: cell.currentImage, isVideo: true, duration: duration, isLooping: isLooping, isMuted: isMuted)
            }
        }
        
        // Create loop action - we'll save a reference to update it later
        let loopAction = UIAlertAction(title: isLooping ? "Loop: Yes" : "Loop: No", style: .default) { [weak self, weak alertController] _ in
            guard let self = self, let alertController = alertController else { return }
            
            // Toggle the setting
            isLooping = !isLooping
            
            // Update both old and new systems for compatibility
            self.setVideoSetting(for: videoPath, setting: "loop", value: isLooping)
            
            // Update the new system (viewModel/AppState)
            let mediaItem = MediaItem(path: videoPath)
            self.viewModel.updateVideoSetting(for: mediaItem, keyPath: \.isLooping, value: isLooping)
            
            // Apply settings to currently playing video if this is the active video
            if let currentPath = self.dataSource.getCurrentPath(), currentPath == videoPath {
                self.applySettingsToCurrentVideo()
            }
            
            // Show confirmation
            let message = !isLooping ? "Loop turned off" : "Loop turned on"
            self.showNotificationToast(message: message)
            
            // Update the button title in place
            if let loopButton = alertController.actions.first(where: { $0.title?.contains("Loop:") == true }) {
                loopButton.setValue(isLooping ? "Loop: Yes" : "Loop: No", forKey: "title")
            }
            
            // Update the cell to show the new indicator state
            let indexPath = IndexPath(item: index, section: 0)
            if let cell = self.gridView.cellForItem(at: indexPath) as? ImageThumbnailCell {
                // Get current settings
                let duration = cell.getDuration()
                let isMuted = self.getVideoSetting(for: videoPath, setting: "mute")
                
                // Update cell with new settings
                cell.configure(with: cell.currentImage, isVideo: true, duration: duration, isLooping: isLooping, isMuted: isMuted)
            }
        }
        
        // Add actions to controller
        alertController.addAction(muteAction)
        alertController.addAction(loopAction)
        
        // Move option
        alertController.addAction(UIAlertAction(title: "Move", style: .default) { [weak self] _ in
            self?.startMoveMode(forImageAt: index)
        })
        
        // Delete option
        alertController.addAction(UIAlertAction(title: "Delete Video", style: .destructive) { [weak self] _ in
            guard let self = self else { return }
            
            if index < self.dataSource.count {
                self.dataSource.removeMedia(at: index)
            }
        })
        
        // Done option (previously Cancel)
        alertController.addAction(UIAlertAction(title: "Done", style: .cancel) { [weak self] _ in
            // Process any queued content after dismissing the menu
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
                self?.processQueuedContent()
            }
        })
        
        // Present the menu
        present(alertController, animated: true)
    }

    // Start move mode for a specific image
    internal func startMoveMode(forImageAt index: Int) {
        isMoveMode = true
        movingItemIndex = index
        movingItemIndexPath = IndexPath(item: index, section: 0)
        
        // Notify connection manager that we're in move mode
        // This will cause received content to be queued instead of immediately shown
        if let appDelegate = UIApplication.shared.delegate as? AppDelegate {
            appDelegate.connectionManager?.notifyMoveModeEnabled(true)
        }
        
        // Explicitly select the item to ensure it has the blue stroke
        let indexPath = IndexPath(item: index, section: 0)
        gridView.selectItem(at: indexPath, animated: false, scrollPosition: .centeredVertically)
        
        // Show a move overlay with instructions
        showMoveOverlay()
        
        // Highlight the cell being moved
        if let cell = gridView.cellForItem(at: indexPath) {
            movingItemCell = cell
            highlightMovingCell(cell)
        }
        
        // Show toast with instructions
        showNotificationToast(message: "Navigate to reposition, press SELECT or tap item to finish")
    }

    // Highlight a cell that's being moved
    internal func highlightMovingCell(_ cell: UICollectionViewCell) {
        // Ensure the cell is selected (maintains blue stroke)
        cell.isSelected = true
        
        // Force layer to update - this makes the selection border visible immediately
        cell.layer.setNeedsDisplay()
        
        // Force layout update
        cell.setNeedsLayout()
        cell.layoutIfNeeded()
        
        // Ensure other cells are not selected
        for visibleCell in gridView.visibleCells {
            if visibleCell != cell {
                visibleCell.isSelected = false
            }
        }
        
        UIView.animate(withDuration: 0.2) {
            cell.transform = CGAffineTransform(scaleX: 1.1, y: 1.1)
            cell.alpha = 0.8
        }
        
        // Add a pulsing animation
        let pulseAnimation = CABasicAnimation(keyPath: "transform.scale")
        pulseAnimation.duration = 0.8
        pulseAnimation.fromValue = 1.05
        pulseAnimation.toValue = 1.15
        pulseAnimation.autoreverses = true
        pulseAnimation.repeatCount = Float.infinity
        cell.layer.add(pulseAnimation, forKey: "pulse")
    }

    // Reset a cell back to normal
    internal func resetMovingCell(_ cell: UICollectionViewCell) {
        UIView.animate(withDuration: 0.2) {
            cell.transform = .identity
            cell.alpha = 1.0
        }
        cell.layer.removeAnimation(forKey: "pulse")
    }

    // Show overlay with move instructions
    internal func showMoveOverlay() {
        let overlayView = UIView(frame: CGRect(x: 0, y: 0, width: 600, height: 80))
        overlayView.backgroundColor = UIColor.black.withAlphaComponent(0.7)
        overlayView.layer.cornerRadius = 10
        overlayView.tag = 2001 // Use tag to find and remove the view later
        
        let instructionLabel = UILabel(frame: overlayView.bounds)
        instructionLabel.text = "Navigate to reposition, press SELECT when done"
        instructionLabel.textColor = .white
        instructionLabel.textAlignment = .center
        instructionLabel.font = UIFont.systemFont(ofSize: 22)
        
        overlayView.addSubview(instructionLabel)
        view.addSubview(overlayView)
        
        overlayView.center.x = view.center.x
        overlayView.frame.origin.y = view.frame.height - 120
        
        overlayView.alpha = 0
        UIView.animate(withDuration: 0.3) {
            overlayView.alpha = 1
        }
    }

    // Hide move overlay
    internal func hideMoveOverlay() {
        if let overlayView = view.viewWithTag(2001) {
            UIView.animate(withDuration: 0.3, animations: {
                overlayView.alpha = 0
            }) { _ in
                overlayView.removeFromSuperview()
            }
        }
    }

    // End move mode and commit changes
    internal func endMoveMode() {
        guard isMoveMode,
              let _ = movingItemIndex else {
            return
        }
        
        // Notify connection manager that we're no longer in move mode
        if let appDelegate = UIApplication.shared.delegate as? AppDelegate {
            appDelegate.connectionManager?.notifyMoveModeEnabled(false)
        }
        
        // Set a flag to temporarily ignore item selection events
        isIgnoringSelectionEvents = true
        
        isMoveMode = false
        
        // Reset the moving cell appearance
        if let cell = movingItemCell {
            resetMovingCell(cell)
        }
        
        // Hide the move overlay
        hideMoveOverlay()
        
        // Show confirmation toast
        showNotificationToast(message: "Image position updated")
        
        // Update the SimpleSelectionManager with the current position
        if let indexPath = movingItemIndexPath {
            simpleSelectionManager.selectItem(at: indexPath)
        }
        
        // Reset tracking variables
        movingItemCell = nil
        movingItemIndex = nil
        movingItemIndexPath = nil
        
        // Reset the ignore selection flag after a short delay
        // This prevents the SELECT button press from triggering fullscreen mode
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            self.isIgnoringSelectionEvents = false
            
            // Process any content that was queued during move mode
            self.processQueuedContent()
        }
    }

    // Cancel move mode without committing changes
    internal func cancelMoveMode() {
        guard isMoveMode else { return }
        
        // Notify connection manager that we're no longer in move mode
        if let appDelegate = UIApplication.shared.delegate as? AppDelegate {
            appDelegate.connectionManager?.notifyMoveModeEnabled(false)
        }
        
        isMoveMode = false
        
        // Reset the moving cell appearance
        if let cell = movingItemCell {
            resetMovingCell(cell)
        }
        
        // Hide the move overlay
        hideMoveOverlay()
        
        // Reset tracking variables
        movingItemCell = nil
        movingItemIndex = nil
        movingItemIndexPath = nil
        
        // Reload the grid to reset any visual changes
        gridView.reloadData()
        
        // Validate selection state after reload to prevent multiple blue strokes
        DispatchQueue.main.async {
            self.simpleSelectionManager.validateSelectionState()
        }
        
        // Process any content that was queued during move mode
        processQueuedContent()
    }
    
    // Process directional button presses in move mode
    internal func handleMoveModeRemotePress(_ keyCode: UIKeyboardHIDUsage) -> Bool {
        guard isMoveMode else { return false }
        
        switch keyCode {
        case .keyboardReturnOrEnter:
            // Commit the move
            endMoveMode()
            return true
        case .keyboardEscape, .keyboardTab:
            // Cancel the move
            cancelMoveMode()
            return true
        default:
            // No longer handling directional keys here since they'll be handled by focus system
            return false
        }
    }

    // Move an item from one position to another with animation
    internal func moveItemToPosition(from sourceIndex: Int, to targetIndex: Int) {
        guard sourceIndex != targetIndex,
              sourceIndex < dataSource.count,
              targetIndex < dataSource.count,
              let _ = movingItemIndex,
              let _ = movingItemIndexPath else {
            return
        }

        logger.debug("Moving item from \(sourceIndex) to \(targetIndex)")

        // Let data source handle the move (it will call delegate methods)
        dataSource.moveMedia(from: sourceIndex, to: targetIndex)
    }

    // The following methods are kept for backward compatibility but won't be used in the new flow
    
    // Move the selected item up one row
    internal func moveItemUp() {
        // These methods are no longer needed - MediaDataSource handles moves automatically
        // through the delegate pattern when focus changes in move mode
    }

    // Move the selected item down one row
    internal func moveItemDown() {
        // These methods are no longer needed - MediaDataSource handles moves automatically
        // through the delegate pattern when focus changes in move mode
    }

    // Move the selected item left
    internal func moveItemLeft() {
        // These methods are no longer needed - MediaDataSource handles moves automatically
        // through the delegate pattern when focus changes in move mode
    }

    // Move the selected item right
    internal func moveItemRight() {
        // These methods are no longer needed - MediaDataSource handles moves automatically
        // through the delegate pattern when focus changes in move mode
    }
}
