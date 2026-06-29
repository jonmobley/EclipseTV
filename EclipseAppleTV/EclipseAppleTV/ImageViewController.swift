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
        // Let AVPlayerViewController own its transport controls: it shows them on
        // interaction and auto-hides them after inactivity, the standard tvOS behavior.
        view.showsPlaybackControls = true
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

    /// Top-right "Options" button shown on the grid. Selecting it opens a native tvOS
    /// dropdown menu (account code, refresh, help, …). Hidden during fullscreen playback.
    /// The menu itself is built lazily in `setupOptionsButton()`.
    internal lazy var optionsButton: UIButton = {
        var config = UIButton.Configuration.plain()
        config.image = UIImage(systemName: "ellipsis.circle.fill",
                               withConfiguration: UIImage.SymbolConfiguration(pointSize: 44, weight: .semibold))
        config.baseForegroundColor = .white
        let button = UIButton(configuration: config)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.showsMenuAsPrimaryAction = true
        button.accessibilityLabel = "Options"
        return button
    }()
    
    // MARK: - Properties
    
    // Add view model property
    internal let viewModel = MediaLibraryViewModel()
    internal var cancellables = Set<AnyCancellable>()
    
    // ADD to the top of the class (after existing properties):
    internal let dataSource = MediaDataSource.shared

    // MARK: - Remote Album (read-only)

    /// Read-only albums mirrored from an account's online manifest. Shown as separate
    /// grid sections (sections 1…N) and kept entirely out of `MediaDataSource`.
    internal let albumStore = RemoteAlbumStore.shared

    /// Pushes "album changed" nudges from the server over a Realtime WebSocket so the TV
    /// re-syncs immediately while it stays open (instead of only on launch/foreground/
    /// manual refresh).
    internal let albumNotifier = RealtimeAlbumNotifier()

    /// Which collection the fullscreen viewer is currently showing/navigating.
    internal var activeCollection: CollectionKind = .library

    /// When `activeCollection` is `.album`, which display album (0-based over
    /// `albumStore.displayAlbums`) the fullscreen viewer is in.
    internal var albumCurrentAlbumIndex: Int = 0

    /// When `activeCollection` is `.album`, the item index within the current album.
    /// (The local library uses `MediaDataSource.currentIndex`.)
    internal var albumCurrentItemIndex: Int = 0

    /// Stable identity of the album/item the fullscreen viewer is on. Tracked alongside
    /// the indices so a background sync that reorders or removes albums/items can restore
    /// the same position (see `reconcileAlbumCursor()`) instead of jumping by raw index.
    internal var albumCurrentAlbumId: String?
    internal var albumCurrentItemId: String?

    /// The peer-to-peer connection manager that owns this view controller as its
    /// delegate. Set by `SceneDelegate` so move-mode notifications reach the live
    /// instance instead of a nil app-delegate reference.
    internal weak var connectionManager: ConnectionManager?

    internal var isInGridMode = true // Start in grid mode
    internal let sampleImageNames = ["sample1", "sample2", "sample3"]
    internal let logger = Logger(subsystem: "com.eclipsetv.app", category: "ImageViewController")

    /// Repeating timer that streams playback position to companions while a video plays
    /// fullscreen. A timer (vs an AVPlayer periodic observer) survives player swaps safely.
    internal var playbackStatusTimer: Timer?
    /// KVO on the active player's `timeControlStatus`, so play/pause changes (including
    /// from the Siri remote) are reported to companions immediately.
    internal var playbackTimeControlObservation: NSKeyValueObservation?
    
    // REMOVE these old properties - now handled by MediaDataSource:
    // internal var recentImages: [String] = []
    // internal var currentImageIndex = 0
    // internal var previouslySelectedIndex = 0
    // internal let recentImagesKey = "EclipseTV.recentImagesKey"
    
    internal var isVideo = false
    
    internal var playerLooper: AVPlayerLooper?
    
    // Track move state
    internal var isMoveMode = false
    /// The item's original position when move mode began (the source of the reorder).
    internal var originalMovingIndex: Int?
    /// The item's current target position as the user navigates focus during move mode.
    internal var movingItemIndex: Int?
    internal var movingItemIndexPath: IndexPath?
    internal var movingItemCell: UICollectionViewCell?
    
    // Flag to temporarily ignore selection events after ending move mode
    internal var isIgnoringSelectionEvents = false
    
    // Add this property:
    internal var simpleSelectionManager: SimpleSelectionManager!
    
    // Debouncing for focus changes to prevent rapid navigation issues
    internal var focusDebounceTimer: Timer?
    
    // MARK: - Storage
    internal let imageStorage = ImageStorage.shared
    
    // MARK: - Help View
    internal lazy var helpView = HelpView()
    
    // MARK: - Empty State View
    internal lazy var emptyStateView = EmptyStateView()
    
    // Add these properties near the top of the class where other properties are defined
    internal var queuedContent = [(path: String, isVideo: Bool)]()
    internal var isProcessingQueue = false
    
    // First launch detection. Used to load bundled sample media only once (see
    // `setupViewModel`); accessible from extensions in other files.
    let hasLaunchedBeforeKey = "EclipseTV.hasLaunchedBefore"
    
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
        setupOptionsButton()
        setupGradientBackground()
        setupGestures()
        setupFocusGuide()
        setupViewModel()

        // Initialize selection manager
        simpleSelectionManager = SimpleSelectionManager(collectionView: gridView)

        // Observe the remote album and start an initial sync if one is configured.
        setupAlbumSync()
        
        // Note: Player view setup is deferred until actually needed for video playback
        // This prevents unnecessary constraint conflicts during app launch
    }
    
    private var isPlayerViewSetup = false
    
    internal func setupPlayerView() {
        // Avoid setting up the player view multiple times
        guard !isPlayerViewSetup else { return }
        
        logger.info("Setting up player view for video playback")
        
        // Configure player view before adding to view hierarchy
        playerView.view.translatesAutoresizingMaskIntoConstraints = false
        playerView.view.backgroundColor = .black
        playerView.showsPlaybackControls = true  // Enable controls to allow remote control handling
        playerView.videoGravity = .resizeAspect
        
        // Add player view as child view controller
        addChild(playerView)
        view.addSubview(playerView.view)
        
        // Use full screen constraints but with lower priority to avoid conflicts
        let constraints = [
            playerView.view.topAnchor.constraint(equalTo: view.topAnchor),
            playerView.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            playerView.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            playerView.view.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ]
        
        // Set lower priority to avoid conflicts with AVPlayerViewController's internal constraints
        constraints.forEach { $0.priority = UILayoutPriority(999) }
        NSLayoutConstraint.activate(constraints)
        
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
    
    override func viewWillLayoutSubviews() {
        super.viewWillLayoutSubviews()
        // Ensure gradient is updated whenever view size changes
        setupGradientBackground()
    }
    
    /// Returns to grid view while maintaining selection state
    internal func returnToGridView() {
        logger.info("🔄 [FULLSCREEN→GRID] Returning to grid view with smooth transition")
        
        // Use the smooth showGridView method for consistent animation
        showGridView()
    }

    // Note: displayImageAtCurrentIndex() is implemented in ImageViewController+ImageManagement.swift

    // MARK: - Selection Synchronization
    
    /// Validates and fixes synchronization between visual selection and data source
    internal func validateSelectionSync() {
        guard let visualSelection = simpleSelectionManager.currentSelection else {
            logger.warning("🔴 [SYNC] No visual selection found")
            return
        }
        
        let dataIndex = dataSource.currentIndex
        let visualIndex = visualSelection.item
        
        if dataIndex != visualIndex {
            logger.warning("🔴 [SYNC] Selection desync detected! Data: \(dataIndex), Visual: \(visualIndex)")
            
            // Fix the synchronization by updating data source to match visual selection
            dataSource.setCurrentIndex(visualIndex)
            logger.debug("🔄 [SYNC] Fixed selection sync - updated data to match visual: \(visualIndex)")
        } else {
            logger.debug("✅ [SYNC] Selection is synchronized: \(visualIndex)")
        }
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
        self.dataSource.debugState()
    }
}

