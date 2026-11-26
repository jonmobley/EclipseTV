//
//  iPhoneMainViewController+HomePaging.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import UIKit

// MARK: - Home Pager (Home | Library | Show | Music)

extension iPhoneMainViewController: UIScrollViewDelegate {

    /// Embeds Library and Music in the home pager (split or drawer on regular width).
    func embedHomePager() {
        homePagerScrollView.delegate = self
        view.addSubview(homePagerScrollView)

        let topToHeader = homePagerScrollView.topAnchor.constraint(equalTo: headerBar.bottomAnchor)
        let topToSafeArea = homePagerScrollView.topAnchor.constraint(
            equalTo: view.safeAreaLayoutGuide.topAnchor
        )
        homePagerTopToHeaderConstraint = topToHeader
        homePagerTopToSafeAreaConstraint = topToSafeArea
        // Compact default: full-height pager so Music is laid out under the status
        // bar from the first frame (no post-swipe jump when the header hides).
        topToHeader.isActive = false

        // Side edges follow the safe area so both pages clear the Dynamic Island in
        // landscape. Insetting the pager rather than its pages is what makes this
        // stable: UIKit's own safe-area forwarding into a paging scroll view depends
        // on each page's position in the content, so the Library page was handed the
        // left inset but never the right one.
        NSLayoutConstraint.activate([
            topToSafeArea,
            homePagerScrollView.leadingAnchor.constraint(
                equalTo: view.safeAreaLayoutGuide.leadingAnchor
            ),
            homePagerScrollView.trailingAnchor.constraint(
                equalTo: view.safeAreaLayoutGuide.trailingAnchor
            ),
            homePagerScrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])

        embedLibraryPage()
        embedLibraryTabPage()
        embedShowPlaceholder()
        embedMusicPage()
        // Header sits above the pager; Music drawer / bubble re-assert after.
        raiseHomeOverlayChrome()
        applyHomePagerTopAttachment()
        updateHomeSplitLayoutIfNeeded()
        updateHomeChromeForCurrentPage()
    }

    /// Reveals Music: drawer on regular width, pager page when compact.
    func showMusicPage(animated: Bool = true) {
        if isMusicInDrawer {
            musicDrawer.setOpen(true, animated: animated)
            return
        }
        guard !isHomeSplitLayout else { return }
        setHomeTab(.music, animated: animated)
    }

    /// Back to the Home / Show grid: closes the drawer, or pages to the grid's slot.
    func showGridPage(animated: Bool = true) {
        if isMusicInDrawer {
            musicDrawer.setOpen(false, animated: animated)
            return
        }
        guard !isHomeSplitLayout else { return }
        setHomeTab(gridTab, animated: animated)
    }

    /// The slot the grid stands in: Show while a Show is open, else Home.
    var gridTab: HomeTab {
        libraryViewController.isShowMode ? .show : .home
    }

    /// A text tab was tapped.
    ///
    /// The current tab acts on its own page: Show offers the Shows list (as the
    /// iPad Show tab does) and Music returns from a playlist to the list.
    func selectHomeTab(_ tab: HomeTab) {
        guard isHomeTabPaging else { return }
        let settled = !homePagerScrollView.isDragging
            && !homePagerScrollView.isDecelerating
            && !isAnimatingHomePager
        guard tab == homeTab, settled else {
            setHomeTab(tab, animated: true)
            return
        }
        switch tab {
        case .show:
            libraryViewController.presentAllShows()
        case .music:
            audioLibraryNavController?.popToRootViewController(animated: true)
        case .home, .library:
            break
        }
    }

    /// Ends a tab's slide at once, on its page.
    func finishHomePagerSlide() {
        guard isHomeTabPaging, isAnimatingHomePager else { return }
        isAnimatingHomePager = false
        let width = homePagerScrollView.bounds.width
        homePagerScrollView.setContentOffset(
            CGPoint(x: CGFloat(homeTab.rawValue) * width, y: 0), animated: false
        )
        homeTabDidSettle()
    }

    // MARK: - Search (Library, Show, Music)

