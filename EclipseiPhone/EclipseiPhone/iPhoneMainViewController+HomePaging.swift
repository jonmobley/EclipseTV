//
//  iPhoneMainViewController+HomePaging.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import UIKit

// MARK: - Home Pager (Library | Music)

extension iPhoneMainViewController: UIScrollViewDelegate, UINavigationControllerDelegate {

    /// Preferred Music sidebar width in regular-width (side-by-side) layout.
    private static let musicSidebarPreferredWidth: CGFloat = 340
    /// Minimum Library pane width when side-by-side.
    private static let librarySplitMinWidth: CGFloat = 360
    /// Floor for a squeezed Music sidebar on narrower regular widths.
    private static let musicSidebarMinWidth: CGFloat = 280
    /// Matches `HomeHeaderBar` height — overlays Library in compact paging.
    private static let homeHeaderOverlayHeight: CGFloat = 52

    /// Embeds Library and Music side-by-side in a horizontal paging scroll view.
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

        NSLayoutConstraint.activate([
            topToSafeArea,
            homePagerScrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            homePagerScrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
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

    /// Scrolls to the Music page (right of the media grid). No-op in split layout.
    func showMusicPage(animated: Bool = true) {
        guard !isHomeSplitLayout else { return }
        setHomePage(1, animated: animated)
    }

    /// Scrolls back to the Library grid. No-op in split layout.
    func showLibraryPage(animated: Bool = true) {
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

    /// Switches between compact paging and regular-width side-by-side.
    func updateHomeSplitLayoutIfNeeded() {
        let width = homePagerScrollView.bounds.width
        guard width > 0 else { return }

        let wantSplit = traitCollection.horizontalSizeClass == .regular
        let musicWidth = wantSplit ? musicSidebarWidth(for: width) : width
        let libraryWidth = wantSplit ? width - musicWidth : width

        let splitChanged = wantSplit != isHomeSplitLayout
        let libraryWidthChanged =
            abs((libraryPageWidthConstraint?.constant ?? -1) - libraryWidth) > 0.5
        let musicWidthChanged =
            abs((musicPageWidthConstraint?.constant ?? -1) - musicWidth) > 0.5
        guard splitChanged || libraryWidthChanged || musicWidthChanged else { return }

        isHomeSplitLayout = wantSplit
        libraryPageWidthConstraint?.constant = libraryWidth
        musicPageWidthConstraint?.constant = musicWidth

        homePagerScrollView.isPagingEnabled = !wantSplit
        if wantSplit {
            homePageIndex = 0
            homePagerScrollView.contentOffset = .zero
            homePagerScrollView.isScrollEnabled = false
        } else {
            refreshHomePagerScrollEnabled()
            syncHomePagerOffsetIfNeeded()
        }

        audioLibraryViewController.showsEmbeddedBackButton = !wantSplit
        applyHomePagerTopAttachment()
        updateHomeChromeForCurrentPage()
    }

    /// Keeps the current page aligned after rotation / bounds changes.
    func syncHomePagerOffsetIfNeeded() {
        guard !isHomeSplitLayout else {
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
        guard scrollView === homePagerScrollView, !isHomeSplitLayout else { return }
        let width = scrollView.bounds.width
        guard width > 0 else { return }
        // Fade only — pager height stays fixed so Music does not jump.
        let showingMusic = scrollView.contentOffset.x / width > 0.5
        headerBar.alpha = showingMusic ? 0 : 1
        headerBar.isUserInteractionEnabled = !showingMusic
    }

    func scrollViewDidEndDragging(
        _ scrollView: UIScrollView,
        willDecelerate decelerate: Bool
    ) {
        guard scrollView === homePagerScrollView, !isHomeSplitLayout else { return }
        if !decelerate {
            updateHomePageIndexFromOffset()
        }
    }

    func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) {
        guard scrollView === homePagerScrollView, !isHomeSplitLayout else { return }
        updateHomePageIndexFromOffset()
    }

    func scrollViewDidEndScrollingAnimation(_ scrollView: UIScrollView) {
        guard scrollView === homePagerScrollView, !isHomeSplitLayout else { return }
        updateHomePageIndexFromOffset()
    }

    func navigationController(
        _ navigationController: UINavigationController,
        didShow viewController: UIViewController,
        animated: Bool
    ) {
        guard navigationController === audioLibraryNavController else { return }
        refreshHomePagerScrollEnabled()
    }

    // MARK: - Private

    /// Music sidebar width, keeping Library at least `librarySplitMinWidth` when possible.
    private func musicSidebarWidth(for totalWidth: CGFloat) -> CGFloat {
        let preferred = Self.musicSidebarPreferredWidth
        let minLibrary = Self.librarySplitMinWidth
        if totalWidth >= minLibrary + preferred {
            return preferred
        }
        return max(Self.musicSidebarMinWidth, totalWidth - minLibrary)
    }

    /// Paging stays on only at Music root (and never while arranging, split,
    /// or phone-landscape side-by-side chrome).
    private func refreshHomePagerScrollEnabled() {
        if isHomeSplitLayout || libraryViewController.isArranging {
            homePagerScrollView.isScrollEnabled = false
            return
        }
        // Grid|preview owns the horizontal axis in phone landscape; Music stays
        // reachable via the Add menu / mini player.
        if traitCollection.verticalSizeClass == .compact {
            homePagerScrollView.isScrollEnabled = false
            return
        }
        let atMusicRoot = (audioLibraryNavController?.viewControllers.count ?? 1) <= 1
        homePagerScrollView.isScrollEnabled = atMusicRoot
    }

    private func embedLibraryPage() {
        libraryViewController.onRequestResend = { [weak self] id in
            self?.beginResend(forItemId: id)
        }
        libraryViewController.onRequestEdit = { [weak self] id in
            self?.beginEditCrop(forItemId: id)
        }
        libraryViewController.onPresentCamera = { [weak self] in
            self?.presentCameraLive()
        }
        libraryViewController.onChooseLogo = { [weak self] in
            self?.showLogoPicker()
        }
        libraryViewController.onAddMediaToAlbum = { [weak self] albumId in
            self?.promptAddMedia(toAlbumId: albumId)
        }
        libraryViewController.onCreateSlideshow = { [weak self] albumId in
            self?.promptNewSlideshow(inShowId: albumId)
        }
        libraryViewController.onCreateShow = { [weak self] in
            self?.promptNewAlbum()
        }
        libraryViewController.onSeeAllShows = { [weak self] in
            self?.presentAllShows()
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
        libraryViewController.onBlackLiveChanged = { [weak self] live in
            self?.headerBar.setBlackLive(live)
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
        nav.delegate = self
        audioLibraryNavController = nav

        addChild(nav)
        let musicView = nav.view!
        musicView.translatesAutoresizingMaskIntoConstraints = false
        homePagerScrollView.addSubview(musicView)
        nav.didMove(toParent: self)

        let gridView = libraryViewController.view!
        let frame = homePagerScrollView.frameLayoutGuide
        let initialWidth = max(
            homePagerScrollView.bounds.width,
            view.bounds.width,
            UIScreen.main.bounds.width
        )
        let widthConstraint = musicView.widthAnchor.constraint(equalToConstant: initialWidth)
        musicPageWidthConstraint = widthConstraint
        NSLayoutConstraint.activate([
            musicView.topAnchor.constraint(equalTo: homePagerScrollView.contentLayoutGuide.topAnchor),
            musicView.bottomAnchor.constraint(
                equalTo: homePagerScrollView.contentLayoutGuide.bottomAnchor
            ),
            musicView.leadingAnchor.constraint(equalTo: gridView.trailingAnchor),
            musicView.trailingAnchor.constraint(
                equalTo: homePagerScrollView.contentLayoutGuide.trailingAnchor
            ),
            widthConstraint,
            musicView.heightAnchor.constraint(equalTo: frame.heightAnchor)
        ])
    }

    private func setHomePage(_ index: Int, animated: Bool) {
        guard !isHomeSplitLayout else { return }
        let width = homePagerScrollView.bounds.width
        guard width > 0 else {
            homePageIndex = index
            updateHomeChromeForCurrentPage()
            return
        }
        homePageIndex = index
        let offset = CGPoint(x: CGFloat(index) * width, y: 0)
        homePagerScrollView.setContentOffset(offset, animated: animated)
        // Animated scrolls update chrome from `scrollViewDidScroll` at the midpoint.
        if !animated {
            updateHomeChromeForCurrentPage()
        }
        if index == 0 {
            audioLibraryNavController?.popToRootViewController(animated: false)
        }
    }

    private func updateHomePageIndexFromOffset() {
        guard !isHomeSplitLayout else { return }
        let width = homePagerScrollView.bounds.width
        guard width > 0 else { return }
        let index = Int(round(homePagerScrollView.contentOffset.x / width))
        homePageIndex = max(0, min(1, index))
        updateHomeChromeForCurrentPage()
        if homePageIndex == 0 {
            audioLibraryNavController?.popToRootViewController(animated: false)
        }
    }

    /// Hides the library `HomeHeaderBar` on the compact Music page (Music has its own nav bar).
    private func updateHomeChromeForCurrentPage() {
        let showLibraryHeader = isHomeSplitLayout || homePageIndex != 1
        applyHomeLibraryHeaderVisible(showLibraryHeader)
    }

    /// Compact: pager is always under the status bar; header overlays Library.
    /// Split: pager sits below the header (both panes share that chrome).
    private func applyHomePagerTopAttachment() {
        if isHomeSplitLayout {
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

    /// Shows or hides the library header without changing pager height.
    private func applyHomeLibraryHeaderVisible(_ visible: Bool) {
        let shouldHide = !visible
        guard headerBar.isHidden != shouldHide
            || headerBar.alpha != (visible ? 1 : 0)
        else { return }

        headerBar.alpha = visible ? 1 : 0
        headerBar.isHidden = shouldHide
        headerBar.isUserInteractionEnabled = visible
        if visible {
            view.bringSubviewToFront(headerBar)
        }
    }
}
