//
//  LibraryGridViewController.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

// LibraryGridViewController.swift
import UIKit
import os

/// Home and Show are two pages (two collection views). Opening a Show hides
/// Home; it does not rewrite Home's grid. The marketing carousel lives only on
/// the Home page. A Show adds a live preview hero and its own media grid.
/// Blackout and "+" are Show-mode header controls. Live media still drives
/// AirPlay / EclipseTV.
final class LibraryGridViewController: UIViewController {

    // MARK: - Properties

    let connectionManager: iPhoneConnectionManager
    let store = TVLibraryStore.shared
    private let logger = Logger(subsystem: "com.eclipseapp.ios", category: "LibraryGrid")

    /// Invoked when the user chooses to re-send a purged item from Photos. The host VC
    /// owns the picker flow and the `pendingRestoreId` handshake.
    var onRequestResend: ((String) -> Void)?
    /// Invoked when the user chooses Edit — host opens the crop tool for that item.
    var onRequestEdit: ((String) -> Void)?
    /// Invoked when the user chooses Thumbnail — host opens the video frame picker.
    var onRequestVideoThumbnail: ((String) -> Void)?
    /// Invoked when the Camera phone viewer should open (⋯ Open Controller).
    var onPresentCamera: (() -> Void)?
    /// True while fullscreen Camera is opening/open — keep the tile on a still.
    var homeCameraWarmPreviewSuspended = false
    /// Invoked when the Background tile needs a new image from Photos.
    var onChooseLogo: (() -> Void)?
    /// Invoked when Screensaver should be replaced (image or video from Photos).
    var onChooseScreensaver: (() -> Void)?
    /// Invoked when the user wants to add photos/videos into a Show.
    var onAddMediaToAlbum: ((UUID) -> Void)?
    /// Invoked when the user wants to add a website into a Show.
    var onAddWebsiteToAlbum: ((UUID) -> Void)?
    /// Supplies the header Add menu for the empty-Show Add tile.
    var addMenuProvider: (() -> UIMenu)?
    /// Invoked when the user wants to create a Slideshow in a Show.
    var onCreateSlideshow: ((UUID) -> Void)?
    /// Transient status (dual-path AirPlay hint, and similar).
    var onStatusMessage: ((String) -> Void)?
    /// Invoked when the Recent Shows New Show tile is tapped.
    var onCreateShow: (() -> Void)?
    /// Invoked when Not Connected offers Connect (EclipseTV pairing).
    var onRequestEclipseTVConnect: (() -> Void)?
    /// Invoked when Show mode opens/closes or the open Show's metadata changes.
    var onOpenShowChanged: ((LocalAlbum?) -> Void)?
    /// Invoked when Show-grid arrange mode starts or ends.
    var onArrangingChanged: ((Bool) -> Void)?
    /// Invoked when Show-grid select mode starts, ends, or the selection changes.
    var onSelectingChanged: ((Bool) -> Void)?

    let sectionInset: CGFloat = 16
    let interitemSpacing: CGFloat = 12
    let headerInset: CGFloat = 16
    /// Black gap inserted between the hero banner and the grid below it.
    let heroBottomPadding: CGFloat = 16
    /// Caps Vertical-mode hero height so a 9:16 frame doesn't fill the phone.
    /// Also used to height-cap Landscape heroes on wide (iPad) panes.
    let verticalHeroMaxHeight: CGFloat = 280
    /// Last width used for hero / grid sizing; avoids redundant layout work.
    var lastLayoutWidth: CGFloat = 0
    /// Last height used for side-by-side chrome; avoids redundant layout work.
    var lastLayoutHeight: CGFloat = 0
    /// True while grid|preview are side-by-side (phone landscape).
    var isSideBySideChrome = false

    var heroHeightConstraint: NSLayoutConstraint?
    var heroWidthConstraint: NSLayoutConstraint?
    var heroLeadingConstraint: NSLayoutConstraint?
    var heroTrailingConstraint: NSLayoutConstraint?
    var heroCenterXConstraint: NSLayoutConstraint?
    /// Portrait hero top inset (safe area + padding).
    var heroTopConstraint: NSLayoutConstraint?
    /// Stacked hero-above-grid constraints (phone portrait / iPad).
    var portraitChromeConstraints: [NSLayoutConstraint] = []
    /// Preview-left / grid-right constraints (phone landscape).
    var landscapeChromeConstraints: [NSLayoutConstraint] = []
    /// Always 0 for this Show's hero (pinned). Foreign live uses its own mini view.
    var heroCollapseProgress: CGFloat = 0
    /// Every notification token this controller owns, so `deinit` can drain them in one
    /// place. One property per observer meant six of the fifteen registrations here were
    /// never torn down at all, and each new one was an opportunity to forget another.
    var observerTokens: [NSObjectProtocol] = []

    /// True while Black is the selected presentation source.
    var isBlackSelected = false
    /// True while Background is the selected presentation source.
    var isLogoSelected = false
    /// True while Screensaver is the selected presentation source.
    var isScreensaverSelected = false
    /// When true, live output cannot change; media taps open phone Preview.
    var isLiveOutputLocked = false