    /// Opens the header's search field for the page in front.
    func beginPageSearch() {
        guard isHomeTabPaging, searchingTab == nil else { return }
        finishHomePagerSlide()
        let placeholder: String
        switch homeTab {
        case .library: placeholder = "Search Library"
        case .show:
            guard libraryViewController.isShowMode else { return }
            placeholder = "Search this Show"
        case .music: placeholder = "Search Music"
        case .home: return
        }
        searchingTab = homeTab
        headerBar.beginSearch(placeholder: placeholder)
        animateHeaderHeightChange()
    }

    /// Filters the page being searched as the text changes.
    func applyPageSearch(_ text: String) {
        switch searchingTab {
        case .library: libraryPagePicker?.setHomeTabSearchQuery(text)
        case .show: libraryViewController.setShowSearchQuery(text)
        case .music: audioLibraryViewController.searchQuery = text
        case .home, nil: break
        }
    }

    /// Closes the search field and shows the whole page again.
    ///
    /// Also runs when the page changes or the Show does: a filter left on a page
    /// nobody is looking at would hide cards with nothing on screen to say why.
    func endPageSearch(animated: Bool = true) {
        guard searchingTab != nil else { return }
        searchingTab = nil
        libraryPagePicker?.setHomeTabSearchQuery("")
        libraryViewController.setShowSearchQuery("")
        audioLibraryViewController.searchQuery = ""
        headerBar.endSearch()
        if animated {
            animateHeaderHeightChange()
        } else {
            applyHomePagerTopAttachment()
        }
    }

    private func animateHeaderHeightChange() {
        guard view.window != nil, !UIAccessibility.isReduceMotionEnabled else {
            applyHomePagerTopAttachment()
            return
        }
        UIView.animate(
            withDuration: 0.22,
            delay: 0,
            options: [.curveEaseInOut, .beginFromCurrentState]
        ) {
            self.applyHomePagerTopAttachment()
            self.view.layoutIfNeeded()
        }
    }

    /// Locks paging while arranging media; snaps back to Library when paged.
    func setHomePagingEnabled(_ enabled: Bool) {
        if !enabled {
            if !isHomeSplitLayout {
                showGridPage(animated: true)
            }
            homePagerScrollView.isScrollEnabled = false
            return
        }
        refreshHomePagerScrollEnabled()
    }

    /// Switches among compact paging and the Music drawer on regular width.
    func updateHomeSplitLayoutIfNeeded() {
        let width = homePagerScrollView.bounds.width
        guard width > 0 else { return }
        applyHomePageWidths(forTotalWidth: width)
    }

    /// Applies Library/Music page widths for `totalWidth` (pager bounds or transition size).
    ///
    /// Called from layout and from `viewWillTransition` with the destination width so a
    /// phone turn doesn't leave the portrait page width stuck — that kept Vertical at
    /// 3-up with a dead band of black beside the grid.
    @discardableResult
    func applyHomePageWidths(forTotalWidth width: CGFloat) -> Bool {
        guard width > 0 else { return false }

        let mode = HomeMusicLayout.mode(
            horizontalSizeClass: traitCollection.horizontalSizeClass,
            pinned: isMusicSidebarPinned
        )
        musicDrawer.panelWidth = HomeMusicLayout.sidebarWidth(for: width)

        let wantSplit = mode == .split
        let musicWidth = wantSplit
            ? HomeMusicLayout.sidebarWidth(for: width) : width
        let libraryWidth = wantSplit ? width - musicWidth : width

        let splitChanged = wantSplit != isHomeSplitLayout
        let libraryWidthChanged =
            abs((libraryPageWidthConstraint?.constant ?? -1) - libraryWidth) > 0.5
        let musicWidthChanged = mode != .drawer && abs(
            (musicPageWidthConstraint?.constant ?? -1) - musicWidth
        ) > 0.5
        let hostNeedsUpdate =
            (mode == .drawer) != isMusicInDrawer
            || audioLibraryNavController?.view.superview == nil
        guard splitChanged || libraryWidthChanged || musicWidthChanged
                || hostNeedsUpdate else {
            return false
        }

        isHomeSplitLayout = wantSplit
        libraryPageWidthConstraint?.constant = libraryWidth
        if mode != .drawer {
            musicPageWidthConstraint?.constant = musicWidth
        }

        let wasTabPaging = isHomeTabPaging
        isHomeTabPaging = mode == .paging
        homePagerScrollView.isPagingEnabled = mode == .paging
        updateMusicHost(for: mode)
        applyTabPageGeometry(pageWidth: libraryWidth)
        applyHomePagerTopAttachment()
        if wasTabPaging != isHomeTabPaging {
            // The menu's title and entries depend on whether the tabs show.
            refreshLibraryMenu()
            if !isHomeTabPaging { endPageSearch(animated: false) }
        }
        if mode != .paging {
            homePagerScrollView.contentOffset = .zero
            homePagerScrollView.isScrollEnabled = false
        } else {
            if !wasTabPaging {
                // Arriving from the drawer layout (iPad window made narrow, a big
                // phone turned upright): start on the grid's own page.
                homeTab = gridTab
                headerBar.tabStrip.setSelected(homeTab, animated: false)
                headerBar.setTabPage(homeTab)
            }
            refreshHomePagerScrollEnabled()
            syncHomePagerOffsetIfNeeded()
        }

        updateHomeChromeForCurrentPage()
        if splitChanged || libraryWidthChanged {
            libraryViewController.invalidatePageLayouts()
        }
        return true
    }

