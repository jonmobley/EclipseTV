// ImageViewController.swift
import UIKit
import os.log
import TVUIKit
import MultipeerConnectivity
import AVKit
import ObjectiveC  // For associated objects
import Combine

class ImageViewController: ManagedViewController, ConnectionManagerDelegate, UIGestureRecognizerDelegate, EmptyStateViewDelegate {
    
    // MARK: - UI Elements
    
    /// The image view that displays the selected JPEG fullscreen
    internal let imageView: UIImageView = {
        let view = UIImageView()
        view.contentMode = .scaleAspectFill // Fill screen with image, maintaining aspect ratio, centered
        view.clipsToBounds = true
        view.isHidden = true
        view.backgroundColor = .black
        return view
    }()
    
    /// Video player view for playing videos
    internal let playerView: AVPlayerViewController = {
        let view = AVPlayerViewController()
        view.view.isHidden = true
        view.view.backgroundColor = .black
        view.showsPlaybackControls = false  // Hide playback controls
        view.videoGravity = .resizeAspect  // Keep videos as they were
        return view
    }()
    
    /// Title label for the grid view
    internal let titleLabel: UILabel = {
        let label = UILabel()
        label.text = "Eclipse"
        label.textColor = .white
        label.font = UIFont.systemFont(ofSize: 48, weight: .bold)
        label.textAlignment = .center
        return label
    }()
    
    /// Gradient background for grid view
    internal let gradientView: UIView = {
        let view = UIView()
        view.backgroundColor = .black
        return view
    }()
    
    /// Grid view that displays thumbnails with rounded corners
    internal lazy var gridView: UICollectionView = {
        // Create a custom flow layout that enforces 16:9 aspect ratio
        class AdaptiveFlowLayout: UICollectionViewFlowLayout {
            override func prepare() {
                super.prepare()
                
                guard let collectionView = collectionView else { return }
                
                // Fixed values for layout
                let itemsPerRow: CGFloat = 3
                let minimumSpacing: CGFloat = 80
                let sideInset: CGFloat = 120
                
                // Available width calculation
                let availableWidth = collectionView.bounds.width - (sideInset * 2) - (minimumSpacing * (itemsPerRow - 1))
                let itemWidth = floor(availableWidth / itemsPerRow)
                
                // Calculate height based on 16:9 aspect ratio
                let itemHeight = itemWidth * (9.0/16.0)
                
                // Set layout properties
                itemSize = CGSize(width: itemWidth, height: itemHeight)
                minimumLineSpacing = 80
                minimumInteritemSpacing = minimumSpacing
                sectionInset = UIEdgeInsets(top: 80, left: sideInset, bottom: 50, right: sideInset)
                
                // Ensure left-to-right ordering
                scrollDirection = .vertical
            }
            
            override func layoutAttributesForElements(in rect: CGRect) -> [UICollectionViewLayoutAttributes]? {
                let attributes = super.layoutAttributesForElements(in: rect)
                return attributes?.sorted { $0.indexPath.item < $1.indexPath.item }
            }
        }
        
        // Create collection view with custom layout
        let layout = AdaptiveFlowLayout()
        let collectionView = UICollectionView(frame: .zero, collectionViewLayout: layout)
        collectionView.backgroundColor = .clear
        collectionView.delegate = self
        collectionView.dataSource = self
        collectionView.register(ImageThumbnailCell.self, forCellWithReuseIdentifier: "ThumbnailCell")
        collectionView.remembersLastFocusedIndexPath = true
        
        // Add title label as header
        let headerView = UIView(frame: CGRect(x: 0, y: 0, width: collectionView.bounds.width, height: 150))
        headerView.backgroundColor = .clear
        
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        headerView.addSubview(titleLabel)
        
        NSLayoutConstraint.activate([
            titleLabel.centerXAnchor.constraint(equalTo: headerView.centerXAnchor),
            titleLabel.centerYAnchor.constraint(equalTo: headerView.centerYAnchor)
        ])
        
        collectionView.register(UICollectionReusableView.self, forSupplementaryViewOfKind: UICollectionView.elementKindSectionHeader, withReuseIdentifier: "HeaderView")
        
        return collectionView
    }()
    
    internal let focusGuide = UIFocusGuide()
    
    internal let activityIndicator: UIActivityIndicatorView = {
        let indicator = UIActivityIndicatorView(style: .large)
        indicator.color = .white
        indicator.hidesWhenStopped = true
        indicator.isHidden = true  // Hide by default
        return indicator
    }()
    
    internal let instructionLabel: UILabel = {
        let label = UILabel()
        label.text = "Press Menu button to access sample images"
        label.textColor = .lightGray
        label.textAlignment = .center
        label.font = UIFont.preferredFont(forTextStyle: .headline)
        label.isHidden = true
        return label
    }()
    
