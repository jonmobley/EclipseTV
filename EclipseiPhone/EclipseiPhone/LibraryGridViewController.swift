//
//  LibraryGridViewController.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

// LibraryGridViewController.swift
import UIKit
import os

/// Home: tools row (Logo / Camera / Website) + Recent Shows ribbon.
/// Opening a Show keeps this shell and swaps Recent for that Show's media grid.
/// Black is a header control. Live media still drives AirPlay / EclipseTV.
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
    /// Invoked when the Camera tile is tapped.
    var onPresentCamera: (() -> Void)?
    /// Invoked when the Logo tile needs a new image from Photos.
    var onChooseLogo: (() -> Void)?
    /// Invoked when the user wants to add media into a Show.
    var onAddMediaToAlbum: ((UUID) -> Void)?
    /// Invoked when the user wants to create a Slideshow in a Show.
    var onCreateSlideshow: ((UUID) -> Void)?
    /// Invoked when the Recent ribbon New Show tile is tapped.
    var onCreateShow: (() -> Void)?
    /// Invoked when Show mode opens/closes or the open Show's metadata changes.
    var onOpenShowChanged: ((LocalAlbum?) -> Void)?
    /// Invoked when Show-grid arrange mode starts or ends.
    var onArrangingChanged: ((Bool) -> Void)?

    let sectionInset: CGFloat = 16
    let interitemSpacing: CGFloat = 12
    private let headerInset: CGFloat = 16
    /// Black gap inserted between the hero banner and the grid below it.
    private let heroBottomPadding: CGFloat = 16
    /// Caps Vertical-mode hero height so a 9:16 frame doesn't fill the phone.
    /// Also used to height-cap Landscape heroes on wide (iPad) panes.
    private let verticalHeroMaxHeight: CGFloat = 280
    /// Last width used for hero / grid sizing; avoids redundant layout work.
    private var lastLayoutWidth: CGFloat = 0

    private var heroHeightConstraint: NSLayoutConstraint?
    private var heroWidthConstraint: NSLayoutConstraint?
    private var heroLeadingConstraint: NSLayoutConstraint?
    private var heroTrailingConstraint: NSLayoutConstraint?
    private var heroCenterXConstraint: NSLayoutConstraint?
    private var settingsObserver: NSObjectProtocol?
    private var pagesObserver: NSObjectProtocol?
    private var albumsObserver: NSObjectProtocol?
    private var slideshowsObserver: NSObjectProtocol?
    private var slideshowPlaybackObserver: NSObjectProtocol?
    private var webThumbsObserver: NSObjectProtocol?
    private var logoObserver: NSObjectProtocol?
    private var pdfsObserver: NSObjectProtocol?
    private var pdfThumbsObserver: NSObjectProtocol?

    /// True while Black is the selected presentation source.
    var isBlackSelected = false
    /// True while Logo is the selected presentation source.
    var isLogoSelected = false

    /// Open Show id while in Show mode; `nil` means Home (Recent ribbon).
    var openShowId: UUID?
    /// True while the user is dragging Show items to rearrange them.
    var isArranging = false
    /// Working copy of the library order used while arranging and until the Apple TV
    /// confirms the saved order with a fresh manifest. `nil` means show `store.items`.
    var arrangeItems: [LibraryItemDTO]?

    /// Long-press recognizer that drives interactive reordering; only active while
    /// arranging.
    lazy var reorderGesture: UILongPressGestureRecognizer = {
        let gesture = UILongPressGestureRecognizer(target: self, action: #selector(handleReorderGesture(_:)))
        gesture.isEnabled = false
        return gesture
    }()

    /// Media slice only (arrange working copy or mirrored TV order).
    var displayItems: [LibraryItemDTO] { arrangeItems ?? store.items }

    /// Open Show when in Show mode.
    var openShow: LocalAlbum? {
        guard let openShowId else { return nil }
        return LocalAlbumStore.shared.album(id: openShowId)
    }

    /// True when a Show replaces the Recent ribbon.
    var isShowMode: Bool { openShowId != nil }

    /// Media belonging to the open Show (resolved against the library store).
    var openShowItems: [LibraryItemDTO] {
        guard let album = openShow else { return [] }
        return album.itemIds.compactMap { id in
            store.items.first(where: { $0.id == id })
        }
    }

    /// Slideshows belonging to the open Show.
    var openShowSlideshows: [Slideshow] {
        guard let openShowId else { return [] }
        return SlideshowStore.shared.slideshows(forShowId: openShowId)
    }

    /// Show-grid rows: slideshows, then media, or a single Add tile when empty.
    var openShowGridItems: [ShowGridItem] {
        guard isShowMode else { return [] }
        if showsShowAddTile { return [.add] }
        let shows = openShowSlideshows.map { ShowGridItem.slideshow($0) }
        let media = openShowItems.map { ShowGridItem.media($0) }
        return shows + media
    }

    /// Empty Show (no media, no slideshows) shows a single Add tile (unless arranging).
    var showsShowAddTile: Bool {
        isShowMode
            && openShowItems.isEmpty
            && openShowSlideshows.isEmpty
            && !isArranging
    }

    /// Live slideshow ribbon is on for the open Show's active slideshow.
    var showsLiveSlideshowRibbon: Bool {
        guard isShowMode,
              let id = SlideshowPlaybackController.shared.activeSlideshowId,
              let show = SlideshowStore.shared.slideshow(id: id),
              show.showId == openShowId,
              show.showRibbonWhenLive else { return false }
        return !SlideshowPlaybackController.shared.activeSlideIds.isEmpty
    }

    /// Layout sections for the current mode (tools, optional ribbon, shows).
    var visibleHomeSections: [HomeSection] {
        Self.visibleHomeSections(
            isShowMode: isShowMode,
            showsSlideshowRibbon: showsLiveSlideshowRibbon
        )
    }

    /// Collection-view section index for `section`, if currently visible.
    func sectionIndex(for section: HomeSection) -> Int? {
        visibleHomeSections.firstIndex(of: section)
    }

    /// Home section at a collection-view section index.
    func homeSection(at section: Int) -> HomeSection? {
        guard visibleHomeSections.indices.contains(section) else { return nil }
        return visibleHomeSections[section]
    }

    /// Fixed tools row (Logo / Camera / Website).
    var toolItems: [HomeGridItem] { HomeGridItem.tools }

    /// Horizontally scrolling Recent Shows (+ New Show).
    var showRibbonItems: [HomeGridItem] {
        HomeGridItem.recentShows(from: LocalAlbumStore.shared.albumsForCurrentMode)
    }

    /// Count of Logo + Camera + Website.
    var pinnedItemCount: Int { HomeGridItem.specialCount }

    /// Fired when Black live chrome should update (e.g. header button).
    var onBlackLiveChanged: ((Bool) -> Void)?

    /// Extra bottom inset reserved for the home mini player.
    var miniPlayerBottomInset: CGFloat = 0 {
        didSet {
            guard miniPlayerBottomInset != oldValue else { return }
            collectionView.contentInset.bottom = miniPlayerBottomInset + sectionInset
            collectionView.verticalScrollIndicatorInsets.bottom = miniPlayerBottomInset
        }
    }

    func homeItem(at indexPath: IndexPath) -> HomeGridItem? {
        guard let section = homeSection(at: indexPath.section) else { return nil }
        switch section {
        case .tools:
            guard toolItems.indices.contains(indexPath.item) else { return nil }
            return toolItems[indexPath.item]
        case .slideshowRibbon:
            return nil
        case .shows:
            guard showRibbonItems.indices.contains(indexPath.item) else { return nil }
            return showRibbonItems[indexPath.item]
        }
    }

    func displayItem(at index: Int) -> LibraryItemDTO? {
        let items = displayItems
        guard index >= 0 && index < items.count else { return nil }
        return items[index]
    }

    private let liveHeader: LiveHeaderView = {
        let header = LiveHeaderView()
        header.translatesAutoresizingMaskIntoConstraints = false
        return header
    }()

    /// Solid black padding strip below the hero banner, separating it from the grid.
    private let heroSpacer: UIView = {
        let view = UIView()
        view.backgroundColor = .black
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    lazy var collectionView: UICollectionView = {
        let layout = Self.makeHomeLayout(
            sectionInset: sectionInset,
            spacing: interitemSpacing,
            isShowMode: false,
            showsSlideshowRibbon: false
        )
        let view = UICollectionView(frame: .zero, collectionViewLayout: layout)
        view.backgroundColor = .systemBackground
        view.alwaysBounceVertical = true
        view.register(
            LibraryThumbnailCell.self,
            forCellWithReuseIdentifier: LibraryThumbnailCell.reuseIdentifier
        )
        view.register(
            HomeSectionHeaderView.self,
            forSupplementaryViewOfKind: UICollectionView.elementKindSectionHeader,
            withReuseIdentifier: HomeSectionHeaderView.reuseIdentifier
        )
        view.dataSource = self
        view.delegate = self
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    private let emptyLabel: UILabel = {
        let label = UILabel()
        label.textColor = .secondaryLabel
        label.font = .preferredFont(forTextStyle: .footnote)
        label.adjustsFontForContentSizeCategory = true
        label.textAlignment = .center
        label.numberOfLines = 0
        label.isHidden = true
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    private var emptyTopConstraint: NSLayoutConstraint?

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

        liveHeader.onTogglePlayPause = { [weak self] in
            self?.connectionManager.sendPlaybackCommand(action: .toggle, position: nil)
        }
        liveHeader.onSkip = { [weak self] delta in
            self?.connectionManager.sendPlaybackCommand(action: .skip, position: delta)
        }
        liveHeader.onSeek = { [weak self] position in
            self?.connectionManager.sendPlaybackCommand(action: .seek, position: position)
        }

        collectionView.addGestureRecognizer(reorderGesture)

        view.addSubview(liveHeader)
        view.addSubview(heroSpacer)
        view.addSubview(collectionView)
        view.addSubview(emptyLabel)

        let safeArea = view.safeAreaLayoutGuide
        let heroTop = liveHeader.topAnchor.constraint(
            equalTo: safeArea.topAnchor, constant: headerInset)
        let heroLeading = liveHeader.leadingAnchor.constraint(
            equalTo: view.leadingAnchor, constant: headerInset)
        let heroTrailing = liveHeader.trailingAnchor.constraint(
            equalTo: view.trailingAnchor, constant: -headerInset)
        let heroCenterX = liveHeader.centerXAnchor.constraint(equalTo: view.centerXAnchor)
        heroCenterX.isActive = false
        let heroWidth = liveHeader.widthAnchor.constraint(equalToConstant: 160)
        heroWidth.isActive = false
        let heroHeight = liveHeader.heightAnchor.constraint(
            equalTo: liveHeader.widthAnchor, multiplier: 9.0 / 16.0)

        heroLeadingConstraint = heroLeading
        heroTrailingConstraint = heroTrailing
        heroCenterXConstraint = heroCenterX
        heroWidthConstraint = heroWidth
        heroHeightConstraint = heroHeight

        NSLayoutConstraint.activate([
            heroTop,
            heroLeading,
            heroTrailing,
            heroHeight,

            heroSpacer.topAnchor.constraint(equalTo: liveHeader.bottomAnchor),
            heroSpacer.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            heroSpacer.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            heroSpacer.heightAnchor.constraint(equalToConstant: heroBottomPadding),

            collectionView.topAnchor.constraint(equalTo: heroSpacer.bottomAnchor),
            collectionView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            collectionView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            collectionView.trailingAnchor.constraint(equalTo: view.trailingAnchor),

            emptyLabel.centerXAnchor.constraint(equalTo: collectionView.centerXAnchor),
            emptyLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 40),
            emptyLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -40)
        ])
        let emptyTop = emptyLabel.topAnchor.constraint(
            equalTo: collectionView.topAnchor, constant: 160
        )
        emptyTop.isActive = true
        emptyTopConstraint = emptyTop

        applyLayoutMode()
        settingsObserver = NotificationCenter.default.addObserver(
            forName: ExternalOutputSettings.didChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.applyLayoutMode()
            self?.validateOpenShow()
        }
        pagesObserver = NotificationCenter.default.addObserver(
            forName: WebPageStore.didChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.collectionView.reloadData()
            self?.updateEmptyState()
        }
        albumsObserver = NotificationCenter.default.addObserver(
            forName: LocalAlbumStore.didChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.validateOpenShow()
            self?.collectionView.reloadData()
            self?.updateEmptyState()
        }
        slideshowsObserver = NotificationCenter.default.addObserver(
            forName: SlideshowStore.didChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.refreshSlideshowRibbonPresentation()
            self?.collectionView.reloadData()
            self?.updateEmptyState()
        }
        slideshowPlaybackObserver = NotificationCenter.default.addObserver(
            forName: SlideshowPlaybackController.didChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.refreshSlideshowRibbonPresentation()
            self?.collectionView.reloadData()
            self?.refreshLiveHeader()
            self?.scrollLiveSlideshowRibbonToCurrentSlide()
        }
        webThumbsObserver = NotificationCenter.default.addObserver(
            forName: WebThumbnailStore.didChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.collectionView.reloadData()
            self?.refreshLiveHeader()
        }
        logoObserver = NotificationCenter.default.addObserver(
            forName: LogoStore.didChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.collectionView.reloadData()
            self?.refreshLiveHeader()
        }
        pdfsObserver = NotificationCenter.default.addObserver(
            forName: PDFStore.didChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.collectionView.reloadData()
            self?.updateEmptyState()
        }
        pdfThumbsObserver = NotificationCenter.default.addObserver(
            forName: PDFThumbnailStore.didChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.collectionView.reloadData()
            self?.refreshLiveHeader()
        }
        NotificationCenter.default.addObserver(
            forName: CameraManager.lastFrameDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.reloadCameraTile()
        }
        let overlayReload: (Notification) -> Void = { [weak self] _ in
            self?.collectionView.reloadData()
            self?.refreshLiveHeader()
        }
        NotificationCenter.default.addObserver(
            forName: ExternalDisplayManager.didChangeNotification,
            object: nil,
            queue: .main,
            using: overlayReload
        )
        NotificationCenter.default.addObserver(
            forName: ExternalDisplayManager.cameraDidEndNotification,
            object: nil,
            queue: .main,
            using: overlayReload
        )
        NotificationCenter.default.addObserver(
            forName: ExternalDisplayManager.webDidEndNotification,
            object: nil,
            queue: .main,
            using: overlayReload
        )
        NotificationCenter.default.addObserver(
            forName: ExternalDisplayManager.pdfDidEndNotification,
            object: nil,
            queue: .main,
            using: overlayReload
        )
        NotificationCenter.default.addObserver(
            forName: ExternalDisplayManager.didApplyCameraCloseDestinationNotification,
            object: nil,
            queue: .main
        ) { [weak self] note in
            self?.applyCameraCloseDestination(from: note)
        }
    }

    /// Syncs Black / Logo home selection after Close applies a camera-close setting.
    private func applyCameraCloseDestination(from note: Notification) {
        let raw = note.userInfo?["destination"] as? String
        let destination = raw.flatMap(CameraCloseDestination.init(rawValue:))
        switch destination {
        case .logo:
            isBlackSelected = false
            isLogoSelected = true
        case .black:
            isBlackSelected = true
            isLogoSelected = false
        case .camera, .none:
            return
        }
        collectionView.reloadData()
        refreshLiveHeader()
    }

    deinit {
        if let settingsObserver {
            NotificationCenter.default.removeObserver(settingsObserver)
        }
        if let pagesObserver {
            NotificationCenter.default.removeObserver(pagesObserver)
        }
        if let albumsObserver {
            NotificationCenter.default.removeObserver(albumsObserver)
        }
        if let slideshowsObserver {
            NotificationCenter.default.removeObserver(slideshowsObserver)
        }
        if let slideshowPlaybackObserver {
            NotificationCenter.default.removeObserver(slideshowPlaybackObserver)
        }
        if let webThumbsObserver {
            NotificationCenter.default.removeObserver(webThumbsObserver)
        }
        if let logoObserver {
            NotificationCenter.default.removeObserver(logoObserver)
        }
        if let pdfsObserver {
            NotificationCenter.default.removeObserver(pdfsObserver)
        }
        if let pdfThumbsObserver {
            NotificationCenter.default.removeObserver(pdfThumbsObserver)
        }
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        let width = view.bounds.width
        guard width > 0, abs(width - lastLayoutWidth) > 0.5 else { return }
        lastLayoutWidth = width
        applyHeroChrome()
        collectionView.collectionViewLayout.invalidateLayout()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        store.delegate = self
        // Let the external display ask for the live item if it connects mid-session.
        ExternalDisplayManager.shared.currentSourceProvider = { [weak self] in
            self?.currentPresentationSource()
        }
        collectionView.reloadData()
        updateEmptyState()
        refreshLiveHeader()
        pushCurrentToExternalDisplay()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        if store.delegate === self {
            store.delegate = nil
        }
        ExternalDisplayManager.shared.currentSourceProvider = nil
    }

    // MARK: - Helpers

    func updateEmptyState() {
        // Show mode owns its empty Add tile; Home only hints about the other mode.
        guard !isShowMode else {
            emptyLabel.isHidden = true
            return
        }
        let hasShows = !LocalAlbumStore.shared.albumsForCurrentMode.isEmpty
        if !hasShows, store.inactiveModeHasContent() {
            let other = ExternalOutputSettings.isVerticalMode ? "Landscape" : "Vertical"
            emptyLabel.text =
                "No Shows in \(ExternalOutputSettings.orientation.rawValue) yet.\nYour content may be under \(other) in Settings → Display Mode."
            emptyLabel.isHidden = false
            let rowHeight = itemSize(for: collectionView.bounds.width).height
            emptyTopConstraint?.constant = sectionInset + rowHeight + 100
        } else {
            emptyLabel.isHidden = true
        }
    }

    /// Rebuilds the compositional layout for Home ribbon vs Show grid.
    func applyCollectionLayout() {
        let layout = Self.makeHomeLayout(
            sectionInset: sectionInset,
            spacing: interitemSpacing,
            isShowMode: isShowMode,
            showsSlideshowRibbon: showsLiveSlideshowRibbon
        )
        collectionView.setCollectionViewLayout(layout, animated: false)
    }

    /// Reloads only the Camera tile (live preview / last-frame updates).
    func reloadCameraTile() {
        guard let toolsSection = sectionIndex(for: .tools) else { return }
        let indexPath = IndexPath(item: 1, section: toolsSection)
        guard toolItems.indices.contains(1),
              case .camera = toolItems[1],
              collectionView.indexPathsForVisibleItems.contains(indexPath) else {
            return
        }
        collectionView.reloadItems(at: [indexPath])
    }

    /// Updates the fixed hero banner to reflect the currently live item (or a placeholder).
    func refreshLiveHeader() {
        let mgr = ExternalDisplayManager.shared
        let blackLive = isBlackSelected && !mgr.isOverlayLive
        onBlackLiveChanged?(blackLive)
        if mgr.isWebLive {
            let page = WebPageStore.shared.pages
                .first(where: { $0.id == mgr.liveWebPageId })
            let title = page?.title ?? "Website"
            let thumb = mgr.liveWebPageId.flatMap {
                WebThumbnailStore.shared.image(for: $0)
            }
            liveHeader.configureOverlay(
                title: title,
                systemImage: "safari",
                fillColor: UIColor(white: 0.12, alpha: 1),
                thumbnail: thumb
            )
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
            liveHeader.updatePlayback(PlaybackState())
            return
        }
        if isBlackSelected {
            liveHeader.configureOverlay(
                title: "Black",
                systemImage: nil,
                fillColor: .black
            )
            liveHeader.updatePlayback(PlaybackState())
            return
        }
        if isLogoSelected {
            liveHeader.configureOverlay(
                title: "Logo",
                systemImage: "seal.fill",
                fillColor: UIColor(white: 0.12, alpha: 1),
                thumbnail: LogoStore.shared.image
            )
            liveHeader.updatePlayback(PlaybackState())
            return
        }

        let liveItem = store.currentId.flatMap { id in
            store.items.first(where: { $0.id == id })
        }
        let thumbnail = liveItem.flatMap { store.thumbnail(for: $0.id) }
        liveHeader.configure(with: liveItem, thumbnail: thumbnail, isOnline: store.isOnline)
        liveHeader.updatePlayback(store.playback)
    }

    // MARK: - External Display

    /// The presentation source for the currently live item, or nil when nothing is live.
    /// Used by `ExternalDisplayManager` when a display connects mid-session.
    /// Returns the active overlay (camera / web) when one is live.
    func currentPresentationSource() -> PresentationSource? {
        switch ExternalDisplayManager.shared.overlaySource {
        case .camera:
            return .camera
        case .web(let url):
            return .web(url)
        case .pdf(let url):
            return .pdf(url)
        case .none:
            break
        }
        if isBlackSelected {
            return .black
        }
        if isLogoSelected, let url = LogoStore.shared.fileURL {
            return .image(url)
        }
        guard let id = store.currentId,
              let item = store.items.first(where: { $0.id == id }) else { return nil }
        return .forLibraryItem(item, thumbnail: store.thumbnail(for: id))
    }

    /// Pushes the currently live item to the external display (if one is connected).
    /// Does not interrupt an active camera/web overlay or a sticky joined presentation.
    private func pushCurrentToExternalDisplay() {
        guard ExternalDisplayManager.shared.isConnected else { return }
        guard !ExternalDisplayManager.shared.isOverlayLive else { return }
        guard !ExternalDisplayManager.shared.isJoinedLive else { return }
        if let source = currentPresentationSource() {
            ExternalDisplayManager.shared.present(source)
        } else {
            ExternalDisplayManager.shared.clear()
        }
    }

    /// Clears home-grid live selection when a joined album item becomes the live output.
    func clearLiveSelectionForJoinedPresent() {
        isBlackSelected = false
        isLogoSelected = false
        store.updateCurrentId(nil)
        collectionView.reloadData()
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
                let gridIndex = pinnedItemCount + index
                let anchor = collectionView.cellForItem(at: IndexPath(item: gridIndex, section: 0)) ?? view
                popover.sourceView = anchor
                popover.sourceRect = anchor?.bounds ?? view.bounds
            }
            present(sheet, animated: true)
            return
        }

        sheet.addAction(UIAlertAction(title: "Make Live", style: .default) { [weak self] _ in
            self?.runCommand { self?.connectionManager.sendPlayRequest(id: id) ?? false }
        })

        if item.isVideo {
            let loopOn = item.isLooping ?? false
            sheet.addAction(UIAlertAction(title: loopOn ? "Turn Loop Off" : "Turn Loop On", style: .default) { [weak self] _ in
                self?.runCommand { self?.connectionManager.sendVideoSetting(id: id, isLooping: !loopOn, isMuted: nil) ?? false }
            })

            let muted = item.isMuted ?? false
            sheet.addAction(UIAlertAction(title: muted ? "Unmute" : "Mute", style: .default) { [weak self] _ in
                self?.runCommand { self?.connectionManager.sendVideoSetting(id: id, isLooping: nil, isMuted: !muted) ?? false }
            })
        }

        sheet.addAction(UIAlertAction(title: "Delete", style: .destructive) { [weak self] _ in
            self?.confirmDelete(id: id, name: item.name)
        })

        sheet.addAction(UIAlertAction(title: "Cancel", style: .cancel))

        // iPad requires a popover anchor.
        if let popover = sheet.popoverPresentationController {
            let gridIndex = pinnedItemCount + index
            let indexPath = IndexPath(item: gridIndex, section: 0)
            let anchor = collectionView.cellForItem(at: indexPath) ?? view
            popover.sourceView = anchor
            popover.sourceRect = anchor?.bounds ?? view.bounds
        }

        present(sheet, animated: true)
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

    /// Applies Landscape vs Vertical chrome and reloads the active mode's library.
    private func applyLayoutMode() {
        // TVLibraryStore also observes this notification and swaps buckets first.
        store.syncLibraryModeFromSettings()
        applyHeroChrome()
        collectionView.collectionViewLayout.invalidateLayout()
        collectionView.reloadData()
    }

    /// Sizes the live hero for Vertical (always capped) or Landscape (full-bleed /
    /// capped on wide panes).
    private func applyHeroChrome() {
        if ExternalOutputSettings.isVerticalMode {
            applyCappedHero(aspectWidthOverHeight: 9.0 / 16.0)
            return
        }
        let bleedWidth = max(0, view.bounds.width - headerInset * 2)
        let bleedHeight = bleedWidth * 9.0 / 16.0
        if bleedHeight > verticalHeroMaxHeight + 0.5 {
            applyCappedHero(aspectWidthOverHeight: 16.0 / 9.0)
        } else {
            applyFullBleedLandscapeHero()
        }
    }

    /// Centers a fixed-height hero (Vertical always; Landscape on wide panes).
    private func applyCappedHero(aspectWidthOverHeight: CGFloat) {
        heroLeadingConstraint?.isActive = false
        heroTrailingConstraint?.isActive = false
        heroCenterXConstraint?.isActive = true
        heroWidthConstraint?.isActive = true
        let height = verticalHeroMaxHeight
        let width = (height * aspectWidthOverHeight).rounded(.down)
        heroWidthConstraint?.constant = width
        heroHeightConstraint?.isActive = false
        let heightConstraint = liveHeader.heightAnchor.constraint(equalToConstant: height)
        heightConstraint.isActive = true
        heroHeightConstraint = heightConstraint
    }

    /// Pins Landscape hero leading/trailing with a 16:9 height.
    private func applyFullBleedLandscapeHero() {
        heroCenterXConstraint?.isActive = false
        heroWidthConstraint?.isActive = false
        heroLeadingConstraint?.isActive = true
        heroTrailingConstraint?.isActive = true
        heroHeightConstraint?.isActive = false
        let aspect = liveHeader.heightAnchor.constraint(
            equalTo: liveHeader.widthAnchor, multiplier: 9.0 / 16.0)
        aspect.isActive = true
        heroHeightConstraint = aspect
    }
}

