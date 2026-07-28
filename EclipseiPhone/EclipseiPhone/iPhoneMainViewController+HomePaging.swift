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

    /// Embeds Library and Music side-by-side in a horizontal paging scroll view.
    func embedHomePager() {
        homePagerScrollView.delegate = self
        view.addSubview(homePagerScrollView)

        NSLayoutConstraint.activate([
            homePagerScrollView.topAnchor.constraint(equalTo: headerBar.bottomAnchor),
            homePagerScrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            homePagerScrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            homePagerScrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])

        embedLibraryPage()
        embedMusicPage()
        updateHomeSplitLayoutIfNeeded()
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
    }

    /// Keeps the current page aligned after rotation / bounds changes.
    func syncHomePagerOffsetIfNeeded() {
        guard !isHomeSplitLayout else {
            if homePagerScrollView.contentOffset.x != 0 {
                homePagerScrollView.contentOffset = .zero
            }
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

    /// Paging stays on only at Music root (and never while arranging or split).
    private func refreshHomePagerScrollEnabled() {
        if isHomeSplitLayout || libraryViewController.isArranging {
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
        libraryViewController.onOpenShowChanged = { [weak self] _ in
            self?.refreshLibraryMenu()
            self?.refreshHomePagerScrollEnabled()
        }
        libraryViewController.onArrangingChanged = { [weak self] _ in
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
            return
        }
        homePageIndex = index
        let offset = CGPoint(x: CGFloat(index) * width, y: 0)
        homePagerScrollView.setContentOffset(offset, animated: animated)
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
        if homePageIndex == 0 {
            audioLibraryNavController?.popToRootViewController(animated: false)
        }
    }
}