    internal let toastView: ToastView = {
        let view = ToastView()
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()
    
    // MARK: - Properties
    
    // Add view model property
    internal let viewModel = MediaLibraryViewModel()
    private var cancellables = Set<AnyCancellable>()
    
    // ADD to the top of the class (after existing properties):
    internal let dataSource = MediaDataSource.shared

    internal var isInGridMode = true // Start in grid mode
    internal let sampleImageNames = ["sample1", "sample2", "sample3"]
    internal let logger = Logger(subsystem: "com.eclipsetv.app", category: "ImageViewController")
    
    // REMOVE these old properties - now handled by MediaDataSource:
    // internal var recentImages: [String] = []
    // internal var currentImageIndex = 0
    // internal var previouslySelectedIndex = 0
    // internal let recentImagesKey = "EclipseTV.recentImagesKey"
    
    internal var isVideo = false
    
    /// Dictionary to store user-defined positions for each image path
    internal var imagePositions: [String: CGPoint] = [:] {
        didSet {
            saveImagePositions()
        }
    }
    
    /// UserDefaults key for storing image positions
    private let imagePositionsKey = "EclipseTV.imagePositions"
    
    /// Pan gesture recognizer for image positioning
    internal var imagePanGesture: UIPanGestureRecognizer?
    internal var isVideoScrubbing = false
    internal var playerLooper: AVPlayerLooper?
    
    // Video player controls auto-hide timer
    internal var playerControlsAutoHideTimer: Timer?
    
    // Video playback settings
    internal var videoSettings: [String: [String: Bool]] = [:] // [videoPath: [setting: value]]
    internal let videoSettingsKey = "EclipseTV.videoSettingsKey"
    
    // Track move state
    internal var isMoveMode = false
    internal var movingItemIndex: Int?
    internal var movingItemIndexPath: IndexPath?
    internal var movingItemCell: UICollectionViewCell?
    
    // Flag to temporarily ignore selection events after ending move mode
    internal var isIgnoringSelectionEvents = false
    
    // Add this property:
    internal var simpleSelectionManager: SimpleSelectionManager!
    
    // Debouncing for focus changes to prevent rapid navigation issues
    private var focusDebounceTimer: Timer?
    
    // MARK: - Storage
    internal let imageStorage = ImageStorage.shared
    
    // MARK: - Help View
    internal lazy var helpView = HelpView()
    
    // MARK: - Empty State View
    internal lazy var emptyStateView = EmptyStateView()
    
    // Add these properties near the top of the class where other properties are defined
    private var queuedContent = [(path: String, isVideo: Bool)]()
    private var isProcessingQueue = false
    
    // First launch detection
    private let hasLaunchedBeforeKey = "EclipseTV.hasLaunchedBefore"
    
    // MARK: - Lifecycle Methods
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        // Try to initialize audio session early to avoid first-time sounds
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback)
        } catch {
            logger.debug("Could not set audio session category: \(error)")
        }
        
        // Set up data source delegate
        dataSource.delegate = self
        
        // Basic setup
        view.backgroundColor = .black
        ErrorHandler.shared.setPresentingViewController(self)
        PerformanceMonitor.shared.startFrameRateMonitoring()
        
        // Add memory pressure observer
        addManagedObserver(for: Notification.Name("MemoryPressureDetected")) { notification in
            if let memInfo = notification.object as? PerformanceMonitor.MemoryInfo {
                self.handleMemoryPressure(memInfo)
            }
        }
        
        // Log performance state every 60 seconds in debug builds
        #if DEBUG
        createManagedTimer(interval: 60.0, repeats: true) {
            PerformanceMonitor.shared.logPerformanceState()
        }
        #endif
        
        // Setup UI and services
        setupUI()
        setupGradientBackground()
        setupGestures()
        setupFocusGuide()
        setupViewModel()
        
        // Load stored image positions
        loadImagePositions()
        
        // Initialize selection manager
        simpleSelectionManager = SimpleSelectionManager(collectionView: gridView)
        
        // Note: Player view setup is deferred until actually needed for video playback
        // This prevents unnecessary constraint conflicts during app launch
    }
    
    // Add this new method:
    private func setupViewModel() {
        // Bind to view model changes
        viewModel.$isLoading
            .receive(on: DispatchQueue.main)
            .sink { [weak self] isLoading in
                if isLoading {
                    self?.activityIndicator.startAnimating()
                } else {
                    self?.activityIndicator.stopAnimating()
                }
            }
            .store(in: &cancellables)
        
        // Start in grid mode and hide all views initially while loading
        logger.info("Setting up initial state - starting in grid mode")
        isInGridMode = true
        gridView.isHidden = true  // Hide until sample media loads
        gradientView.isHidden = true  // Hide background until ready
        imageView.isHidden = true
        playerView.view.isHidden = true
        
        // Always load sample media first
        logger.info("Loading sample media automatically on every launch")
        Task {
            logger.info("🚀 [SETUP] About to call viewModel.loadSampleMedia()")
            await viewModel.loadSampleMedia()
            await MainActor.run {
                logger.info("✅ [SETUP] Sample media loading completed. Data source count: \(self.dataSource.count)")
                
                // Debug data source state
                self.dataSource.debugPrint()
                
                // Fallback: if no media found by service, try scanning bundle subfolders explicitly
                if self.dataSource.isEmpty {
                    self.logger.info("❔ [SETUP] No media after service load — scanning bundle 'Videos' and 'Images' folders as fallback")
                    let before = self.dataSource.count
                    self.loadVideosFromBundle()
                    self.logger.info("📦 [SETUP] After videos scan: count=\(self.dataSource.count) (Δ=\(self.dataSource.count - before))")
                    self.loadImagesFromBundle()
                    self.logger.info("📦 [SETUP] After images scan: count=\(self.dataSource.count)")
                    if self.dataSource.isEmpty {
                        self.logger.error("🚫 [SETUP] Still empty after fallback scans. Showing empty state.")
                    }
                }

                // Always go directly to grid view with sample media
                logger.info("🎯 [SETUP] Going directly to grid view with sample media")
                self.isInGridMode = true
                
                // If we have media, show grid view directly
                if !self.dataSource.isEmpty {
                    logger.info("✅ [SETUP] Data source has \(self.dataSource.count) items - showing grid view")
                    self.gridView.isHidden = false
                    self.titleLabel.isHidden = false
                    self.gradientView.isHidden = false
                    
                    // Start preloading videos for smooth transitions
                    logger.info("🚀 [CACHE] Starting initial video preloading")
                    VideoCacheManager.shared.preloadInitialVideos(from: self.dataSource)
                    
                    // Reload and select first item
                    self.gridView.reloadData()
                    if let firstIndexPath = IndexPath(item: 0, section: 0) as IndexPath?, self.dataSource.count > 0 {
                        self.simpleSelectionManager.selectItem(at: firstIndexPath)
                        self.dataSource.setCurrentIndex(0)
                        
                        // Update focus to the grid view
                        self.setNeedsFocusUpdate()
                        self.updateFocusIfNeeded()
                    }
                } else {
                    // If no media loaded, show empty state
                    logger.info("❌ [SETUP] Data source is empty - showing empty state")
                    self.showEmptyState()
                }
            }
        }
    }
    
    private var isPlayerViewSetup = false
    
    internal func setupPlayerView() {
        // Avoid setting up the player view multiple times
        guard !isPlayerViewSetup else { return }
        
        logger.info("Setting up player view for video playback")
        
        // Configure player view before adding to view hierarchy
        playerView.view.translatesAutoresizingMaskIntoConstraints = false
        playerView.view.backgroundColor = .black
        playerView.showsPlaybackControls = false
        playerView.videoGravity = .resizeAspect
        
        // Add player view as child view controller
        addChild(playerView)
        view.addSubview(playerView.view)
        
        // Setup player view constraints with lower priorities to avoid conflicts
        let topConstraint = playerView.view.topAnchor.constraint(equalTo: view.topAnchor)
        topConstraint.priority = UILayoutPriority(999)
        
        let leadingConstraint = playerView.view.leadingAnchor.constraint(equalTo: view.leadingAnchor)
        leadingConstraint.priority = UILayoutPriority(999)
        
        let trailingConstraint = playerView.view.trailingAnchor.constraint(equalTo: view.trailingAnchor)
        trailingConstraint.priority = UILayoutPriority(999)
        
        let bottomConstraint = playerView.view.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        bottomConstraint.priority = UILayoutPriority(999)
        
        NSLayoutConstraint.activate([
            topConstraint,
            leadingConstraint,
            trailingConstraint,
            bottomConstraint
        ])
        
        // Complete the child view controller setup
        playerView.didMove(toParent: self)
        
        // Setup gestures for player view
        setupPlayerViewGestures()
        
        // Mark as setup
        isPlayerViewSetup = true
        
        // Add a small delay before allowing controls to prevent immediate constraint conflicts
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            self?.logger.debug("Player view setup completed, controls ready")
        }
    }
    
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        
        // Update activity indicator and instruction label positions
        activityIndicator.center = view.center
        instructionLabel.center = view.center
        
        // Update gradient layer frame whenever view layout changes
        if let gradientLayer = gradientView.layer.sublayers?.first as? CAGradientLayer {
            gradientLayer.frame = gradientView.bounds
        }
        
        // Note: Player view focus constraints are now set up only when the player view is actually needed
    }
    
    private var hasConfiguredPlayerConstraints = false
    private func setupPlayerViewFocusConstraintsIfNeeded() {}
    private func configurePlayerViewFocusConstraints() {}
    
    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        
        // Clean up focus debounce timer
        focusDebounceTimer?.invalidate()
        focusDebounceTimer = nil
        
        // If this is the main ImageViewController and it's disappearing,
        // we probably don't want to process the queue yet
    }
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        
        // If a presented view controller was just dismissed, process any queued content
        if !isMoveMode && presentedViewController == nil {
            // We use a short delay to ensure the UI is fully back before processing
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
                self?.processQueuedContent()
            }
        }
    }
    
    // MARK: - UI Setup
    
    internal func setupUI() {
        // Add views in proper z-index order
        view.addSubview(gradientView)
        view.addSubview(imageView)
        view.addSubview(gridView)
        view.addSubview(activityIndicator)
        view.addSubview(instructionLabel)
        view.addSubview(helpView)
        view.addSubview(toastView)
        
        // Configure helpers
        helpView.delegate = self
        helpView.isHidden = true
        emptyStateView.delegate = self
        instructionLabel.isHidden = true
        
        // Setup constraints
        imageView.translatesAutoresizingMaskIntoConstraints = false
        gradientView.translatesAutoresizingMaskIntoConstraints = false
        gridView.translatesAutoresizingMaskIntoConstraints = false
        helpView.translatesAutoresizingMaskIntoConstraints = false
        
        NSLayoutConstraint.activate([
            // Image view constraints
            imageView.topAnchor.constraint(equalTo: view.topAnchor),
            imageView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            imageView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            imageView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            
            // Gradient view constraints
            gradientView.topAnchor.constraint(equalTo: view.topAnchor),
            gradientView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            gradientView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            gradientView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            
            // Grid view constraints
            gridView.topAnchor.constraint(equalTo: view.topAnchor),
            gridView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            gridView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            gridView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            
            // Help view constraints
            helpView.topAnchor.constraint(equalTo: view.topAnchor),
            helpView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            helpView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            helpView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            
            // Toast view constraints
            toastView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 20),
            toastView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -40),
            toastView.widthAnchor.constraint(lessThanOrEqualTo: view.widthAnchor, multiplier: 0.4)
        ])
    }
    
    internal func setupGradientBackground() {
        // Create a new gradient layer
        let gradientLayer = CAGradientLayer()
        gradientLayer.colors = [
            UIColor.black.cgColor,
            UIColor(white: 0.1, alpha: 1.0).cgColor
        ]
        gradientLayer.locations = [0.0, 1.0]
        gradientLayer.startPoint = CGPoint(x: 0.5, y: 0.0)
        gradientLayer.endPoint = CGPoint(x: 0.5, y: 1.0)
        gradientLayer.frame = gradientView.bounds
        
        // Remove any existing layers
        gradientView.layer.sublayers?.forEach { $0.removeFromSuperlayer() }
        
        // Add the new gradient layer
        gradientView.layer.insertSublayer(gradientLayer, at: 0)
    }
    
    internal func setupFocusGuide() {
        view.addLayoutGuide(focusGuide)
        
        NSLayoutConstraint.activate([
            focusGuide.topAnchor.constraint(equalTo: view.topAnchor),
            focusGuide.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            focusGuide.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            focusGuide.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
    }
    
    override func viewWillLayoutSubviews() {
        super.viewWillLayoutSubviews()
        // Ensure gradient is updated whenever view size changes
        setupGradientBackground()
    }
    
    // MARK: - Focus Handling
    
    func indexPathForPreferredFocusedView(in collectionView: UICollectionView) -> IndexPath? {
        // Simple: focus on current index if valid, otherwise first item
        if dataSource.currentIndex < dataSource.count {
            return IndexPath(item: dataSource.currentIndex, section: 0)
        } else if !dataSource.isEmpty {
            return IndexPath(item: 0, section: 0)
        }
        return nil
    }
    
    override var preferredFocusEnvironments: [UIFocusEnvironment] {
        if isInGridMode && !dataSource.isEmpty {
            // If we have a selected cell, prefer to focus on it
            if let selectedIndexPath = simpleSelectionManager.currentSelection,
               let selectedCell = gridView.cellForItem(at: selectedIndexPath) {
                return [selectedCell]
            }
            return [gridView]
        } else if !isInGridMode {
            return [imageView]
        }
        return super.preferredFocusEnvironments
    }
    
    override func didUpdateFocus(in context: UIFocusUpdateContext, with coordinator: UIFocusAnimationCoordinator) {
        super.didUpdateFocus(in: context, with: coordinator)
        
        // Debug logging for sound investigation
        logger.debug("🔊 [FOCUS] Focus change detected - from: \(String(describing: context.previouslyFocusedItem)) to: \(String(describing: context.nextFocusedItem))")
        
        // Only handle grid focus changes
        guard isInGridMode,
              gridView.alpha == 1,  // Don't interfere during transitions
              let nextCell = context.nextFocusedItem as? UICollectionViewCell,
              let nextIndexPath = gridView.indexPath(for: nextCell) else {
            return
        }
        
        // CRITICAL FIX FOR MOVE MODE: Handle selection differently in move mode
        if isMoveMode {
            logger.debug("🔊 [FOCUS] In move mode - handling focus change specially")
            
            // Get the previously focused cell's index path
            if let previousCell = context.previouslyFocusedItem as? UICollectionViewCell,
               let previousIndexPath = gridView.indexPath(for: previousCell) {
                
                // If the previously focused cell was our moving item, update its position
                if previousIndexPath == movingItemIndexPath {
                    // Update the moving item's index path to the new position
                    movingItemIndexPath = nextIndexPath
                    movingItemIndex = nextIndexPath.item
                    
                    // Clear selection from the old cell
                    if let oldCell = previousCell as? ImageThumbnailCell {
                        oldCell.isSelected = false
                        oldCell.updateVisualEffects()
                    }
                    
                    // Apply selection to the new cell
                    if let newCell = nextCell as? ImageThumbnailCell {
                        newCell.isSelected = true
                        newCell.updateVisualEffects()
                    }
                    
                    logger.debug("🔊 [FOCUS] Updated moving item position to index: \(nextIndexPath.item)")
                }
            }
            
            // Don't update SimpleSelectionManager in move mode
            return
        }
        
        // NORMAL MODE: Handle selection normally when not in move mode
        
        // CRITICAL: If we already have a selection that matches the focused item, don't change it
        // This prevents interference during grid view transitions
        if let currentSelection = simpleSelectionManager.currentSelection,
           currentSelection == nextIndexPath {
            logger.debug("🔊 [FOCUS] Focus matches current selection (\(nextIndexPath.item)) - no action needed")
            return
        }
        
        logger.debug("🔊 [FOCUS] Grid focus change to index: \(nextIndexPath.item)")
        
        // Cancel any pending focus debounce timer
        focusDebounceTimer?.invalidate()
        
        // CRITICAL: Clear the previous selection immediately to prevent dual blue strokes
        // This ensures only one blue outline is visible at any time
        if let currentSelection = simpleSelectionManager.currentSelection,
           currentSelection != nextIndexPath {
            // Immediately clear the previous selection's visual state
            if let previousCell = gridView.cellForItem(at: currentSelection) as? ImageThumbnailCell {
                previousCell.isSelected = false
                gridView.deselectItem(at: currentSelection, animated: false)
            }
        }
        
        // CRITICAL: Let the selection manager handle ALL selection logic
        // Do NOT manually manipulate cell selection states here to prevent race conditions
        focusDebounceTimer = Timer.scheduledTimer(withTimeInterval: 0.03, repeats: false) { [weak self] _ in
            guard let self = self else { return }
            
            // The selection manager will properly clear previous selections and set new ones
            self.simpleSelectionManager.selectItem(at: nextIndexPath)
            
            // Preload the currently focused item for smooth transitions
            self.preloadFocusedItem(at: nextIndexPath.item)
        }
    }
    
    override func shouldUpdateFocus(in context: UIFocusUpdateContext) -> Bool {
        logger.debug("🎯 [FOCUS] shouldUpdateFocus called")
        logger.debug("🎯 [FOCUS] Current state - currentIndex: \(self.dataSource.currentIndex)")
        return super.shouldUpdateFocus(in: context)
    }
    
    // MARK: - Preloading
    
    private func preloadFocusedItem(at index: Int) {
        guard let path = dataSource.getPath(at: index) else { return }
        
        let mediaItem = MediaItem(path: path)
        
        // Preload images in background for smooth transitions
        Task {
            if mediaItem.isVideo {
                // For videos, ensure thumbnail is cached
                let cellSize = CGSize(width: 400, height: 225) // Reasonable size for caching
                _ = await viewModel.getThumbnail(for: mediaItem, size: cellSize)
            } else {
                // For images, preload the full-size image
                _ = await AsyncImageLoader.shared.loadImage(from: mediaItem.path, targetSize: self.view.bounds.size)
            }
        }
    }
    
    // MARK: - ConnectionManagerDelegate Implementation
    
    func connectionManager(_ manager: ConnectionManager, didReceiveImageAt path: String) {
        let startTime = Date()
        
        // Check if we're in move mode or showing a menu - if so, queue the content
        if isMoveMode || presentedViewController != nil {
            logger.info("Queuing received image as app is in move mode or settings: \(path)")
            queuedContent.append((path: path, isVideo: false))
            
            // Show a subtle notification that content was received but queued
            showNotificationToast(message: "New image received (will be added when ready)")
            return
        }
        
        // Add the newly received image using data source
        dataSource.addMedia(at: path)
        
        let endTime = Date()
        let duration = endTime.timeIntervalSince(startTime)
        logger.info("Added new image via data source in \(String(format: "%.3f", duration))s")
    }
    
    func connectionManager(_ manager: ConnectionManager, didUpdateConnectionState connected: Bool, with peer: MCPeerID?) {
        if connected, let peer = peer {
            // Show a notification that a device connected
            toastView.show(message: "Connected to \(peer.displayName)")
        }
    }
    
    func connectionManager(_ manager: ConnectionManager, didReceiveVideoAt path: String) {
        let startTime = Date()
        self.logger.info("Received video at path: \(path)")
        
        // Verify file exists and is readable
        let fileManager = FileManager.default
        if fileManager.fileExists(atPath: path) {
            do {
                let attributes = try fileManager.attributesOfItem(atPath: path)
                let fileSize = attributes[.size] as? UInt64 ?? 0
                self.logger.info("Video file exists, size: \(ByteCountFormatter.string(fromByteCount: Int64(fileSize), countStyle: .file))")
            } catch {
                self.logger.error("Failed to get video file attributes: \(error)")
            }
        } else {
            self.logger.error("Video file does not exist at path: \(path)")
        }
        
        // Check if we're in move mode or showing a menu - if so, queue the content
        if isMoveMode || presentedViewController != nil {
            logger.info("Queuing received video as app is in move mode or settings: \(path)")
            queuedContent.append((path: path, isVideo: true))
            
            // Show a subtle notification that content was received but queued
            showNotificationToast(message: "New video received (will be added when ready)")
            return
        }
        
        // Add the newly received video using data source
        dataSource.addMedia(at: path)
        
        let endTime = Date()
        let duration = endTime.timeIntervalSince(startTime)
        self.logger.info("Added new video via data source in \(String(format: "%.3f", duration))s")
    }
    
    /// Loads video files from the Videos folder in the app bundle
    func loadVideosFromBundle() {
        guard let videosURL = Bundle.main.resourceURL?.appendingPathComponent("Videos") else { return }
        let fileManager = FileManager.default
        
        // Load videos from main Videos folder
        print("[DEBUG] Looking for videos in: \(videosURL.path)")
        if let files = try? fileManager.contentsOfDirectory(at: videosURL, includingPropertiesForKeys: nil) {
            for file in files {
                let ext = file.pathExtension.lowercased()
                print("[DEBUG] Found file in Videos: \(file.lastPathComponent)")
                if ext == "mp4" || ext == "mov" {
                    let path = file.path
                    print("[DEBUG] Adding video to dataSource: \(path)")
                    dataSource.addMedia(at: path)
                }
            }
        } else {
            print("[DEBUG] No files found in Videos folder")
        }
        
        // Also load videos from Videos/Loop subfolder
        let loopURL = videosURL.appendingPathComponent("Loop")
        print("[DEBUG] Looking for videos in Loop folder: \(loopURL.path)")
        if let loopFiles = try? fileManager.contentsOfDirectory(at: loopURL, includingPropertiesForKeys: nil) {
            for file in loopFiles {
                let ext = file.pathExtension.lowercased()
                print("[DEBUG] Found file in Videos/Loop: \(file.lastPathComponent)")
                if ext == "mp4" || ext == "mov" {
                    let path = file.path
                    print("[DEBUG] Adding loop video to dataSource: \(path)")
                    dataSource.addMedia(at: path)
                }
            }
        } else {
            print("[DEBUG] No files found in Videos/Loop folder")
        }
    }

    /// Loads image files from the Images folder in the app bundle
    func loadImagesFromBundle() {
        guard let imagesURL = Bundle.main.resourceURL?.appendingPathComponent("Images") else { return }
        let fileManager = FileManager.default
        print("[DEBUG] Looking for images in: \(imagesURL.path)")
        if let files = try? fileManager.contentsOfDirectory(at: imagesURL, includingPropertiesForKeys: nil) {
            for file in files {
                let ext = file.pathExtension.lowercased()
                print("[DEBUG] Found file in Images: \(file.lastPathComponent)")
                if ext == "jpg" || ext == "jpeg" || ext == "png" {
                    let path = file.path
                    print("[DEBUG] Adding image to dataSource: \(path)")
                    dataSource.addMedia(at: path)
                }
            }
        } else {
            print("[DEBUG] No files found in Images folder")
        }
    }

    /// Updates the grid view when a new item is added
    /// - Parameters:
    ///   - newIndex: The index of the newly added item
    ///   - isFullscreen: Whether the view is currently in fullscreen mode
    private func updateGridViewForNewItem(at newIndex: Int, isFullscreen: Bool) {
        if isFullscreen {
            // Just update in background
            gridView.performBatchUpdates({
                gridView.insertItems(at: [IndexPath(item: newIndex, section: 0)])
            })
        } else {
            // Update and select new item
            dataSource.setCurrentIndex(newIndex)
            
            gridView.performBatchUpdates({
                gridView.insertItems(at: [IndexPath(item: newIndex, section: 0)])
            }) { _ in
                let targetIndexPath = IndexPath(item: newIndex, section: 0)
                self.simpleSelectionManager.selectItem(at: targetIndexPath)
                self.setNeedsFocusUpdate()
                self.updateFocusIfNeeded()
            }
        }
    }
    
    /// Returns to grid view while maintaining selection state
    internal func returnToGridView() {
        logger.info("🔄 [FULLSCREEN→GRID] Returning to grid view with smooth transition")
        
        // Use the smooth showGridView method for consistent animation
        showGridView()
    }

    // Note: displayImageAtCurrentIndex() is implemented in ImageViewController+ImageManagement.swift

    // Process any content that was queued while in move mode or settings
    func processQueuedContent() {
        // Check if we're already processing the queue or if there's nothing to process
        guard !self.isProcessingQueue, !self.queuedContent.isEmpty else {
            return
        }
        
        // Don't process if we're still in move mode or have a presented view controller
        if self.isMoveMode || self.presentedViewController != nil {
            self.logger.info("Skipping queue processing as app is still in move mode or settings")
            return
        }
        
        self.logger.info("Processing queued content - \(self.queuedContent.count) items")
        self.isProcessingQueue = true
        
        // Process all queued items
        var addedCount = 0
        var lastAddedIndex = -1
        
        for queuedItem in self.queuedContent {
            // Add the item via data source
            self.dataSource.addMedia(at: queuedItem.path)
            lastAddedIndex = self.dataSource.count - 1
            addedCount += 1
        }
        
        // Clear the queue
        self.queuedContent.removeAll()
        
        // Only update UI if we added items
        if addedCount > 0 {
            // If we were showing the empty state, hide it and switch to grid view
            if view.subviews.contains(emptyStateView) {
                hideEmptyState()
            }
            
            // Reload the grid with all the new content (delegate will handle this)
            // But force it just in case
            self.gridView.reloadData()
            
            // Select the last added item using SimpleSelectionManager
            if lastAddedIndex >= 0 {
                let indexPath = IndexPath(item: lastAddedIndex, section: 0)
                
                // Use async dispatch to ensure reload is complete before selection
                DispatchQueue.main.async {
                    self.simpleSelectionManager.selectItem(at: indexPath)
                    self.dataSource.setCurrentIndex(lastAddedIndex)
                    
                    // Ensure visibility
                    if !self.gridView.indexPathsForVisibleItems.contains(indexPath) {
                        self.gridView.scrollToItem(at: indexPath, at: .centeredVertically, animated: true)
                    }
                    
                    // Validate selection state after all operations
                    self.simpleSelectionManager.validateSelectionState()
                    
                    // Ensure focus is updated
                    self.setNeedsFocusUpdate()
                    self.updateFocusIfNeeded()
                }
            }
            
            // Show a notification with the count of added items
            let itemText = addedCount == 1 ? "item" : "items"
            self.showNotificationToast(message: "\(addedCount) new \(itemText) added")
        }
        
        self.isProcessingQueue = false
    }
    
    // MARK: - Performance & Memory Management
    
    private func handleMemoryPressure(_ memInfo: PerformanceMonitor.MemoryInfo) {
        logger.warning("Memory pressure detected: \(String(format: "%.1f", memInfo.usagePercentage))% used")
        
        // Clear caches to free memory
        Task { await AsyncImageLoader.shared.clearCache() }
        VideoThumbnailCache.shared.clearCache()
        
        // Force garbage collection
        if memInfo.usagePercentage > 90 {
            // In critical memory situations, reload the grid to release cell memory
            DispatchQueue.main.async {
                self.gridView.reloadData()
            }
        }
    }
    
    // MARK: - EmptyStateViewDelegate Implementation
    
    func emptyStateViewDidTapOpenApp(_ view: EmptyStateView) {
        logger.info("User tapped 'Open App' button - data source count: \(self.dataSource.count)")
        
        // Force hide empty state and show grid view regardless of data source state
        self.hideEmptyState()
        
        // Show notification to user
        self.showNotificationToast(message: "Transitioning to grid view")
        
        // Ensure we're in grid mode
        self.isInGridMode = true
        
        // Debug the data source
        self.dataSource.debugPrint()
    }
}

// MARK: - HelpViewDelegate Implementation
extension ImageViewController: HelpViewDelegate {
    func didTapCloseButton() {
        UIView.animate(withDuration: 0.3, animations: {
            self.helpView.alpha = 0
        }) { _ in
            self.helpView.isHidden = true
        }
    }
}

// MARK: - UICollectionViewLayout
extension ImageViewController: UICollectionViewDelegateFlowLayout {
    func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, referenceSizeForHeaderInSection section: Int) -> CGSize {
        return CGSize(width: collectionView.bounds.width, height: 120)
    }
    
    func collectionView(_ collectionView: UICollectionView, viewForSupplementaryElementOfKind kind: String, at indexPath: IndexPath) -> UICollectionReusableView {
        if kind == UICollectionView.elementKindSectionHeader {
            let headerView = collectionView.dequeueReusableSupplementaryView(ofKind: kind, withReuseIdentifier: "HeaderView", for: indexPath)
            
            // Remove any existing title label
            headerView.subviews.forEach { $0.removeFromSuperview() }
            
            // Add title label to header
            titleLabel.translatesAutoresizingMaskIntoConstraints = false
            headerView.addSubview(titleLabel)
            
            NSLayoutConstraint.activate([
                titleLabel.centerXAnchor.constraint(equalTo: headerView.centerXAnchor),
                titleLabel.topAnchor.constraint(equalTo: headerView.topAnchor, constant: 20)
            ])
            
            return headerView
        }
        return UICollectionReusableView()
    }
}

