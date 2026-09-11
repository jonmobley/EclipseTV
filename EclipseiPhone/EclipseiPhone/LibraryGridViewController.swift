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
    /// Black gap inserted between the hero banner and the grid below it. Both the
    /// grid's resting top inset and the `heroSpacer` plate extend by this amount,
    /// so the first row starts flush with the plate's shadowed bottom edge.
    /// A docked ribbon brings its own padding — see `liveChromeBottomPadding`.
    let heroBottomPadding: CGFloat = 16
    /// Last width used for hero / grid sizing; avoids redundant layout work.
    var lastLayoutWidth: CGFloat = 0
    /// Last height used for side-by-side chrome; avoids redundant layout work.
    var lastLayoutHeight: CGFloat = 0
    /// `gridHost` size at the last layout pass; a change is what re-applies the
    /// pending scroll anchor. See `LibraryGridViewController+ScrollAnchor`.
    var lastGridLayoutSize: CGSize = .zero
    /// Where `page` was scrolled before its geometry changed, waiting for the page
    /// to lay out at its new size so the same share of the range can be restored.
    var pendingGridScrollAnchor: (page: UICollectionView, anchor: GridScrollAnchor)?
    /// True while grid|preview are side-by-side (phone / iPad landscape).
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
    /// Preview-left / grid-right constraints (phone + iPad landscape).
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
    /// Surface ids of the open Show as of the last album-store change. Anything new
    /// on the next change is a just-added tile the grid snaps to.
    var revealedShowSurface: (showId: UUID, ids: Set<String>)?
    /// One-shot cold-launch restore of the most recently opened Show.
    private static var didAttemptRestoreLastShow = false
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
        // Both migrations rewrite the album's surface, so read `openShow` after
        // them or the first build renders the pre-migration snapshot.
        LivePollStore.shared.dropLegacyToolTokensIfNeeded()
        CountdownStore.shared.migrateLegacyToolTokensIfNeeded()
        guard let album = openShow else { return [] }
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
    ///
    /// A live countdown has no ribbon: its duration lives in the tile's ⋯ menu.
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
    /// Fired when a phone-hosted Live Poll takes or releases the hero, so the
    /// header can offer Lock / Blackout for it even with Practice Mode off.
    var onLivePollPhoneHeroChanged: ((Bool) -> Void)?

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

    /// Black plate behind the portrait live card so tiles can't show in the
    /// gap under the header (or beside a capped Vertical preview). Parked at
    /// 0×0 in landscape so those chrome constraints stay unambiguous.
    let heroSpacer: LiveHeroBackdropView = {
        let view = LiveHeroBackdropView()
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

    /// Note for the live item, docked under the preview (and under the ribbon).
    let liveNoteCard: LiveNoteCardView = {
        let card = LiveNoteCardView()
        card.isHidden = true
        card.translatesAutoresizingMaskIntoConstraints = false
        return card
    }()
    /// Item whose note the card is showing; `nil` while the card is parked.
    var presentedLiveNoteId: String?
    /// Note text the card currently carries.
    var presentedLiveNote: String?
    /// Gap between the bottom-most live chrome and the note card (0 when parked).
    var liveNoteTopConstraint: NSLayoutConstraint?
    /// Measured note-card height (0 when parked).
    var liveNoteHeightConstraint: NSLayoutConstraint?

    /// Last in-grid / docked ribbon placement. Slide advances must not rebuild this.
    var lastSlideshowRibbonChrome: SlideshowRibbonChrome?
    /// Hero + ribbon presentation the last chrome pass applied (`nil` before the first).
    var presentedLiveChrome: LiveChromeState?
    /// Docked ribbon is fading out; keep it unhidden until the animation lands.
    var isFadingOutDockedRibbon = false
    /// Invalidates the completion of a superseded ribbon show / hide animation.
    var dockedRibbonTransitionToken = 0
    /// Height of the docked ribbon (0 when it is parked, hidden, or vertical).
    var dockedRibbonHeightConstraint: NSLayoutConstraint?
    /// Width of the docked ribbon (0 when it is parked, hidden, or horizontal).
    var dockedRibbonWidthConstraint: NSLayoutConstraint?
    /// Gap between the landscape preview and the docked ribbon (0 when hidden).
    var dockedRibbonTopConstraint: NSLayoutConstraint?
    /// How far the black plate runs past the bottom-most live chrome.
    var heroBackdropBottomConstraint: NSLayoutConstraint?
    /// Landscape grid leading pinned to the hero trailing edge (horizontal ribbon).
    var landscapeGridLeadingFromHeroConstraint: NSLayoutConstraint?
    /// Landscape grid leading pinned to the vertical ribbon trailing edge.
    var landscapeGridLeadingFromRibbonConstraint: NSLayoutConstraint?
    /// Ribbon pins used when the strip sits under the hero (portrait + phone landscape).
    var horizontalDockedRibbonConstraints: [NSLayoutConstraint] = []
    /// Ribbon pins used when the strip sits beside the hero (iPad landscape).
    var verticalDockedRibbonConstraints: [NSLayoutConstraint] = []

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
        CountdownStore.shared.migrateLegacyToolTokensIfNeeded()
        registerForTraitChanges(
            [UITraitVerticalSizeClass.self, UITraitHorizontalSizeClass.self]
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
        liveHeader.onRequestOverlayController = { [weak self] in
            self?.presentControllerForLiveOverlay()
        }
        liveHeader.onSlideshowSwipe = { delta in
            SlideshowPlaybackController.shared.goToAdjacentSlide(delta: delta)
            Haptics.impactLight()
        }
        liveHeader.onLibraryBrowse = { [weak self] delta in
            self?.browseLiveHero(delta: delta)
        }
        liveHeader.onToggleSlideshowRibbon = { [weak self] in
            self?.toggleLiveSlideshowRibbon()
        }
        liveHeader.onToggleScreenFit = { [weak self] in
            self?.toggleLiveScreenFit()
        }
        liveHeader.onFlipCamera = { [weak self] in
            self?.flipLiveCameraLens()
        }
        liveNoteCard.addTarget(
            self, action: #selector(handleLiveNoteTap), for: .touchUpInside
        )

        // Grid under the floating live hero so content can scroll beneath it.
        installLibraryPages()
        view.addSubview(heroSpacer)
        view.addSubview(liveHeader)
        view.addSubview(slideshowRibbonView)
        view.addSubview(liveNoteCard)
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
            self?.reloadLivePollForDisplayMode()
        }
        observe(WebPageStore.didChangeNotification) { [weak self] _ in
            self?.reloadGridIfSafe()
            self?.updateEmptyState()
        }
        observe(LocalAlbumStore.didChangeNotification) { [weak self] _ in
            self?.validateOpenShow()
            self?.revealShowMembersAddedSinceLastChange()
            self?.reloadGridIfSafe()
            self?.updateEmptyState()
            // Practice Mode (and other Show prefs) can flip the live hero on/off.
            self?.updateHeroVisibility()
            self?.applyHeroChrome()
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
        observe(MediaNoteStore.didChangeNotification) { [weak self] _ in
            self?.syncLiveNoteChrome()
        }
        observe(CountdownStore.didChangeNotification) { [weak self] _ in
            self?.reloadGridIfSafe()
            self?.refreshCountdownChrome()
        }
        observe(CountdownClockLayoutPreview.didChangeNotification) { [weak self] _ in
            self?.refreshCountdownChrome()
        }
        observe(CountdownController.didChangeNotification) { [weak self] _ in
            self?.refreshCountdownChrome()
        }
        observe(CountdownController.didExpireNotification) { [weak self] _ in
            self?.handleCountdownExpiry()
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
            // HDMI gained → this device can become director; lost → it steps down.
            self.syncShowLiveSession()
            // Hero follows a real destination or Practice Mode.
            self.updateHeroVisibility()
            self.applyHeroChrome()
            overlayReload(note)
        }
        observe(ShowLiveSession.didChangeNotification) { [weak self] note in
            self?.handleShowLiveSessionChanged(note)
        }
        observe(ShowLiveSession.incomingSelectNotification) { [weak self] note in
            self?.handleIncomingShowLiveSelect(note)
        }
        observe(ShowLiveSession.incomingCommandNotification) { [weak self] note in
            self?.handleIncomingShowLiveCommand(note)
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

    override func viewWillTransition(
        to size: CGSize,
        with coordinator: UIViewControllerTransitionCoordinator
    ) {
        super.viewWillTransition(to: size, with: coordinator)
        // Before anything reflows: the offset is still the user's, not a clamp.
        captureGridScrollAnchor()
        lastLayoutWidth = 0
        lastLayoutHeight = 0
        coordinator.animate(alongsideTransition: { [weak self] _ in
            self?.updateChromeLayoutIfNeeded()
        }, completion: { [weak self] _ in
            self?.lastLayoutWidth = 0
            self?.lastLayoutHeight = 0
            self?.updateChromeLayoutIfNeeded()
        })
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
        liveHeader.layoutCameraPreviewIfNeeded()
        // Content size is final here — pin leftover offset if the grid no longer overflows.
        updateHomeVerticalScrollPolicy()
        // Last: a turn or a covered-then-uncovered reflow puts the user back where they were.
        restoreGridScrollAnchorIfNeeded()
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
        restoreLastOpenedShowIfNeeded()
    }

    /// Reopens the most recently used Show once per process launch.
    private func restoreLastOpenedShowIfNeeded() {
        guard !Self.didAttemptRestoreLastShow else { return }
        Self.didAttemptRestoreLastShow = true
        guard !isShowMode else { return }
        let candidate = LocalAlbumStore.shared.albums
            .compactMap { album -> (LocalAlbum, Date)? in
                guard let opened = album.lastOpenedAt else { return nil }
                return (album, opened)
            }
            .max(by: { $0.1 < $1.1 })?
            .0
        guard let album = candidate else { return }
        openLocalAlbum(id: album.id)
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        // A fullscreen screen (website, camera) may turn the phone while this view is
        // off the window; the grid only meets the new size when it comes back.
        captureGridScrollAnchor()
        if store.delegate === self {
            store.delegate = nil
        }
        ExternalDisplayManager.shared.currentSourceProvider = nil
        stopHomeCameraPreviewIfNeeded()
    }
}