    /// Open Show id while in Show mode; `nil` means Home (Recent ribbon).
    var openShowId: UUID?
    /// Show that `validateOpenShow()` had to close because its Display Mode went
    /// inactive, or because its album was momentarily absent. It reopens as soon as it
    /// is valid again, so a detour through Settings returns the user to the same Show.
    var showAwaitingReturnId: UUID?
    /// True while the user is dragging Show items to rearrange them.
    var isArranging = false
    /// True while the user is multi-selecting Show surface tiles.
    var isSelecting = false
    /// Membership / tool ids checked while `isSelecting`.
    var selectedShowItemIds = Set<String>()
    /// Cancels Live Poll status polling when the ribbon hides or the Show closes.
    var questPollStatusPollTask: Task<Void, Never>?
    /// Idle Live Poll card waiting for Practice / Start in the hero.
    var livePollGateMembershipId: UUID?
    /// Working copy of the library order used while arranging and until the Apple TV
    /// confirms the saved order with a fresh manifest. `nil` means show `store.items`.
    var arrangeItems: [LibraryItemDTO]?

    /// Long-press: enter arrange mode (Show grid), then grab a tile to drag.
    lazy var reorderGesture: UILongPressGestureRecognizer = {
        let gesture = UILongPressGestureRecognizer(
            target: self,
            action: #selector(handleReorderGesture(_:))
        )
        // Idle hold is longer (enter arrange); while arranging, shorten for grabs.
        gesture.minimumPressDuration = 0.45
        gesture.allowableMovement = 8
        return gesture
    }()

    /// Media slice only (arrange working copy or mirrored TV order).
    var displayItems: [LibraryItemDTO] { arrangeItems ?? store.items }

    /// Open Show when in Show mode.
    var openShow: LocalAlbum? {
        guard let openShowId else { return nil }
        return LocalAlbumStore.shared.album(id: openShowId)
    }

    /// True when the Show page is visible (Home is only hidden, not rewritten).
    var isShowMode: Bool { openShowId != nil }

    /// Media belonging to the open Show (resolved against the library store).
    var openShowItems: [LibraryItemDTO] {
        guard let album = openShow else { return [] }
        return album.itemIds.compactMap { id in
            store.items.first(where: { $0.id == id })
        }
    }

    /// Websites belonging to the open Show (resolved against the page store).
    var openShowWebPages: [WebPage] {
        guard let album = openShow else { return [] }
        return album.itemIds.compactMap { id in
            guard let uuid = UUID(uuidString: id) else { return nil }
            return WebPageStore.shared.page(id: uuid)
        }
    }

    /// Resolvable membership ids in album order — media, websites, and PDFs.
    ///
    /// Orphans (ids whose store entry is gone) are dropped so callers agree with the
    /// grid, which also can't render them.
    var openShowMembershipIds: [String] {
        guard let album = openShow else { return [] }
        return album.itemIds.filter { id in
            if store.items.contains(where: { $0.id == id }) { return true }
            guard let uuid = UUID(uuidString: id) else { return false }
            return WebPageStore.shared.page(id: uuid) != nil
                || PDFStore.shared.documents.contains(where: { $0.id == uuid })
        }
    }

    /// Slideshows belonging to the open Show.
    var openShowSlideshows: [Slideshow] {
        guard let openShowId else { return [] }
        return SlideshowStore.shared.slideshows(forShowId: openShowId)
    }

    /// Live Poll cards belonging to the open Show.
    var openShowLivePolls: [ShowLivePoll] {
        guard let openShowId else { return [] }
        return LivePollStore.shared.polls(forShowId: openShowId)
    }

    /// Ordered Show-grid surface ids (tools, members, slideshows, Live Polls).
    /// Add is not included.
    var openShowSurfaceIds: [String] {
        guard let album = openShow else { return [] }
        LivePollStore.shared.dropLegacyToolTokensIfNeeded()
        let slideshows = openShowSlideshows.map { ShowSlideshowToken.token(for: $0.id) }
        let livePolls = openShowLivePolls.map { ShowLivePollToken.token(for: $0.id) }
        return album.resolvedSurfaceIds(slideshowIds: slideshows, livePollIds: livePolls)
    }

    /// Show-grid rows in surface order. Empty Shows append a trailing Add tile
    /// (unless arranging).
    var openShowGridItems: [ShowGridItem] {
        guard isShowMode else { return [] }
        let surface = openShowSurfaceIds.compactMap { showGridItem(forSurfaceId: $0) }
        if showsShowAddTile {
            return surface + [.add]
        }
        return surface
    }

    /// Surface cells that can be dragged while arranging (excludes Add).
    var openShowMovableCount: Int {
        openShowSurfaceIds.count
    }

    /// Empty Show (no media, websites, slideshows, or Live Polls) offers an Add tile
    /// (unless arranging or selecting).
    var showsShowAddTile: Bool {
        isShowMode
            && openShowMembershipIds.isEmpty
            && openShowSlideshows.isEmpty
            && openShowLivePolls.isEmpty
            && !isArranging
            && !isSelecting
    }

    /// Live slideshow or Live Poll ribbon is on for the open Show.
    var showsLiveSlideshowRibbon: Bool {
        if showsLivePollRibbon { return true }
        guard isShowMode,
              let id = SlideshowPlaybackController.shared.activeSlideshowId,
              let show = SlideshowStore.shared.slideshow(id: id),
              show.showId == openShowId,
              show.showRibbonWhenLive else { return false }
        return !SlideshowPlaybackController.shared.activeSlideIds.isEmpty
    }

    /// Live ribbon is never a Show-grid section; it docks under the hero.
    var showsInGridSlideshowRibbon: Bool {
        Self.showsInGridSlideshowRibbon(
            liveRibbon: showsLiveSlideshowRibbon,
            sideBySideChrome: isSideBySideChrome
        )
    }

    /// Live slideshow / Live Poll ribbon stays under the hero (portrait + landscape).
    var docksLiveSlideshowRibbon: Bool {
        showsLiveSlideshowRibbon
    }