// MARK: - Video Settings

extension ImageViewController {
    func loadVideoSettings() {
        if let savedSettings = UserDefaults.standard.dictionary(forKey: videoSettingsKey) as? [String: [String: Bool]] {
            videoSettings = savedSettings
        }
    }
    
    func saveVideoSettings() {
        UserDefaults.standard.set(videoSettings, forKey: videoSettingsKey)
    }
    
    func getVideoSetting(for videoPath: String, setting: String) -> Bool {
        // Default settings: Audio On (not muted), Loop Off (except videos in Loop folder)
        let defaultValue: Bool
        
        if setting == "mute" {
            defaultValue = false  // Audio on by default (not muted)
        } else if setting == "loop" {
            // Special case: videos in Loop folder should loop by default
            if videoPath.contains("/Loop/") {
                defaultValue = true  // Loop videos in Loop folder by default
            } else {
                defaultValue = false  // Other videos don't loop by default
            }
        } else {
            defaultValue = false  // Default fallback
        }
        
        if let videoConfig = videoSettings[videoPath], let value = videoConfig[setting] {
            return value
        }
        
        // Initialize with default settings if not found
        if videoSettings[videoPath] == nil {
            videoSettings[videoPath] = [:]
        }
        videoSettings[videoPath]?[setting] = defaultValue
        saveVideoSettings()
        
        return defaultValue
    }
    
