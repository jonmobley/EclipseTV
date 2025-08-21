import UIKit
import AVFoundation

class ImageThumbnailCell: UICollectionViewCell {
    
    // MARK: - UI Elements
    
    private let imageView: UIImageView = {
        let view = UIImageView()
        view.contentMode = .scaleAspectFill  // Match fullscreen view behavior
        view.clipsToBounds = true
        view.backgroundColor = .black
        return view
    }()
    
    private let videoIndicator: UIImageView = {
        let view = UIImageView()
        view.image = UIImage(systemName: "play.circle.fill")?.withTintColor(.white, renderingMode: .alwaysOriginal)
        view.contentMode = .scaleAspectFill
        view.isHidden = true
        return view
    }()
    
    private let focusEffectView: UIView = {
        let view = UIView()
        view.layer.borderWidth = 6
        view.layer.borderColor = UIColor.systemBlue.cgColor
        view.layer.cornerRadius = 15
        view.isHidden = true
        return view
    }()
    
    private let selectionEffectView: UIView = {
        let view = UIView()
        view.layer.borderWidth = 8  // Thicker border for selection
        view.layer.borderColor = UIColor.systemBlue.cgColor
        view.layer.cornerRadius = 15
        view.isHidden = true
        return view
    }()
    
    // Constants for overlay sizing
    private let OVERLAY_HEIGHT: CGFloat = 48  // Increased from 36 for better visibility
    private let ICON_SIZE: CGFloat = 36       // Increased from 28 for better visibility
    private let ICON_PADDING: CGFloat = 8     // Increased from 6 for better spacing
    private let DURATION_FONT_SIZE: CGFloat = 24  // Increased from 20 for better readability
    
    private let durationBackground: UIView = {
        let view = UIView()
        view.backgroundColor = UIColor.black.withAlphaComponent(0.7)
        view.layer.cornerRadius = 10  // Increased from 8 to match larger overlay
        view.isHidden = true
        view.clipsToBounds = true
        return view
    }()
    
    private let durationLabel: UILabel = {
        let label = UILabel()
        label.textColor = .white
        label.font = UIFont.systemFont(ofSize: 24, weight: .medium)  // Updated to match DURATION_FONT_SIZE
        label.textAlignment = .center
        label.isHidden = true
        return label
    }()
    
    private let loopIndicator: UIImageView = {
        let view = UIImageView()
        let config = UIImage.SymbolConfiguration(pointSize: 28, weight: .medium)
        view.image = UIImage(systemName: "repeat.circle.fill", withConfiguration: config)?
            .withTintColor(.white, renderingMode: .alwaysOriginal)
        view.contentMode = .center
        view.isHidden = true
        view.backgroundColor = UIColor.black.withAlphaComponent(0.7)
        view.layer.cornerRadius = 8
        return view
    }()
    
    private let muteIndicator: UIImageView = {
        let view = UIImageView()
        let config = UIImage.SymbolConfiguration(pointSize: 28, weight: .medium)
        view.image = UIImage(systemName: "speaker.slash.fill", withConfiguration: config)?
            .withTintColor(.white, renderingMode: .alwaysOriginal)
        view.contentMode = .center
        view.isHidden = true
        view.backgroundColor = UIColor.black.withAlphaComponent(0.7)
        view.layer.cornerRadius = 8
        return view
    }()
    
    // Stack view to hold the indicators
    private let indicatorsStack: UIStackView = {
        let stack = UIStackView()
        stack.axis = .horizontal
        stack.spacing = 8
        stack.alignment = .center
        stack.distribution = .fill  // Changed from .fillEqually to .fill for more flexibility
        stack.isHidden = true
        stack.setContentHuggingPriority(UILayoutPriority(251), for: .horizontal)  // Help prevent stretching
        stack.setContentCompressionResistancePriority(UILayoutPriority(749), for: .horizontal)  // Allow compression if needed
        return stack
    }()
    
    // MARK: - Properties
    
    private var isVideo = false
    private var currentDuration: TimeInterval?
    var currentImage: UIImage?
    
    // Add these new properties for async loading:
    private var currentLoadingTask: Task<Void, Never>?
    private var currentItemPath: String?
    
    // MARK: - Initialization
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        setupUI()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    // MARK: - UI Setup
    