    /// Layout inputs for the current mode, sampled by the layout on every pass.
    var homeLayoutState: HomeLayoutState {
        HomeLayoutState(
            isShowMode: isShowMode,
            showsSlideshowRibbon: showsInGridSlideshowRibbon
        )
    }

    /// Layout sections for the visible page.
    var visibleHomeSections: [HomeSection] { pageSections(for: collectionView) }

    /// Collection-view section index for `section` on the visible page.
    func sectionIndex(for section: HomeSection) -> Int? {
        visibleHomeSections.firstIndex(of: section)
    }

    /// Section at a collection-view index on the visible page.
    func homeSection(at section: Int) -> HomeSection? {
        homeSection(at: section, in: collectionView)
    }

    /// Home Recent format filter. `nil` is both; ignored unless both formats exist.
    var homeRecentOrientationFilter: ExternalOutputOrientation?

    /// Recent Shows from both Display Modes (+ New Show when empty).
    var showRibbonItems: [HomeGridItem] {
        let albums = LocalAlbumStore.shared.albums
        let filter = HomeGridItem.hasBothOrientations(in: albums)
            ? homeRecentOrientationFilter
            : nil
        return HomeGridItem.recentShows(from: albums, orientation: filter)
    }

    /// Index of the Camera tile in the open Show grid, if present.
    var cameraShowItemIndex: Int? {
        openShowGridItems.firstIndex {
            if case .camera = $0 { return true }
            return false
        }
    }

    /// Fired when Black live chrome should update (e.g. header button).
    var onBlackLiveChanged: ((Bool) -> Void)?
    /// Fired when live-output lock toggles (header amber chrome).
    var onLiveOutputLockChanged: ((Bool) -> Void)?

    /// Extra bottom inset reserved for the home mini player.
    var miniPlayerBottomInset: CGFloat = 0 {
        didSet {
            guard miniPlayerBottomInset != oldValue else { return }
            syncHeroOverlayInsets(preservingProgress: currentHeroScrollProgress())
            bottomChromeBottomConstraint?.constant = -(miniPlayerBottomInset + 20)
            updateHomeVerticalScrollPolicy()
        }
    }

    /// Reserved height under the landscape live preview. Always 0 today — the mini
    /// player is a trailing card, not docked under the hero.
    var sideBySideMiniPlayerHeight: CGFloat = 0 {
        didSet {
            guard abs(sideBySideMiniPlayerHeight - oldValue) > 0.5 else { return }
            guard isSideBySideChrome else { return }
            applyHeroChrome()
        }
    }

    func homeItem(at indexPath: IndexPath) -> HomeGridItem? {
        guard homeSection(at: indexPath.section, in: homeCollectionView) == .shows,
              showRibbonItems.indices.contains(indexPath.item) else { return nil }
        return showRibbonItems[indexPath.item]
    }

    func displayItem(at index: Int) -> LibraryItemDTO? {
        let items = displayItems
        guard index >= 0 && index < items.count else { return nil }
        return items[index]
    }

    let liveHeader: LiveHeaderView = {
        let header = LiveHeaderView()
        header.translatesAutoresizingMaskIntoConstraints = false
        return header
    }()

    /// Tucked mini preview of live output that still belongs to another Show.
    let foreignLiveHeader: LiveHeaderView = {
        let header = LiveHeaderView()
        header.translatesAutoresizingMaskIntoConstraints = true
        header.isHidden = true
        return header
    }()