    func setVideoSetting(for videoPath: String, setting: String, value: Bool) {
        if videoSettings[videoPath] == nil {
            videoSettings[videoPath] = [:]
        }
        videoSettings[videoPath]?[setting] = value
        saveVideoSettings()
    }
    
    func applyVideoSettings(for videoPath: String, to player: AVPlayer?) {
        guard let player = player else { return }
        
        // Apply mute setting
        let isMuted = getVideoSetting(for: videoPath, setting: "mute")
        player.isMuted = isMuted
        
        // Note: Loop setting is applied when video playback ends
    }
    
    /// Clean up player looper resources
    func cleanupPlayerLooper() {
        #if DEBUG
        if let player = playerView.player {
            cleanupLooperDebugging(for: player)
        }
        #endif
        playerLooper = nil
    }
    
    /// Apply settings to currently playing video (if any)
    func applySettingsToCurrentVideo() {
        guard isVideo, let player = playerView.player else { return }
        guard let currentPath = dataSource.getCurrentPath() else { return }
        
        // Get settings from the new system (viewModel)
        let mediaItem = MediaItem(path: currentPath)
        let settings = viewModel.getVideoSettings(for: mediaItem)
        
        // Apply mute setting immediately
        player.isMuted = settings.isMuted
        
        // Note: Loop setting will be applied when video ends
        logger.info("Applied settings to current video: muted=\(settings.isMuted), loop=\(settings.isLooping)")
    }
    