// MARK: - TVLibraryStoreDelegate

extension LibraryGridViewController: TVLibraryStoreDelegate {
    func libraryStoreDidUpdateItems(_ store: TVLibraryStore) {
        // While actively dragging, keep the working order; it reconciles on finish.
        guard !isArranging else { return }
        // A fresh manifest from the TV confirms any just-saved arrangement.
        arrangeItems = nil
        collectionView.reloadData()
        updateEmptyState()
        refreshLiveHeader()
    }

    func libraryStoreDidUpdateCurrent(_ store: TVLibraryStore) {
        if store.currentId != nil {
            isBlackSelected = false
            isLogoSelected = false
        }
        refreshLiveHeader()
        pushCurrentToExternalDisplay()
        guard !isArranging else { return }
        collectionView.reloadData()
    }

    func libraryStore(_ store: TVLibraryStore, didUpdateThumbnailFor id: String) {
        if id == store.currentId {
            refreshLiveHeader()
        }
        guard !isArranging else { return }
        guard let showsSection = sectionIndex(for: .shows) else { return }
        if isShowMode {
            var paths: [IndexPath] = []
            if let ribbonSection = sectionIndex(for: .slideshowRibbon),
               let ribbonIndex = SlideshowPlaybackController.shared.activeSlideIds
                .firstIndex(of: id) {
                let path = IndexPath(item: ribbonIndex, section: ribbonSection)
                if collectionView.indexPathsForVisibleItems.contains(path) {
                    paths.append(path)
                }
            }
            if let mediaIndex = openShowItems.firstIndex(where: { $0.id == id }) {
                let item = openShowSlideshows.count + mediaIndex
                let path = IndexPath(item: item, section: showsSection)
                if collectionView.indexPathsForVisibleItems.contains(path) {
                    paths.append(path)
                }
            }
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
        refreshLiveHeader()
    }

    func libraryStoreDidUpdatePlayback(_ store: TVLibraryStore) {
        liveHeader.updatePlayback(store.playback)
    }
}