    /// Parked view kept only so landscape chrome constraints stay unambiguous.
    /// Black plate behind the portrait live card so tiles can't show in the
    /// gap under the header (or beside a capped Vertical preview).
    let heroSpacer: UIView = {
        let view = UIView()
        view.backgroundColor = .black
        view.isHidden = true
        view.isUserInteractionEnabled = true
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    /// Shared frame for the Home and Show pages. Chrome pins this host; each
    /// page fills it and is shown or hidden.
    let gridHost: UIView = {
        let view = UIView()
        view.backgroundColor = .systemBackground
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    lazy var homeCollectionView: UICollectionView = {
        makePageCollectionView(layout: makeHomePageLayout(), registersHero: true)
    }()

    lazy var showCollectionView: UICollectionView = {
        makePageCollectionView(layout: makeShowPageLayout(), registersHero: false)
    }()

    /// Horizontal slide strip docked under the landscape live preview.
    lazy var slideshowRibbonView: UICollectionView = makeDockedSlideshowRibbonView()
    /// Last in-grid / docked ribbon placement. Slide advances must not rebuild this.
    var lastSlideshowRibbonChrome: SlideshowRibbonChrome?
    /// Height of the docked ribbon (0 when it is parked or hidden).
    var dockedRibbonHeightConstraint: NSLayoutConstraint?
    /// Gap between the landscape preview and the docked ribbon (0 when hidden).
    var dockedRibbonTopConstraint: NSLayoutConstraint?

    let emptyLabel: UILabel = {
        let label = UILabel()
        label.textColor = .secondaryLabel
        label.font = .preferredFont(forTextStyle: .subheadline)
        label.adjustsFontForContentSizeCategory = true
        label.textAlignment = .center
        label.numberOfLines = 0
        label.isHidden = true
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    let musicSwipeHint: HomeMusicSwipeHint = {
        let hint = HomeMusicSwipeHint()
        hint.translatesAutoresizingMaskIntoConstraints = false
        return hint
    }()

    let syncStatusBanner: EclipseSyncStatusBanner = {
        let banner = EclipseSyncStatusBanner()
        banner.translatesAutoresizingMaskIntoConstraints = false
        return banner
    }()

    var emptyTopConstraint: NSLayoutConstraint?
    var bottomChromeBottomConstraint: NSLayoutConstraint?

    // MARK: - Init

    init(connectionManager: iPhoneConnectionManager) {
        self.connectionManager = connectionManager
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        installHomeCameraPreviewObservers()
        observe(WarmWebSession.didRelinquishNotification) { [weak self] _ in
            self?.refreshLiveHeader()
        }
        LivePollStore.shared.dropLegacyToolTokensIfNeeded()
        registerForTraitChanges(
            [UITraitVerticalSizeClass.self]
        ) { (self: Self, _: UITraitCollection) in
            // Bounds may not have updated yet; clear cache so layout reapplies.
            self.lastLayoutWidth = 0
            self.lastLayoutHeight = 0
            self.updateChromeLayoutIfNeeded()
        }

        liveHeader.onTogglePlayPause = { [weak self] in
            self?.handleLiveVideoPlayPause()
        }
        liveHeader.onSkip = { [weak self] delta in
            self?.handleLiveVideoSkip(by: delta)
        }
        liveHeader.onSeek = { [weak self] position in
            self?.handleLiveVideoSeek(to: position)
        }
        liveHeader.onRequestFullscreen = { [weak self] in
            self?.presentFullscreenForLiveMedia()
        }
        liveHeader.onRequestHostController = { [weak self] in
            self?.presentQuestPollHostController()
        }
        liveHeader.onRequestCameraController = { [weak self] in
            self?.onPresentCamera?()
        }
        liveHeader.onSlideshowSwipe = { delta in
            SlideshowPlaybackController.shared.goToAdjacentSlide(delta: delta)
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        }
        liveHeader.onToggleSlideshowRibbon = { [weak self] in
            self?.toggleLiveSlideshowRibbon()
        }

        // Grid under the floating live hero so content can scroll beneath it.
        installLibraryPages()
        view.addSubview(heroSpacer)
        view.addSubview(liveHeader)
        view.addSubview(slideshowRibbonView)
        view.addSubview(emptyLabel)
        let bottomChrome = UIStackView(arrangedSubviews: [syncStatusBanner, musicSwipeHint])
        bottomChrome.axis = .vertical
        bottomChrome.spacing = 8
        bottomChrome.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(bottomChrome)
        // Clear the home-indicator / rounded-corner bite so the banner isn't clipped.
        let bottomChromeBottom = bottomChrome.bottomAnchor.constraint(
            equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -20
        )
        bottomChromeBottomConstraint = bottomChromeBottom
        NSLayoutConstraint.activate([
            bottomChrome.leadingAnchor.constraint(
                equalTo: view.leadingAnchor, constant: sectionInset
            ),
            bottomChrome.trailingAnchor.constraint(
                equalTo: view.trailingAnchor, constant: -sectionInset
            ),
            bottomChromeBottom
        ])
        installChromeLayout()
        installForeignLivePreview()
        updateHeroVisibility()
        applyLayoutMode()
        observe(ExternalOutputSettings.didChangeNotification) { [weak self] _ in
            self?.applyLayoutMode()
            // Settings Display Mode: keep the open Show by adopting the new format.
            // Cross-mode Show opens clear `openShowId` first so nothing is rewritten.
            self?.validateOpenShow(adoptingCurrentDisplayMode: true)
            self?.refreshVisibleCameraTilePreview()
        }
        observe(WebPageStore.didChangeNotification) { [weak self] _ in
            self?.reloadGridIfSafe()
            self?.updateEmptyState()
        }
        observe(LocalAlbumStore.didChangeNotification) { [weak self] _ in
            self?.validateOpenShow()
            self?.reloadGridIfSafe()
            self?.updateEmptyState()
            self?.updateHeroVisibility()
            self?.refreshLiveHeader()
        }
        observe(SlideshowStore.didChangeNotification) { [weak self] _ in
            self?.refreshSlideshowRibbonPresentation()
            self?.reloadGridIfSafe()
            self?.updateEmptyState()
        }
        observe(LivePollStore.didChangeNotification) { [weak self] _ in
            self?.reloadGridIfSafe()
            self?.updateEmptyState()
        }
        observe(SlideshowPlaybackController.didChangeNotification) { [weak self] _ in
            self?.refreshSlideshowRibbonPresentation()
            self?.refreshLiveHeader()
            self?.scrollLiveSlideshowRibbonToCurrentSlide()
        }
        observe(QuestPollSessionStore.didChangeNotification) { [weak self] _ in
            self?.handleQuestPollSessionChange()
        }
        observe(VideoResumeStore.didChangeNotification) { [weak self] _ in
            self?.reloadGridIfSafe()
        }
        observe(WebThumbnailStore.didChangeNotification) { [weak self] _ in
            self?.reloadGridIfSafe()
            self?.refreshLiveHeader()
        }
        observe(LogoStore.didChangeNotification) { [weak self] _ in
            guard let self else { return }
            self.reloadGridIfSafe()
            if LiveOutputRouting.shouldRefreshLiveAfterReplace(
                isToolLive: self.isLogoSelected
            ) {
                self.presentLogoLive()
            } else {
                self.refreshLiveHeader()
            }
        }
        observe(ScreensaverStore.didChangeNotification) { [weak self] _ in
            guard let self else { return }
            self.liveHeader.clearScreensaverPreview()
            self.reloadGridIfSafe()
            if LiveOutputRouting.shouldRefreshLiveAfterReplace(
                isToolLive: self.isScreensaverSelected
            ) {
                self.presentScreensaverLive()
            } else {
                self.refreshLiveHeader()
            }
        }
        observe(PDFStore.didChangeNotification) { [weak self] _ in
            self?.reloadGridIfSafe()
            self?.updateEmptyState()
        }
        observe(PDFThumbnailStore.didChangeNotification) { [weak self] _ in
            self?.reloadGridIfSafe()
            self?.refreshLiveHeader()
        }
        observe(CameraManager.lastFrameDidChangeNotification) { [weak self] _ in
            self?.reloadCameraTile()
        }
        observe(CaptureStore.didChangeNotification) { [weak self] _ in
            TVLibraryStore.shared.refreshMergedCaptures()
            self?.reloadGridIfSafe()
            self?.updateEmptyState()
        }
        observe(EclipseSyncController.statusDidChangeNotification) { [weak self] _ in
            self?.syncStatusBanner.reload()
        }

        let overlayReload: (Notification) -> Void = { [weak self] _ in
            self?.syncScreensaverFallbackLiveSelection()
            self?.reloadGridIfSafe()
            self?.refreshLiveHeader()
        }
        observe(ExternalDisplayManager.videoPlaybackDidChangeNotification) { [weak self] _ in
            self?.applyAirPlayVideoPlaybackToHero()
        }
        observe(ExternalDisplayManager.didChangeNotification) { [weak self] note in
            guard let self else { return }
            if ExternalDisplayManager.shared.isConnected {
                self.pushCurrentToExternalDisplay()
            } else if note.userInfo?[ExternalDisplayManager.disconnectReasonKey] as? Bool == true {
                // AirPlay / HDMI dropped — keep phone camera / web / PDF open; tip the user.
                self.showPresentationToast("External display disconnected")
            }
            // Hero follows a real destination or Practice Mode.
            self.updateHeroVisibility()
            self.applyHeroChrome()
            overlayReload(note)
        }
        observe(ExternalDisplayManager.webDidEndNotification, using: overlayReload)
        observe(ExternalDisplayManager.pdfDidEndNotification, using: overlayReload)
        observe(ExternalDisplayManager.cameraDidEndNotification) { [weak self] note in
            self?.adoptBackgroundSelectionIfCameraCommitted()
            overlayReload(note)
            // AirPlay tore down the session — warm the home tile again.
            self?.warmHomeCameraPreview()
        }
        observe(CameraLiveViewController.didDismissNotification) { [weak self] _ in
            self?.adoptBackgroundSelectionIfCameraCommitted()
            self?.homeCameraWarmPreviewSuspended = false
            self?.reloadGridIfSafe()
            self?.refreshLiveHeader()
            self?.warmHomeCameraPreview()
        }
    }

    /// Registers a main-queue observer and keeps its token for teardown.
    func observe(
        _ name: Notification.Name,
        using handler: @escaping (Notification) -> Void
    ) {
        observerTokens.append(
            NotificationCenter.default.addObserver(
                forName: name, object: nil, queue: .main, using: handler
            )
        )
    }

    deinit {
        for token in observerTokens {
            NotificationCenter.default.removeObserver(token)
        }
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        updateChromeLayoutIfNeeded()
        // Hero bounds are only trustworthy after layout; re-derive the collapse so
        // rotation / Display Mode changes land on the right transform.
        updateHeroCollapse()
        layoutForeignLivePreview()
        // Phone turn: keep the Camera tile upright without rebuilding the freeze still.
        syncVisibleCameraTileOrientation()
        // Content size is final here — pin leftover offset if the grid no longer overflows.
        updateHomeVerticalScrollPolicy()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        store.delegate = self
        // Let the external display ask for the live item if it connects mid-session.
        ExternalDisplayManager.shared.currentSourceProvider = { [weak self] in
            self?.currentPresentationSource()
        }
        updateEmptyState()
        updateVisibleLibraryPage()
        if isShowMode {
            refreshLiveHeader()
        } else {
            enforceHomeLiveHeroTeardownIfNeeded()
        }
        syncScreensaverFallbackLiveSelection()
        reloadLibraryGrid()
        pushCurrentToExternalDisplay()
        warmHomeCameraPreview()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        // Cold launch: viewWillAppear can run before the app is active; retry here.
        warmHomeCameraPreview()
        updateHeroCollapse()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        if store.delegate === self {
            store.delegate = nil
        }
        ExternalDisplayManager.shared.currentSourceProvider = nil
        stopHomeCameraPreviewIfNeeded()
    }

    // MARK: - Helpers

    func updateEmptyState() {
        // Show mode owns its empty Add tile; Home shows Recent from both modes.
        refreshMusicSwipeHintVisibility()
        guard !isShowMode else {
            emptyLabel.isHidden = true
            return
        }
        let hasShows = !LocalAlbumStore.shared.albums.isEmpty
        if !hasShows {
            emptyLabel.text = "Create a Show to get started."
            emptyLabel.isHidden = false
            // Sit just below the lone New Show tile rather than over it.
            let tile = Self.homeRecentTileSize(
                containerWidth: collectionView.bounds.width,
                sectionInset: sectionInset,
                spacing: interitemSpacing
            )
            emptyTopConstraint?.constant = collectionView.contentInset.top
                + Self.heroEstimatedHeight
                + Self.showsGridTopInset
                + Self.sectionHeaderEstimatedHeight
                + tile.height
                + sectionInset * 2
        } else {
            emptyLabel.isHidden = true
        }
    }

    /// Compact paging can swipe to Music; side-by-side layout cannot.
    func setMusicPagingAvailable(_ available: Bool) {
        musicSwipeHint.setMusicPagingAvailable(available)
        refreshMusicSwipeHintVisibility()
    }

    /// Music swipe tip is Home-only — never Show mode or any other surface.
    func refreshMusicSwipeHintVisibility() {
        guard !isShowMode else {
            musicSwipeHint.isHidden = true
            return
        }
        musicSwipeHint.reload()
    }

    /// Permanently hides the Home Music swipe hint after dismiss or first visit.
    func dismissMusicSwipeHint() {
        musicSwipeHint.dismissPermanently()
        refreshMusicSwipeHintVisibility()
    }

    /// Rebuilds the Show page layout. Home keeps its own layout.
    func applyCollectionLayout() {
        applyShowPageLayout()
    }

    /// Keeps Home and Show pages rubber-bandable even when the grid fits on screen.
    func updateHomeVerticalScrollPolicy() {
        collectionView.alwaysBounceVertical = true
        collectionView.bounces = true
        collectionView.isScrollEnabled = true
        // Don't yank the offset while the user is mid-bounce.
        guard !collectionView.isDragging, !collectionView.isDecelerating else { return }
        if maxVerticalScroll() <= 8 {
            pinCollectionViewToTop()
        }
    }

    /// Pins the grid to its top inset (no residual overscroll under the header).
    func pinCollectionViewToTop() {
        let top = -collectionView.adjustedContentInset.top
        if abs(collectionView.contentOffset.y - top) > 0.5 {
            collectionView.setContentOffset(CGPoint(x: 0, y: top), animated: false)
        }
    }

    /// Reloads only the Camera tile (live preview / last-frame updates).
    func reloadCameraTile() {
        guard let showsSection = sectionIndex(for: .shows),
              let item = cameraShowItemIndex else { return }
        let indexPath = IndexPath(item: item, section: showsSection)
        guard collectionView.indexPathsForVisibleItems.contains(indexPath) else {
            return
        }
        collectionView.reloadItems(at: [indexPath])
    }

    /// Updates the fixed hero banner to reflect the currently live item (or a placeholder).
    ///
    /// Home uses the marketing carousel only — the live preview must stay hidden
    /// there. Blackout chrome still updates so the header moon reflects live state.
    func refreshLiveHeader() {
        let mgr = ExternalDisplayManager.shared
        let blackLive = isBlackSelected && !mgr.isOverlayLive
        onBlackLiveChanged?(blackLive)
        onLiveOutputLockChanged?(isLiveOutputLocked)
        liveHeader.setOutputLocked(isLiveOutputLocked)
        guard showsLiveHero else {
            // Never leave a Show-mode live preview over the Home marketing carousel.
            liveHeader.clearWebPreview(parking: true)
            liveHeader.clearScreensaverPreview()
            liveHeader.clearLibraryVideoPreview()
            liveHeader.hideLivePollGate()
            liveHeader.setSlideshowRibbonToggleVisible(false, isOn: false)
            liveHeader.allowsSlideshowBrowse = false
            liveHeader.isHidden = true
            liveHeader.isUserInteractionEnabled = false
            refreshForeignLivePreview()
            return
        }
        liveHeader.isHidden = false
        liveHeader.isUserInteractionEnabled = true
        // Ribbon toggle visibility follows the active slideshow for this Show.
        defer { syncLiveSlideshowRibbonChrome() }

        // Another Show still owns live output — keep AirPlay as-is, show an empty
        // hero here, and park the live art in the tucked mini preview.
        if isLiveFromOtherShow {
            liveHeader.configureSelectToGoLive()
            liveHeader.updatePlayback(PlaybackState())
            refreshForeignLivePreview()
            updateHeroCollapse()
            return
        }
        refreshForeignLivePreview()

        if applyLivePollIdleHeaderIfNeeded() {
            return
        }
        if mgr.isWebLive {
            if mgr.isQuestPollLive {
                applyQuestPollLiveHeader()
                return
            }
            let pageId = mgr.liveWebPageId
            let page = pageId.flatMap { WebPageStore.shared.page(id: $0) }
            let title = page?.title ?? "Website"
            let thumb = pageId.flatMap { WebThumbnailStore.shared.image(for: $0) }
            let canShowLivePreview = pageId.map {
                !WarmWebSessionPool.shared.isAdopted(pageId: $0)
            } ?? false
            liveHeader.configureOverlay(
                title: title,
                systemImage: "safari",
                fillColor: UIColor(white: 0.12, alpha: 1),
                thumbnail: thumb,
                keepWebPreview: canShowLivePreview
            )
            if let pageId, canShowLivePreview {
                // In-app hero shows the warm page even with no AirPlay display.
                liveHeader.showWebPreview(pageId: pageId)
            }
            liveHeader.updatePlayback(PlaybackState())
            return
        }
        if mgr.isPDFLive {
            let doc = PDFStore.shared.documents
                .first(where: { $0.id == mgr.livePDFDocumentId })
            let title = doc?.title ?? "PDF"
            let thumb = doc.flatMap { PDFThumbnailStore.shared.image(for: $0.id) }
            liveHeader.configureOverlay(
                title: title,
                systemImage: "doc.richtext",
                fillColor: UIColor(white: 0.12, alpha: 1),
                thumbnail: thumb
            )
            liveHeader.updatePlayback(PlaybackState())
            return
        }
        if mgr.isCameraLive {
            liveHeader.configureOverlay(
                title: "Camera",
                systemImage: "camera.fill",
                fillColor: UIColor(white: 0.12, alpha: 1)
            )
            liveHeader.allowsCameraControllerTap = true
            liveHeader.updatePlayback(PlaybackState())
            return
        }
        if mgr.isParkedOnQuickChangeStill {
            liveHeader.configureOverlay(
                title: "Camera",
                systemImage: "camera.fill",
                fillColor: UIColor(white: 0.12, alpha: 1),
                thumbnail: mgr.cameraTileParkedStillImage
            )
            liveHeader.allowsCameraControllerTap = true
            liveHeader.updatePlayback(PlaybackState())
            return
        }
        if isBlackSelected {
            liveHeader.configureOverlay(
                title: "Blackout",
                systemImage: "moon.fill",
                fillColor: .black
            )
            liveHeader.updatePlayback(PlaybackState())
            return
        }
        if isLogoSelected {
            liveHeader.configureOverlay(
                title: "Background",
                systemImage: "seal.fill",
                fillColor: UIColor(white: 0.12, alpha: 1),
                thumbnail: LogoStore.shared.image
            )
            liveHeader.updatePlayback(PlaybackState())
            return
        }
        if isScreensaverSelected {
            presentScreensaverInLiveHeader()
            return
        }

        let liveItem = store.currentId.flatMap { id in
            store.items.first(where: { $0.id == id })
        }
        // AirPlay with nothing selected: preview the passive Screensaver filling
        // the external display. Practice Mode uses the same fallback.
        // EclipseTV-only still shows the connect prompt.
        if liveItem == nil, mgr.isConnected
            || (prefersDisconnectedLivePreview && !store.isOnline) {
            presentScreensaverInLiveHeader()
            return
        }
        if let liveItem, liveItem.isVideo {
            applyLibraryVideoLiveHeader(item: liveItem)
            return
        }
        let thumbnail = liveItem.flatMap { store.thumbnail(for: $0.id) }
        liveHeader.configure(
            with: liveItem,
            thumbnail: thumbnail,
            isOnline: store.isOnline
        )
        liveHeader.clearLibraryVideoPreview()
        liveHeader.updatePlayback(store.playback)
    }

    /// Opens fullscreen Preview for phone-local live media.
    func presentFullscreenForLiveMedia() {
        guard let id = store.currentId,
              let item = store.items.first(where: { $0.id == id }),
              let url = LocalMediaStore.shared.localURL(forId: id) else { return }
        if item.isVideo {
            let startAt = liveHeader.libraryVideoPlaybackState.currentTime
            liveHeader.pauseLibraryVideoPreview()
            presentLocalVideoPreview(
                fileURL: url,
                isMuted: item.isMuted ?? false,
                isLooping: item.isLooping ?? false,
                startAt: startAt
            ) { [weak self] position in
                self?.liveHeader.resumeLibraryVideoPreview(at: position)
            }
            return
        }
        presentLocalPreview(
            for: item,
            in: openShowItems.isEmpty ? displayItems : openShowItems
        )
    }

    /// Static poster chrome + muted looping video in the phone preview.
    private func presentScreensaverInLiveHeader() {
        liveHeader.configureOverlay(
            title: "Screensaver",
            systemImage: "sparkles.tv",
            fillColor: UIColor(white: 0.12, alpha: 1),
            thumbnail: ScreensaverStore.poster,
            keepScreensaverPreview: liveHeader.screensaverPreview != nil
        )
        liveHeader.showScreensaverPreview()
        liveHeader.updatePlayback(PlaybackState())
    }

    // MARK: - External Display

    /// The presentation source for the currently live item.
    ///
    /// Used by `ExternalDisplayManager` when a display connects mid-session.
    /// Falls back to the bundled Screensaver so AirPlay never shows a grey idle.
    /// Connection observers mark that fallback as the live Screensaver tile.
    func currentPresentationSource() -> PresentationSource? {
        switch ExternalDisplayManager.shared.overlaySource {
        case .camera:
            if let parked = ExternalDisplayManager.shared.parkedStillPresentationSource {
                return parked
            }
            return .camera
        case .web(let url):
            return .web(url)
        case .pdf(let url):
            return .pdf(url)
        case .countdown:
            return .countdown
        case .none:
            break
        }
        if isBlackSelected {
            return .black
        }
        if isScreensaverSelected {
            return ScreensaverStore.presentationSource
        }
        if isLogoSelected {
            return LogoStore.shared.presentationSource
        }
        if let id = store.currentId,
           let item = store.items.first(where: { $0.id == id }) {
            let startAt: TimeInterval
            if item.isVideo {
                startAt = ExternalDisplayManager.shared
                    .currentVideoPlaybackTime(forItemId: id)
                    ?? VideoResumeStore.shared.position(for: id)
                    ?? 0
            } else {
                startAt = 0
            }
            return .forLibraryItem(
                item, thumbnail: store.thumbnail(for: id), startAt: startAt
            )
        }
        return ScreensaverStore.presentationSource
    }

    /// Pushes the currently live item to the external display (if one is connected).
    /// Does not interrupt an active camera/web overlay or a sticky joined presentation.
    private func pushCurrentToExternalDisplay() {
        guard ExternalDisplayManager.shared.isConnected else { return }
        guard !ExternalDisplayManager.shared.isOverlayLive else { return }
        guard !ExternalDisplayManager.shared.isJoinedLive else { return }
        if let source = currentPresentationSource() {
            ExternalDisplayManager.shared.present(source)
        }
    }

    /// Reloads the grid unless an interactive reorder is in flight.
    ///
    /// Background stores (thumbnails, slideshows, albums, PDFs, overlay state) post changes
    /// at any time. A `reloadData()` in the middle of `UICollectionView`'s interactive move
    /// invalidates the drag's index paths, which drops the drag and can throw outright.
    /// The order reconciles from the Apple TV's next manifest once arranging finishes.
    func reloadGridIfSafe() {
        guard !isArranging else { return }
        pruneShowSelection()
        reloadLibraryGrid()
    }

    /// Reloads the collection view while keeping on-screen thumbnail pins warm.
    ///
    /// Prefer this over bare `reloadData()` on go-live / live-chrome paths: video decode
    /// often purges `NSCache`, and an unpinned reload paints blank placeholders.
    func reloadLibraryGrid() {
        refreshVisibleThumbnailPins()
        homeCollectionView.reloadData()
        showCollectionView.reloadData()
        slideshowRibbonView.reloadData()
        collectionView.layoutIfNeeded()
        refreshVisibleThumbnailPins()
    }

    /// Clears home-grid live selection when a joined album item becomes the live output.
    func clearLiveSelectionForJoinedPresent() {
        isBlackSelected = false
        isLogoSelected = false
        isScreensaverSelected = false
        store.updateCurrentId(nil)
        reloadLibraryGrid()
        refreshLiveHeader()
    }

    // MARK: - Per-item Options

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
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
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

// MARK: - TVLibraryStoreDelegate

extension LibraryGridViewController: TVLibraryStoreDelegate {
    func libraryStoreDidUpdateItems(_ store: TVLibraryStore) {
        // While actively dragging, keep the working order; it reconciles on finish.
        guard !isArranging else { return }
        // A fresh manifest from the TV confirms any just-saved arrangement.
        arrangeItems = nil
        reloadLibraryGrid()
        updateEmptyState()
        refreshLiveHeader()
    }

    func libraryStoreDidUpdateCurrent(_ store: TVLibraryStore) {
        if store.currentId != nil {
            isBlackSelected = false
            isLogoSelected = false
            isScreensaverSelected = false
        }
        refreshLiveHeader()
        pushCurrentToExternalDisplay()
        guard !isArranging else { return }
        pruneShowSelection()
        // Prefer visible-only reload: go-live often coincides with video memory
        // pressure that empties NSCache; a full reloadData blanked the whole Show.
        // Fall back when Display Mode just swapped buckets — visible paths can
        // outlive the new data-source counts and crash reloadItems.
        reloadVisibleItemsOrGrid()
    }

    /// Reloads on-screen cells, or the whole grid when any path is out of bounds.
    ///
    /// Bounds come from the data source (not `collectionView.numberOfSections`) so a
    /// layout that still reflects the previous Home/Show shape cannot green-light a
    /// `reloadItems` against a shorter bucket.
    private func reloadVisibleItemsOrGrid() {
        refreshVisibleThumbnailPins()
        let visible = collectionView.indexPathsForVisibleItems
        guard !visible.isEmpty else {
            reloadLibraryGrid()
            return
        }
        let sectionCount = numberOfSections(in: collectionView)
        let safe = visible.filter { path in
            guard path.section >= 0, path.section < sectionCount else { return false }
            let count = self.collectionView(
                collectionView, numberOfItemsInSection: path.section
            )
            return path.item >= 0 && path.item < count
        }
        if safe.count != visible.count || safe.isEmpty {
            reloadLibraryGrid()
            return
        }
        collectionView.reloadItems(at: safe)
        refreshVisibleThumbnailPins()
    }

    func libraryStore(_ store: TVLibraryStore, didUpdateThumbnailFor id: String) {
        if id == store.currentId {
            refreshLiveHeader()
        }
        // Still paint during arrange — entry reload can miss a purged NSCache, and
        // skipping the update left blank tiles for the whole arrange session.
        // Item/order reloads stay gated; only the thumb for this id refreshes.
        guard let showsSection = sectionIndex(for: .shows) else { return }
        if isShowMode {
            var paths: [IndexPath] = []
            if docksLiveSlideshowRibbon {
                reloadDockedRibbonThumbnail(for: id)
            } else if let ribbonSection = sectionIndex(for: .slideshowRibbon),
               let ribbonIndex = SlideshowPlaybackController.shared.activeSlideIds
                .firstIndex(of: id) {
                let path = IndexPath(item: ribbonIndex, section: ribbonSection)
                if collectionView.indexPathsForVisibleItems.contains(path) {
                    paths.append(path)
                }
            }
            // Use grid item order (not raw surface ids) — compactMap can drop
            // unresolved members and skew indexes, leaving blanks stuck.
            let gridPaths: [IndexPath] = openShowGridItems.enumerated().compactMap { index, item in
                let matches: Bool
                switch item {
                case .media(let media):
                    matches = media.id == id
                case .slideshow(let show):
                    matches = show.resolvedCoverId == id
                default:
                    matches = false
                }
                guard matches else { return nil }
                let path = IndexPath(item: index, section: showsSection)
                return collectionView.indexPathsForVisibleItems.contains(path) ? path : nil
            }
            paths.append(contentsOf: gridPaths)
            if !paths.isEmpty {
                collectionView.reloadItems(at: paths)
            }
            return
        }
        // Home shows Show covers; reload any ribbon tile that uses this media.
        let items = showRibbonItems
        let paths: [IndexPath] = items.enumerated().compactMap { index, item in
            guard case .show(let show) = item,
                  show.itemIds.contains(id) else { return nil }
            let path = IndexPath(item: index, section: showsSection)
            return collectionView.indexPathsForVisibleItems.contains(path) ? path : nil
        }
        if !paths.isEmpty {
            collectionView.reloadItems(at: paths)
        }
    }

    func libraryStoreDidChangeConnection(_ store: TVLibraryStore) {
        updateEmptyState()
        // Eclipse TV link also gates the disconnected live hero.
        updateHeroVisibility()
        applyHeroChrome()
        refreshLiveHeader()
        reloadLibraryGrid()
    }

    func libraryStoreDidUpdatePlayback(_ store: TVLibraryStore) {
        if ExternalDisplayManager.shared.isLibraryVideoLive { return }
        liveHeader.updatePlayback(store.playback)
    }
}