    #if DEBUG
    /// Handle KVO observations for debug monitoring
    override func observeValue(forKeyPath keyPath: String?, of object: Any?, change: [NSKeyValueChangeKey : Any]?, context: UnsafeMutableRawPointer?) {
        guard let keyPath = keyPath else { return }
        
        switch keyPath {
        case "status":
            if let looper = object as? AVPlayerLooper {
                let status = looper.status
                logger.debug("🔍 [DEBUG] AVPlayerLooper status changed to: \(status.rawValue)")
                if status == .failed, let error = looper.error {
                    logger.error("🔍 [DEBUG] AVPlayerLooper failed with error: \(error)")
                }
            } else if let item = object as? AVPlayerItem {
                let status = item.status
                logger.debug("🔍 [DEBUG] AVPlayerItem status changed to: \(status.rawValue)")
                if status == .failed, let error = item.error {
                    logger.error("🔍 [DEBUG] AVPlayerItem failed with error: \(error)")
                }
            }
            
        case "loadedTimeRanges":
            if let item = object as? AVPlayerItem {
                let ranges = item.loadedTimeRanges
                if let lastRange = ranges.last {
                    let timeRange = lastRange.timeRangeValue
                    let duration = CMTimeGetSeconds(timeRange.duration)
                    logger.debug("🔍 [DEBUG] Buffer loaded: \(String(format: "%.2f", duration))s")
                }
            }
            
        case "playbackBufferEmpty":
            if let item = object as? AVPlayerItem {
                logger.debug("🔍 [DEBUG] Playback buffer empty: \(item.isPlaybackBufferEmpty)")
            }
            
        case "playbackLikelyToKeepUp":
            if let item = object as? AVPlayerItem {
                logger.debug("🔍 [DEBUG] Playback likely to keep up: \(item.isPlaybackLikelyToKeepUp)")
            }
            
        case "currentItem":
            if object is AVQueuePlayer {
                if change?[.newKey] is AVPlayerItem {
                    logger.debug("🔍 [DEBUG] Queue player current item changed to new item")
                } else {
                    logger.debug("🔍 [DEBUG] Queue player current item changed to nil")
                }
            }
            
        default:
            super.observeValue(forKeyPath: keyPath, of: object, change: change, context: context)
        }
    }
    #endif
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
            }
            
            // TEMPORARILY DISABLED: Let setupViewModel handle empty state logic instead
            // Update empty state
            // if self.dataSource.isEmpty {
            //     self.showEmptyState()
            // } else {
            //     self.hideEmptyState()
            // }
            
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
            // Animate removal
            let indexPath = IndexPath(item: index, section: 0)
            self.gridView.performBatchUpdates({
                self.gridView.deleteItems(at: [indexPath])
            }) { _ in
                // Select the item that moves into the deleted item's position
                if !dataSource.isEmpty {
                    let newSelectedIndex: Int
                    
                    if index >= dataSource.count {
                        // Deleted the last item, select the new last item
                        newSelectedIndex = dataSource.count - 1
                    } else {
                        // Item shifts into the deleted position, keep same index
                        newSelectedIndex = index
                    }
                    
                    // Update data source current index to match UI selection
                    dataSource.setCurrentIndex(newSelectedIndex)
                    
                    let newIndexPath = IndexPath(item: newSelectedIndex, section: 0)
                    self.simpleSelectionManager.selectItem(at: newIndexPath)
                    self.setNeedsFocusUpdate()
                    self.updateFocusIfNeeded()
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
    
    // MARK: - Image Position Persistence
    
    /// Saves image positions to UserDefaults
    private func saveImagePositions() {
        let encodedPositions = imagePositions.compactMapValues { position in
            return [position.x, position.y]
        }
        UserDefaults.standard.set(encodedPositions, forKey: imagePositionsKey)
    }
    
    /// Loads image positions from UserDefaults
    private func loadImagePositions() {
        guard let savedPositions = UserDefaults.standard.object(forKey: imagePositionsKey) as? [String: [Double]] else {
            return
        }
        
        var loadedPositions: [String: CGPoint] = [:]
        for (path, coordinates) in savedPositions {
            if coordinates.count == 2 {
                loadedPositions[path] = CGPoint(x: coordinates[0], y: coordinates[1])
            }
        }
        
        // Set directly to avoid triggering didSet save
        self.imagePositions = loadedPositions
    }
}