    private func setupUI() {
        // Add corner radius to cell
        layer.cornerRadius = 12
        clipsToBounds = true
        
        // Add image view
        contentView.addSubview(imageView)
        imageView.translatesAutoresizingMaskIntoConstraints = false
        
        // Add video indicator
        contentView.addSubview(videoIndicator)
        videoIndicator.translatesAutoresizingMaskIntoConstraints = false
        
        // Add duration background and label
        contentView.addSubview(durationBackground)
        durationBackground.translatesAutoresizingMaskIntoConstraints = false
        
        durationBackground.addSubview(durationLabel)
        durationLabel.translatesAutoresizingMaskIntoConstraints = false
        
        // Add indicators stack
        contentView.addSubview(indicatorsStack)
        indicatorsStack.translatesAutoresizingMaskIntoConstraints = false
        
        // Add indicators to stack
        indicatorsStack.addArrangedSubview(loopIndicator)
        indicatorsStack.addArrangedSubview(muteIndicator)
        
        // Set fixed size for indicator icons
        loopIndicator.translatesAutoresizingMaskIntoConstraints = false
        muteIndicator.translatesAutoresizingMaskIntoConstraints = false
        
        // Set up constraints with lower priorities to avoid conflicts with Apple TV focus system
        let loopHeightConstraint = loopIndicator.heightAnchor.constraint(equalToConstant: OVERLAY_HEIGHT)
        loopHeightConstraint.priority = UILayoutPriority(750)  // Reduced priority to avoid conflicts
        
        let loopWidthConstraint = loopIndicator.widthAnchor.constraint(equalToConstant: ICON_SIZE + (ICON_PADDING * 2))
        loopWidthConstraint.priority = UILayoutPriority(750)  // Reduced priority to avoid conflicts
        
        let muteHeightConstraint = muteIndicator.heightAnchor.constraint(equalToConstant: OVERLAY_HEIGHT)
        muteHeightConstraint.priority = UILayoutPriority(750)  // Reduced priority to avoid conflicts
        
        let muteWidthConstraint = muteIndicator.widthAnchor.constraint(equalToConstant: ICON_SIZE + (ICON_PADDING * 2))
        muteWidthConstraint.priority = UILayoutPriority(750)  // Reduced priority to avoid conflicts
        
        NSLayoutConstraint.activate([
            loopHeightConstraint,
            loopWidthConstraint,
            muteHeightConstraint,
            muteWidthConstraint
        ])
        
        // Add focus effect view
        contentView.addSubview(focusEffectView)
        focusEffectView.translatesAutoresizingMaskIntoConstraints = false
        
        // Add selection effect view (behind focus view)
        contentView.insertSubview(selectionEffectView, belowSubview: focusEffectView)
        selectionEffectView.translatesAutoresizingMaskIntoConstraints = false
        
        // Set constraints with lower priorities to avoid conflicts with Apple TV focus system
        let indicatorsStackBottomConstraint = indicatorsStack.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -12)
        indicatorsStackBottomConstraint.priority = UILayoutPriority(750)  // Reduced priority
        