    /// Keeps the current page aligned after rotation / bounds changes.
    func syncHomePagerOffsetIfNeeded() {
        guard !isHomeSplitLayout, !isMusicInDrawer else {
            if homePagerScrollView.contentOffset.x != 0 {
                homePagerScrollView.contentOffset = .zero
            }
            return
        }
        // Never fight an in-flight page swipe (layout from header chrome used to
        // snap offset back to `homeTab` and leave the pager stuck mid-page).
        // A tab's slide is in flight too: snapping to its end here made the
        // animation carry on past the page.
        guard !homePagerScrollView.isDragging,
              !homePagerScrollView.isDecelerating,
              !isAnimatingHomePager
        else {
            return
        }
        let width = homePagerScrollView.bounds.width
        guard width > 0 else { return }
        let expected = CGFloat(homeTab.rawValue) * width
        if abs(homePagerScrollView.contentOffset.x - expected) > 0.5 {
            homePagerScrollView.contentOffset = CGPoint(x: expected, y: 0)
        }
    }

    // MARK: - UIScrollViewDelegate

    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        guard scrollView === homePagerScrollView else { return }
        // Horizontal pager only — never let a whole page ride vertically under
        // the fixed header.
        if abs(scrollView.contentOffset.y) > 0.5 {
            scrollView.contentOffset.y = 0
        }
        guard isHomeTabPaging else { return }
        // Only a swipe or a tab's slide moves things. Layout also sets the offset
        // (a turn of the phone passes through in-between widths), and that must
        // never be read as a swipe towards Home that closes the Show.
        let byFinger = scrollView.isTracking || scrollView.isDragging
            || scrollView.isDecelerating
        guard byFinger || isAnimatingHomePager else { return }
        let width = scrollView.bounds.width
        guard width > 0 else { return }
        let position = scrollView.contentOffset.x / width
        headerBar.tabStrip.setPosition(position)
        // Only a finger changes the grid between Home and Show on the way. A tab's
        // slide put the grid where it is going before it started.
        guard byFinger else { return }
        headerBar.setTabPage(HomeTabPaging.nearestTab(toPosition: position))
        if let slot = HomeTabPaging.visibleGridSlot(atPosition: position) {
            moveGrid(into: slot)
        }
    }

    func scrollViewWillBeginDragging(_ scrollView: UIScrollView) {
        guard scrollView === homePagerScrollView else { return }
        // A finger takes over from a tab's slide.
        isAnimatingHomePager = false
    }

    func scrollViewDidEndDragging(
        _ scrollView: UIScrollView,
        willDecelerate decelerate: Bool
    ) {
        guard scrollView === homePagerScrollView,
              !isHomeSplitLayout,
              !isMusicInDrawer else { return }
        if !decelerate {
            updateHomePageIndexFromOffset()
        }
    }

    func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) {
        guard scrollView === homePagerScrollView,
              !isHomeSplitLayout,
              !isMusicInDrawer else { return }
        updateHomePageIndexFromOffset()
    }

    func scrollViewDidEndScrollingAnimation(_ scrollView: UIScrollView) {
        guard scrollView === homePagerScrollView else { return }
        isAnimatingHomePager = false
        guard isHomeTabPaging else { return }
        // A tab's slide ends on the tab that was tapped, whatever the offset says
        // at this instant: read from the offset, a slide cut short by something
        // else (the search field taking focus) left the tabs on one page and the
        // screen on another.
        syncHomePagerOffsetIfNeeded()
        homeTabDidSettle()
    }

    // MARK: - Private

    /// Paging stays on except while arranging, selecting, split, drawer, or on the
    /// Show page in phone landscape. An open playlist remains the Music page.
    func refreshHomePagerScrollEnabled() {
        let allowPaging: Bool
        if !isHomeTabPaging
            || libraryViewController.isArranging
            || libraryViewController.isSelecting {
            allowPaging = false
        } else if traitCollection.verticalSizeClass == .compact,
                  libraryViewController.isShowMode,
                  homeTab == .show {
            // Preview|grid already owns the horizontal axis in phone landscape.
            // The tabs still work, and the other pages still swipe.
            allowPaging = false
        } else {
            allowPaging = true
        }
        homePagerScrollView.isScrollEnabled = allowPaging
        // Pager owns the swipe; the playlist back button returns to Music.
        audioLibraryNavController?.interactivePopGestureRecognizer?.isEnabled =
            !allowPaging
    }

    // MARK: - Grid slot (Home / Show)

    /// The grid changed between Home and Show (or switched Shows).
    ///
    /// Moves it to its slot. When the change came from somewhere other than the
    /// pager — a Recent tile, the Shows list, Delete Show, launch restoring the last
    /// Show — the pager follows, so opening a Show lands on the Show tab and closing
    /// one lands on Home.
    func homeGridModeDidChange() {
        let isShow = libraryViewController.isShowMode
        if let id = libraryViewController.openShowId {
            lastOpenShowId = id
        }
        let changed = isShow != wasGridInShowMode
        wasGridInShowMode = isShow
        // Another Show, or none: its cards were what the search was filtering.
        if searchingTab == .show, libraryViewController.openShowId != searchedShowId {
            endPageSearch(animated: false)
        }
        searchedShowId = libraryViewController.openShowId
        placeGridInItsSlot()
        guard isHomeTabPaging, changed, !isMovingGridForPaging else { return }
        let leftBehind: HomeTab = isShow ? .home : .show
        if homeTab == leftBehind {
            setHomeTab(gridTab, animated: false)
        }
    }

    /// Puts the grid into `slot`, changing its mode to match: Home closes the open
    /// Show, Show reopens the last one. With no Show to open the grid stays put and
    /// the Show slot keeps its "No Show open" page.
    private func moveGrid(into slot: HomeTab) {
        let grid = libraryViewController
        switch slot {
        case .home where grid.isShowMode:
            isMovingGridForPaging = true
            grid.closeOpenShow()
            isMovingGridForPaging = false
        case .show where !grid.isShowMode:
            guard let id = showIdForShowTab() else { return }
            isMovingGridForPaging = true
            grid.openLocalAlbum(id: id)
            isMovingGridForPaging = false
        default:
            return
        }
    }

    /// The Show the Show tab opens when none is open.
    private func showIdForShowTab() -> UUID? {
        let store = LocalAlbumStore.shared
        let mode = ExternalOutputSettings.orientation
        return HomeTabPaging.showToOpen(
            lastOpen: lastOpenShowId.flatMap { store.album(id: $0) },
            recents: store.albums,
            isCurrentMode: { $0.orientation == mode }
        )?.id
    }

    /// Lines every page up for `pageWidth`, and the grid with its mode's slot.
    private func applyTabPageGeometry(pageWidth: CGFloat) {
        let paging = isHomeTabPaging
        libraryPageNavController?.view.isHidden = !paging
        libraryPageNavController?.hidesBarAtRoot = paging
        audioLibraryNavController?.hidesBarAtRoot = paging
        libraryTabPageWidthConstraint?.constant = pageWidth
        libraryPageLeadingConstraint?.constant =
            paging ? CGFloat(HomeTab.library.rawValue) * pageWidth : 0
        showPlaceholderWidthConstraint?.constant = pageWidth
        showPlaceholderLeadingConstraint?.constant =
            paging ? CGFloat(HomeTab.show.rawValue) * pageWidth : 0
        // Split (unused today) keeps Music beside the grid.
        musicPageLeadingConstraint?.constant =
            paging ? CGFloat(HomeTab.music.rawValue) * pageWidth : pageWidth
        placeGridInItsSlot()
    }

    private func placeGridInItsSlot() {
        let width = libraryPageWidthConstraint?.constant ?? 0
        let paging = isHomeTabPaging
        gridPageLeadingConstraint?.constant =
            paging ? CGFloat(gridTab.rawValue) * width : 0
        showPlaceholderView.isHidden = !paging || libraryViewController.isShowMode
        if !showPlaceholderView.isHidden {
            showPlaceholderView.configure(
                hasShows: !LocalAlbumStore.shared.albums.isEmpty
            )
        }
    }

    private func embedLibraryPage() {
        libraryViewController.onRequestResend = { [weak self] id in
            self?.beginResend(forItemId: id)
        }
        libraryViewController.onRequestEdit = { [weak self] id in
            self?.beginEditCrop(forItemId: id)
        }
        libraryViewController.onRequestTrim = { [weak self] id in
            self?.beginTrimVideo(forItemId: id)
        }
        libraryViewController.onRequestVideoThumbnail = { [weak self] id in
            self?.beginChangeVideoThumbnail(forItemId: id)
        }
        libraryViewController.onPresentCamera = { [weak self] in
            self?.presentCameraLive()
        }
        libraryViewController.onChooseLogo = { [weak self] in
            self?.showLogoPicker()
        }
        libraryViewController.onChooseScreensaver = { [weak self] in
            self?.showScreensaverPicker()
        }
        libraryViewController.onAddMediaToAlbum = { [weak self] albumId in
            self?.promptAddMedia(toAlbumId: albumId)
        }
        libraryViewController.onAddWebsiteToAlbum = { [weak self] albumId in
            self?.promptAddWebsite(toAlbumId: albumId)
        }
        libraryViewController.addMenuProvider = { [weak self] in
            self?.makeAddMenu() ?? UIMenu(children: [])
        }
        libraryViewController.onCreateSlideshow = { [weak self] albumId in
            self?.promptNewSlideshow(inShowId: albumId)
        }
        libraryViewController.onCreateShow = { [weak self] in
            self?.promptNewAlbum()
        }
        libraryViewController.onRequestEclipseTVConnect = { [weak self] in
            self?.resumeConnection()
        }
        libraryViewController.onOpenShowChanged = { [weak self] _ in
            self?.homeGridModeDidChange()
            self?.refreshLibraryMenu()
            self?.refreshHomePagerScrollEnabled()
        }
        libraryViewController.onShowSearchEnded = { [weak self] in
            self?.endPageSearch()
        }
        libraryViewController.onArrangingChanged = { [weak self] arranging in
            self?.headerBar.setArranging(arranging)
            self?.refreshLibraryMenu()
            self?.refreshHomePagerScrollEnabled()
        }
        libraryViewController.onSelectingChanged = { [weak self] selecting in
            guard let self else { return }
            self.headerBar.setSelecting(
                selecting,
                actionsMenu: self.libraryViewController.selectActionsMenu()
            )
            self.refreshLibraryMenu()
            self.refreshHomePagerScrollEnabled()
        }
        libraryViewController.onBlackLiveChanged = { [weak self] live in
            self?.headerBar.setBlackLive(live)
        }
        libraryViewController.onLiveOutputLockChanged = { [weak self] locked in
            self?.headerBar.setLiveLocked(locked)
        }
        libraryViewController.onLiveOutputFreezeChanged = { [weak self] frozen in
            self?.headerBar.setFrozen(frozen)
        }
        libraryViewController.onOutputBlankKindChanged = { [weak self] kind in
            self?.headerBar.setBlankKind(kind)
        }
        libraryViewController.onStatusMessage = { [weak self] message in
            self?.showPresentationToast(message)
        }

        addChild(libraryViewController)
        let gridView = libraryViewController.view!
        gridView.translatesAutoresizingMaskIntoConstraints = false
        homePagerScrollView.addSubview(gridView)
        libraryViewController.didMove(toParent: self)

        let frame = homePagerScrollView.frameLayoutGuide
        // Never start at width 0 — that fights empty-state label insets and
        // collapses the Camera tile's preview layer until the next layout pass.
        let initialWidth = max(
            homePagerScrollView.bounds.width,
            view.bounds.width,
            UIScreen.main.bounds.width
        )
        let widthConstraint = gridView.widthAnchor.constraint(equalToConstant: initialWidth)
        libraryPageWidthConstraint = widthConstraint
        let gridLeading = gridView.leadingAnchor.constraint(
            equalTo: homePagerScrollView.contentLayoutGuide.leadingAnchor
        )
        gridPageLeadingConstraint = gridLeading
        NSLayoutConstraint.activate([
            gridView.topAnchor.constraint(equalTo: homePagerScrollView.contentLayoutGuide.topAnchor),
            gridView.bottomAnchor.constraint(
                equalTo: homePagerScrollView.contentLayoutGuide.bottomAnchor
            ),
            gridLeading,
            widthConstraint,
            gridView.heightAnchor.constraint(equalTo: frame.heightAnchor)
        ])

        let trailing = gridView.trailingAnchor.constraint(
            equalTo: homePagerScrollView.contentLayoutGuide.trailingAnchor
        )
        trailing.isActive = false
        libraryTrailingToContentConstraint = trailing

        // Docked live ribbon (slideshow / Live Poll) owns horizontal
        // pans that start on it — including rubber-band at the ends — so they
        // never transfer into Library→Music paging.
        wireHomePagerToYieldToLiveRibbon()
        libraryViewController.homePagerPanToYield =
            homePagerScrollView.panGestureRecognizer
    }

    /// Pager pan waits for the docked ribbon pan and the hero browse swipes to
    /// fail before it can begin.
    ///
    /// Without the hero requirement a flick across the live preview both stepped
    /// the live item and paged over to Music, since the swipe recognizers and the
    /// pager's pan live on different views and would otherwise each recognize.
    func wireHomePagerToYieldToLiveRibbon() {
        homePagerScrollView.panGestureRecognizer.require(
            toFail: libraryViewController.slideshowRibbonView.panGestureRecognizer
        )
        for swipe in libraryViewController.liveHeader.browseSwipeRecognizers {
            homePagerScrollView.panGestureRecognizer.require(toFail: swipe)
        }
        // Dragging a zoomed still or the countdown clock on the hero must not page
        // to Music either; the drag fails at once when there is nothing to move.
        if let adjustPan = libraryViewController.liveHeader.directAdjustPan {
            homePagerScrollView.panGestureRecognizer.require(toFail: adjustPan)
        }
    }

    /// The Library page between Home and Show: browse and preview only. Adding to
    /// a Show stays on the pushed page that the Show's "+" opens.
    private func embedLibraryTabPage() {
        let picker = makeMediaLibraryPicker()
        picker.isHomeTabPage = true
        let nav = HomeTabPageNavigationController(rootViewController: picker)
        libraryPagePicker = picker
        libraryPageNavController = nav

        addChild(nav)
        let page = nav.view!
        page.translatesAutoresizingMaskIntoConstraints = false
        page.isHidden = true
        homePagerScrollView.addSubview(page)
        nav.didMove(toParent: self)

        let content = homePagerScrollView.contentLayoutGuide
        let leading = page.leadingAnchor.constraint(equalTo: content.leadingAnchor)
        let width = page.widthAnchor.constraint(equalToConstant: 320)
        let top = page.topAnchor.constraint(equalTo: content.topAnchor)
        libraryPageLeadingConstraint = leading
        libraryTabPageWidthConstraint = width
        libraryPageTopConstraint = top
        NSLayoutConstraint.activate([
            leading, width, top,
            page.bottomAnchor.constraint(equalTo: content.bottomAnchor)
        ])
    }

    /// "No Show open", under the grid in the Show slot.
    private func embedShowPlaceholder() {
        let placeholder = showPlaceholderView
        placeholder.translatesAutoresizingMaskIntoConstraints = false
        placeholder.isHidden = true
        placeholder.onNewShow = { [weak self] in
            self?.promptNewAlbum()
        }
        placeholder.onOpenShow = { [weak self] in
            self?.libraryViewController.presentAllShows()
        }
        homePagerScrollView.insertSubview(placeholder, at: 0)

        let content = homePagerScrollView.contentLayoutGuide
        let leading = placeholder.leadingAnchor.constraint(equalTo: content.leadingAnchor)
        let width = placeholder.widthAnchor.constraint(equalToConstant: 320)
        let top = placeholder.topAnchor.constraint(equalTo: content.topAnchor)
        showPlaceholderLeadingConstraint = leading
        showPlaceholderWidthConstraint = width
        showPlaceholderTopConstraint = top
        NSLayoutConstraint.activate([
            leading, width, top,
            placeholder.bottomAnchor.constraint(equalTo: content.bottomAnchor)
        ])
    }

    private func embedMusicPage() {
        audioLibraryViewController.onAddMusic = { [weak self] in
            self?.showAudioPicker()
        }
        audioLibraryViewController.onRequestClose = { [weak self] in
            self?.showGridPage(animated: true)
        }

        let nav = HomeTabPageNavigationController(
            rootViewController: audioLibraryViewController
        )
        nav.setNavigationBarHidden(false, animated: false)
        nav.rootNeedsBar = { [weak self] in
            self?.audioLibraryViewController.isEditing ?? false
        }
        nav.onDepthChanged = { [weak self] atRoot in
            self?.headerBar.setMusicAddAvailable(atRoot)
            // The search filters the Music list, not the playlist now in front.
            if !atRoot, self?.searchingTab == .music {
                self?.endPageSearch()
            }
        }
        audioLibraryViewController.onEditingChanged = { [weak nav] in
            nav?.syncBar(animated: true)
        }
        audioLibraryNavController = nav

        addChild(nav)
        updateMusicHost(
            for: HomeMusicLayout.mode(
                horizontalSizeClass: traitCollection.horizontalSizeClass,
                pinned: isMusicSidebarPinned
            )
        )
        nav.didMove(toParent: self)
    }

    /// Goes to `tab`. Neighbours slide; a jump across pages fades instead, so the
    /// pages in between never flash by.
    private func setHomeTab(_ tab: HomeTab, animated: Bool) {
        guard isHomeTabPaging else { return }
        if tab == .music {
            libraryViewController.dismissMusicSwipeHint()
        }
        let from = homeTab
        homeTab = tab
        let pager = homePagerScrollView
        let width = pager.bounds.width
        let land = { [self] in
            if tab == .home || tab == .show {
                moveGrid(into: tab)
            }
            pager.setContentOffset(
                CGPoint(x: CGFloat(tab.rawValue) * width, y: 0), animated: false
            )
        }
        guard width > 0 else {
            if tab == .home || tab == .show { moveGrid(into: tab) }
            homeTabDidSettle()
            return
        }
        let moves = animated && view.window != nil
        if moves, HomeTabPaging.slides(from: from, to: tab),
           !UIAccessibility.isReduceMotionEnabled {
            // The grid's other slot is two pages away, so it can move across now and
            // slide in as the real thing.
            if tab == .home || tab == .show {
                moveGrid(into: tab)
            }
            isAnimatingHomePager = true
            pager.setContentOffset(
                CGPoint(x: CGFloat(tab.rawValue) * width, y: 0), animated: true
            )
            headerBar.setTabPage(tab)
            return
        }
        isAnimatingHomePager = false
        if moves {
            UIView.transition(
                with: pager,
                duration: 0.2,
                options: [.transitionCrossDissolve, .allowUserInteraction],
                animations: land
            )
        } else {
            land()
        }
        homeTabDidSettle(animated: moves)
    }

    private func updateHomePageIndexFromOffset() {
        isAnimatingHomePager = false
        guard isHomeTabPaging else { return }
        let width = homePagerScrollView.bounds.width
        guard width > 0 else { return }
        homeTab = HomeTabPaging.nearestTab(
            toPosition: homePagerScrollView.contentOffset.x / width
        )
        if homeTab == .home || homeTab == .show {
            moveGrid(into: homeTab)
        }
        homeTabDidSettle()
        if homeTab == .music {
            libraryViewController.dismissMusicSwipeHint()
        }
    }

    /// The pager has come to rest on `homeTab`.
    func homeTabDidSettle(animated: Bool = false) {
        headerBar.tabStrip.setSelected(homeTab, animated: animated)
        headerBar.setTabPage(homeTab)
        refreshHomePagerScrollEnabled()
        if let searchingTab, searchingTab != homeTab {
            endPageSearch()
        }
    }

    /// The header stays put on every page now; this only undoes anything left
    /// over from a layout change.
    private func updateHomeChromeForCurrentPage() {
        headerBar.isHidden = false
        headerBar.alpha = 1
        headerBar.transform = .identity
        headerBar.isUserInteractionEnabled = true
        raiseHomeOverlayChrome()
    }

    /// Compact: the pager runs up under the header, and each page starts below
    /// it (the grid by safe-area inset, Library and Music by position).
    /// Regular width: the pager sits below the header (drawer).
    func applyHomePagerTopAttachment() {
        let tabs = isHomeTabPaging
        headerBar.showsTabStrip = tabs
        let height = HomeHeaderBar.height(
            showsTabStrip: tabs,
            verticalSizeClass: traitCollection.verticalSizeClass,
            isSearching: headerBar.isSearching
        )
        headerHeightConstraint?.constant = height
        libraryPageTopConstraint?.constant = height
        showPlaceholderTopConstraint?.constant = height
        musicPageTopConstraint?.constant = tabs ? height : 0
        if traitCollection.horizontalSizeClass == .regular {
            homePagerTopToSafeAreaConstraint?.isActive = false
            homePagerTopToHeaderConstraint?.isActive = true
            libraryViewController.additionalSafeAreaInsets.top = 0
        } else {
            homePagerTopToHeaderConstraint?.isActive = false
            homePagerTopToSafeAreaConstraint?.isActive = true
            libraryViewController.additionalSafeAreaInsets.top = height
        }
    }
}

// MARK: - Rotation

extension iPhoneMainViewController {

    override func viewWillTransition(
        to size: CGSize,
        with coordinator: UIViewControllerTransitionCoordinator
    ) {
        super.viewWillTransition(to: size, with: coordinator)
        // Re-measure during the turn. Waiting only on `viewDidLayoutSubviews` left the
        // Library page at its portrait width, so Vertical stayed 3-up with a black band
        // beside the grid. Use the pager's bounds (safe-area width), not `size`
        // (full view), so pages don't spill under the landscape notch.
        let refresh = { [weak self] in
            guard let self else { return }
            self.updateHomeSplitLayoutIfNeeded()
            self.libraryViewController.invalidatePageLayouts()
            self.syncAudioMiniLayoutIfNeeded()
            ExternalDisplayManager.shared.syncLiveCameraOrientation()
        }
        coordinator.animate(alongsideTransition: { _ in
            refresh()
        }, completion: { _ in
            refresh()
            self.syncHomePagerOffsetIfNeeded()
        })
    }
}
