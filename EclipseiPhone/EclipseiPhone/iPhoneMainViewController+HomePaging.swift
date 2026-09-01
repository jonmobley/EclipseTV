//
//  iPhoneMainViewController+HomePaging.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import UIKit

// MARK: - Home Pager (Library | Music)

extension iPhoneMainViewController: UIScrollViewDelegate {

    /// Matches `HomeHeaderBar` height — overlays Library in compact paging.
    private static let homeHeaderOverlayHeight: CGFloat = 52

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
        embedMusicPage()
        // Header is added in `setupHeaderBar` before the pager — keep it on top.
        view.bringSubviewToFront(headerBar)
        applyHomePagerTopAttachment()
        updateHomeSplitLayoutIfNeeded()
        updateHomeChromeForCurrentPage()
    }

    /// Reveals Music: drawer on regular width, pager page when compact.
    /// No-op when Music is already pinned beside Library.
    func showMusicPage(animated: Bool = true) {
        if isMusicInDrawer {
            musicDrawer.setOpen(true, animated: animated)
            return
        }
        guard !isHomeSplitLayout else { return }
        setHomePage(1, animated: animated)
    }

    /// Hides Music: closes the drawer, or pages back to Library when compact.
    func showLibraryPage(animated: Bool = true) {
        if isMusicInDrawer {
            musicDrawer.setOpen(false, animated: animated)
            return
        }
        guard !isHomeSplitLayout else { return }
        setHomePage(0, animated: animated)
    }

    /// Locks paging while arranging media; snaps back to Library when paged.
    func setHomePagingEnabled(_ enabled: Bool) {
        if !enabled {
            if !isHomeSplitLayout {
                showLibraryPage(animated: true)
            }
            homePagerScrollView.isScrollEnabled = false
            return
        }
        refreshHomePagerScrollEnabled()
    }

    /// Switches among compact paging, pinned split, and the Music drawer.
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

        homePagerScrollView.isPagingEnabled = mode == .paging
        if mode != .paging {
            homePageIndex = 0
            homePagerScrollView.contentOffset = .zero
            homePagerScrollView.isScrollEnabled = false
        } else {
            refreshHomePagerScrollEnabled()
            syncHomePagerOffsetIfNeeded()
        }

        updateMusicHost(for: mode)
        applyHomePagerTopAttachment()
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
        // snap offset back to `homePageIndex` and leave the pager stuck mid-page).
        guard !homePagerScrollView.isDragging,
              !homePagerScrollView.isDecelerating
        else {
            return
        }
        let width = homePagerScrollView.bounds.width
        guard width > 0 else { return }
        let expected = CGFloat(homePageIndex) * width
        if abs(homePagerScrollView.contentOffset.x - expected) > 0.5 {
            homePagerScrollView.contentOffset = CGPoint(x: expected, y: 0)
        }
    }

    // MARK: - UIScrollViewDelegate

    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        guard scrollView === homePagerScrollView else { return }
        // Horizontal pager only — never let the whole Library/Music page ride
        // vertically under the fixed header.
        if abs(scrollView.contentOffset.y) > 0.5 {
            scrollView.contentOffset.y = 0
        }
        guard !isHomeSplitLayout, !isMusicInDrawer else { return }
        let width = scrollView.bounds.width
        guard width > 0 else { return }
        // Progress-tied chrome — pager height stays fixed so Music does not jump.
        let progress = min(1, max(0, scrollView.contentOffset.x / width))
        applyHomeLibraryHeaderMusicProgress(progress)
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
        guard scrollView === homePagerScrollView,
              !isHomeSplitLayout,
              !isMusicInDrawer else { return }
        updateHomePageIndexFromOffset()
    }

    // MARK: - Private

    /// Paging stays on except while arranging, selecting, split, drawer, or
    /// phone-landscape Show chrome. An open playlist remains the Music page.
    private func refreshHomePagerScrollEnabled() {
        let allowPaging: Bool
        if isHomeSplitLayout
            || isMusicInDrawer
            || libraryViewController.isArranging
            || libraryViewController.isSelecting {
            allowPaging = false
        } else if traitCollection.verticalSizeClass == .compact,
                  libraryViewController.isShowMode {
            // Preview|grid already owns the horizontal axis in phone landscape.
            allowPaging = false
        } else {
            allowPaging = true
        }
        homePagerScrollView.isScrollEnabled = allowPaging
        // Pager owns the swipe; the playlist back button returns to Music.
        audioLibraryNavController?.interactivePopGestureRecognizer?.isEnabled =
            !allowPaging
    }

    private func embedLibraryPage() {
        libraryViewController.onRequestResend = { [weak self] id in
            self?.beginResend(forItemId: id)
        }
        libraryViewController.onRequestEdit = { [weak self] id in
            self?.beginEditCrop(forItemId: id)
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
            self?.refreshLibraryMenu()
            self?.refreshHomePagerScrollEnabled()
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
        libraryViewController.onStatusMessage = { [weak self] message in
            self?.showTemporaryStatus(message)
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
        NSLayoutConstraint.activate([
            gridView.topAnchor.constraint(equalTo: homePagerScrollView.contentLayoutGuide.topAnchor),
            gridView.bottomAnchor.constraint(
                equalTo: homePagerScrollView.contentLayoutGuide.bottomAnchor
            ),
            gridView.leadingAnchor.constraint(
                equalTo: homePagerScrollView.contentLayoutGuide.leadingAnchor
            ),
            widthConstraint,
            gridView.heightAnchor.constraint(equalTo: frame.heightAnchor)
        ])

        let trailing = gridView.trailingAnchor.constraint(
            equalTo: homePagerScrollView.contentLayoutGuide.trailingAnchor
        )
        trailing.isActive = false
        libraryTrailingToContentConstraint = trailing
    }

    private func embedMusicPage() {
        audioLibraryViewController.onAddMusic = { [weak self] in
            self?.showAudioPicker()
        }
        audioLibraryViewController.onRequestClose = { [weak self] in
            self?.showLibraryPage(animated: true)
        }

        let nav = UINavigationController(rootViewController: audioLibraryViewController)
        nav.setNavigationBarHidden(false, animated: false)
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

    private func setHomePage(_ index: Int, animated: Bool) {
        guard !isHomeSplitLayout, !isMusicInDrawer else { return }
        if index == 1 {
            libraryViewController.dismissMusicSwipeHint()
        }
        let width = homePagerScrollView.bounds.width
        guard width > 0 else {
            homePageIndex = index
            updateHomeChromeForCurrentPage()
            return
        }
        homePageIndex = index
        let offset = CGPoint(x: CGFloat(index) * width, y: 0)
        homePagerScrollView.setContentOffset(offset, animated: animated)
        // Animated scrolls drive chrome from `scrollViewDidScroll`.
        if !animated {
            updateHomeChromeForCurrentPage()
        }
    }

    private func updateHomePageIndexFromOffset() {
        guard !isHomeSplitLayout, !isMusicInDrawer else { return }
        let width = homePagerScrollView.bounds.width
        guard width > 0 else { return }
        let index = Int(round(homePagerScrollView.contentOffset.x / width))
        homePageIndex = max(0, min(1, index))
        updateHomeChromeForCurrentPage()
        if homePageIndex == 1 {
            libraryViewController.dismissMusicSwipeHint()
        }
    }

    /// Hides the library `HomeHeaderBar` on the compact Music page (Music has its own nav bar).
    private func updateHomeChromeForCurrentPage() {
        let showLibraryHeader = isHomeSplitLayout || homePageIndex != 1
        applyHomeLibraryHeaderVisible(showLibraryHeader)
    }

    /// Compact: pager is always under the status bar; header overlays Library.
    /// Regular width: pager sits below the header (split and drawer).
    private func applyHomePagerTopAttachment() {
        if traitCollection.horizontalSizeClass == .regular {
            homePagerTopToSafeAreaConstraint?.isActive = false
            homePagerTopToHeaderConstraint?.isActive = true
            libraryViewController.additionalSafeAreaInsets.top = 0
        } else {
            homePagerTopToHeaderConstraint?.isActive = false
            homePagerTopToSafeAreaConstraint?.isActive = true
            libraryViewController.additionalSafeAreaInsets.top =
                Self.homeHeaderOverlayHeight
        }
    }

    /// Settled show/hide for the library header without changing pager height.
    private func applyHomeLibraryHeaderVisible(_ visible: Bool) {
        applyHomeLibraryHeaderMusicProgress(visible ? 0 : 1)
        headerBar.isHidden = !visible
    }

    /// Library→Music progress (0…1): fades and nudges the header with the swipe.
    private func applyHomeLibraryHeaderMusicProgress(_ progress: CGFloat) {
        let p = min(1, max(0, progress))
        let slide: CGFloat = 28
        if headerBar.isHidden, p < 1 {
            headerBar.isHidden = false
        }
        headerBar.alpha = 1 - p
        headerBar.transform = CGAffineTransform(translationX: -p * slide, y: 0)
        headerBar.isUserInteractionEnabled = p < 0.5
        if p < 1 {
            view.bringSubviewToFront(headerBar)
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