        let indicatorsStackLeadingConstraint = indicatorsStack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 12)
        indicatorsStackLeadingConstraint.priority = UILayoutPriority(750)  // Keep consistent priority but make it exact
        
        let indicatorsStackHeightConstraint = indicatorsStack.heightAnchor.constraint(equalToConstant: OVERLAY_HEIGHT)
        indicatorsStackHeightConstraint.priority = UILayoutPriority(750)  // Reduced priority
        
        // Use a flexible trailing constraint instead of width to prevent conflicts
        let indicatorsStackTrailingConstraint = indicatorsStack.trailingAnchor.constraint(lessThanOrEqualTo: contentView.trailingAnchor, constant: -95)
        indicatorsStackTrailingConstraint.priority = UILayoutPriority(250)  // Very low priority to break easily
        
        NSLayoutConstraint.activate([
            // Image view takes up the entire cell
            imageView.topAnchor.constraint(equalTo: contentView.topAnchor),
            imageView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            imageView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            imageView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
            
            // Video indicator centered on the image
            videoIndicator.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
            videoIndicator.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            videoIndicator.widthAnchor.constraint(equalTo: contentView.widthAnchor, multiplier: 0.3),
            videoIndicator.heightAnchor.constraint(equalTo: videoIndicator.widthAnchor),
            
            // Duration label in bottom right
            durationBackground.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -12),
            durationBackground.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -12),
            durationBackground.heightAnchor.constraint(equalToConstant: OVERLAY_HEIGHT),
            
            // Duration label inside background with padding
            durationLabel.topAnchor.constraint(equalTo: durationBackground.topAnchor, constant: 3),
            durationLabel.leadingAnchor.constraint(equalTo: durationBackground.leadingAnchor, constant: 16),
            durationLabel.trailingAnchor.constraint(equalTo: durationBackground.trailingAnchor, constant: -16),
            durationLabel.bottomAnchor.constraint(equalTo: durationBackground.bottomAnchor, constant: -3),
            
            // Indicators stack in bottom left with flexible constraints
            indicatorsStackBottomConstraint,
            indicatorsStackLeadingConstraint,
            indicatorsStackHeightConstraint,
            indicatorsStackTrailingConstraint,
            
            // Focus effect covers the whole cell
            focusEffectView.topAnchor.constraint(equalTo: contentView.topAnchor),
            focusEffectView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            focusEffectView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            focusEffectView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
            
            selectionEffectView.topAnchor.constraint(equalTo: contentView.topAnchor),
            selectionEffectView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            selectionEffectView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            selectionEffectView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor)
        ])
        
        layer.shadowColor = UIColor.systemBlue.cgColor
        layer.shadowOffset = .zero
        layer.shadowOpacity = 0
        layer.shadowRadius = 20
    }
    
    override func layoutSubviews() {
        super.layoutSubviews()
        imageView.frame = contentView.bounds
        videoIndicator.frame = contentView.bounds
        focusEffectView.frame = contentView.bounds
        selectionEffectView.frame = contentView.bounds
    }
    
    // MARK: - Configuration
    
    func configure(with image: UIImage?, isVideo: Bool = false) {
        self.isVideo = isVideo
        self.currentImage = image
        if let image = image {
            imageView.image = image
        }
        videoIndicator.isHidden = !isVideo
        durationBackground.isHidden = !isVideo
        durationLabel.isHidden = !isVideo
        indicatorsStack.isHidden = !isVideo
        // Focus effect is now handled by isFocused override
    }
    
    func configure(with image: UIImage?, isVideo: Bool = false, duration: TimeInterval? = nil, isLooping: Bool = false, isMuted: Bool = false) {
        configure(with: image, isVideo: isVideo)
        self.currentDuration = duration
        
        if isVideo {
            // Show/hide loop indicator
            loopIndicator.isHidden = !isLooping
            
            // Show/hide mute indicator
            muteIndicator.isHidden = !isMuted
            
            // Only show indicators stack if at least one indicator is visible
            indicatorsStack.isHidden = !isLooping && !isMuted
            
            if let duration = duration {
                // Format duration
                let minutes = Int(duration) / 60
                let seconds = Int(duration) % 60
                
                // Use X:XX for videos under 10 minutes, XX:XX for longer videos
                if minutes < 10 {
                    durationLabel.text = String(format: "%d:%02d", minutes, seconds)
                } else {
                    durationLabel.text = String(format: "%02d:%02d", minutes, seconds)
                }
                
                // Ensure background is sized appropriately with padding
                durationLabel.sizeToFit()
                let labelWidth = durationLabel.frame.width
                
                // Update duration background width constraint if needed
                for constraint in durationBackground.constraints {
                    if constraint.firstAttribute == .width {
                        constraint.isActive = false
                    }
                }
                
                let widthConstraint = durationBackground.widthAnchor.constraint(equalToConstant: labelWidth + 32) // 16pt padding on each side for larger overlay
                widthConstraint.isActive = true
                
                // Show duration label
                durationBackground.isHidden = false
                durationLabel.isHidden = false
            } else {
                durationBackground.isHidden = true
                durationLabel.isHidden = true
            }
        } else {
            // Hide all video-related elements for non-videos
            durationBackground.isHidden = true
            durationLabel.isHidden = true
            indicatorsStack.isHidden = true
            loopIndicator.isHidden = true
            muteIndicator.isHidden = true
        }
    }
    
    // Returns the current duration value
    func getDuration() -> TimeInterval? {
        return currentDuration
    }
    
    // MARK: - Focus
    
    override func didUpdateFocus(in context: UIFocusUpdateContext, with coordinator: UIFocusAnimationCoordinator) {
        super.didUpdateFocus(in: context, with: coordinator)
        
        // CRITICAL: Update visual effects immediately to prevent dual blue strokes
        updateVisualEffects()
        
        // Debug logging to track focus changes
        print("🔵 [CELL] Focus changed for cell - isFocused: \(isFocused), isSelected: \(isSelected)")
        
        // Use the coordinator to ensure smooth transitions for transform and shadow
        coordinator.addCoordinatedAnimations({
            if self.isFocused {
                self.transform = CGAffineTransform(scaleX: 1.1, y: 1.1)
                self.layer.shadowOpacity = 0.6
            } else {
                self.transform = CGAffineTransform.identity
                self.layer.shadowOpacity = 0
            }
        })
    }
    
    

    
    override func prepareForReuse() {
        super.prepareForReuse()
        
        // Cancel any ongoing loading
        currentLoadingTask?.cancel()
        currentLoadingTask = nil
        
        // CRITICAL: Reset selection state to prevent blue stroke from sticking
        isSelected = false
        
        // Reset UI state
        currentImage = nil
        currentItemPath = nil
        videoIndicator.isHidden = true
        durationBackground.isHidden = true
        durationLabel.isHidden = true
        indicatorsStack.isHidden = true
        loopIndicator.isHidden = true
        muteIndicator.isHidden = true
        focusEffectView.isHidden = true
        selectionEffectView.isHidden = true
        currentDuration = nil
    }
    
    // MARK: - Async Loading
    
    func configureAsync(imagePath: String, isVideo: Bool, cellSize: CGSize, userPosition: CGPoint? = nil) {
        // Cancel previous loading task
        currentLoadingTask?.cancel()
        
        // Set the current item path for validation
        currentItemPath = imagePath
        
        // Set initial state
        self.isVideo = isVideo
        videoIndicator.isHidden = !isVideo
        
        // Start async loading
        currentLoadingTask = Task {
            // Calculate target size (thumbnail size)
            let targetSize = CGSize(width: cellSize.width * 2, height: cellSize.height * 2) // 2x for retina
            
            if isVideo {
                // For videos, check cache first, then generate thumbnail
                let image = await VideoThumbnailCache.shared.getThumbnailAsync(for: imagePath, targetSize: targetSize)
                
                // Check if task wasn't cancelled and cell is still for same item
                guard !Task.isCancelled else { return }
                
                await MainActor.run {
                    // Only update if we're still showing the same item
                    guard self.currentItemPath == imagePath else { return }
                    
                    if let image = image {
                        self.imageView.image = image
                        self.currentImage = image
                        self.configureVideoUI(for: imagePath)
                        
                        // Apply user positioning
                        self.applyUserPosition(userPosition)
                    }
                }
            } else {
                // For images, use async loader
                let image = await AsyncImageLoader.shared.loadImage(from: imagePath, targetSize: targetSize)
                
                // Check if task wasn't cancelled and cell is still for same item
                guard !Task.isCancelled else { return }
                
                await MainActor.run {
                    // Only update if we're still showing the same item
                    guard self.currentItemPath == imagePath else { return }
                    
                    if let image = image {
                        self.imageView.image = image
                        self.currentImage = image
                        
                        // Apply user positioning
                        self.applyUserPosition(userPosition)
                    }
                }
            }
        }
    }

    // Add helper methods:
    private func configureVideoUI(for videoPath: String) {
        // Configure video-specific indicators
        videoIndicator.isHidden = false
        
        // Preserve any existing duration and settings that were already set
        // The duration and indicators should already be configured by the collection view
        // This method just ensures video UI elements are visible after thumbnail loads
        
        // If we have a stored duration, make sure it's still displayed
        if let duration = currentDuration {
            // Re-apply duration formatting to ensure it's visible
            let minutes = Int(duration) / 60
            let seconds = Int(duration) % 60
            
            if minutes < 10 {
                durationLabel.text = String(format: "%d:%02d", minutes, seconds)
            } else {
                durationLabel.text = String(format: "%02d:%02d", minutes, seconds)
            }
            
            durationBackground.isHidden = false
            durationLabel.isHidden = false
        }
    }
    
    // MARK: - Selection State Management
    
    override var isSelected: Bool {
        didSet {
            // CRITICAL: Update visual effects to prevent dual blue strokes
            updateVisualEffects()
            
            // Debug logging to track selection changes
            if oldValue != isSelected {
                print("🔵 [CELL] Selection changed for cell - isSelected: \(isSelected)")
            }
        }
    }
    

    
    private func updateVisualEffects() {
        // Ensure we're on the main thread for UI updates
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            
            // CRITICAL: Only show one blue border at a time
            if self.isSelected {
                // When selected, hide focus effect and show selection effect
                self.focusEffectView.isHidden = true
                self.selectionEffectView.isHidden = false
            } else if self.isFocused {
                // When focused but not selected, show focus effect and hide selection effect
                self.focusEffectView.isHidden = false
                self.selectionEffectView.isHidden = true
            } else {
                // When neither focused nor selected, hide both effects
                self.focusEffectView.isHidden = true
                self.selectionEffectView.isHidden = true
            }
            
            // Force immediate layout update to apply changes
            self.setNeedsLayout()
            self.layoutIfNeeded()
        }
    }
    
    // MARK: - User Positioning
    
    /// Applies user-defined positioning to the thumbnail image
    private func applyUserPosition(_ position: CGPoint?) {
        if let position = position {
            // Scale the position proportionally for the smaller thumbnail
            let scaleFactor: CGFloat = 0.3 // Adjust the positioning to be less pronounced in thumbnails
            let scaledPosition = CGPoint(x: position.x * scaleFactor, y: position.y * scaleFactor)
            imageView.transform = CGAffineTransform(translationX: scaledPosition.x, y: scaledPosition.y)
        } else {
            // Reset to no transform
            imageView.transform = .identity
        }
    }
}
