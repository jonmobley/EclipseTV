//
//  LibraryGridViewController+Pages.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import UIKit

// MARK: - Home / Show Pages

extension LibraryGridViewController {

    /// The visible Home or Show page.
    var collectionView: UICollectionView {
        isShowMode ? showCollectionView : homeCollectionView
    }

    /// Home page is its own collection view — opening a Show only hides it.
    func isHomePage(_ collectionView: UICollectionView) -> Bool {
        collectionView === homeCollectionView
    }

    /// Landscape-only slide strip under the live preview (not a Show-grid section).
    func isDockedSlideshowRibbon(_ collectionView: UICollectionView) -> Bool {
        collectionView === slideshowRibbonView
    }

    /// Sections for a specific page. Home never gains a Show ribbon; Show never
    /// gains the marketing carousel. The docked landscape ribbon is its own view.
    func pageSections(for collectionView: UICollectionView) -> [HomeSection] {
        if isHomePage(collectionView) {
            return HomeLayoutState.home.sections
        }
        if isDockedSlideshowRibbon(collectionView) {
            return [.slideshowRibbon]
        }
        return Self.visibleHomeSections(
            isShowMode: true,
            showsSlideshowRibbon: showsInGridSlideshowRibbon
        )
    }

    /// Home / Show section at `section` on that page.
    func homeSection(
        at section: Int,
        in collectionView: UICollectionView
    ) -> HomeSection? {
        let sections = pageSections(for: collectionView)
        guard sections.indices.contains(section) else { return nil }
        return sections[section]
    }

    /// Shows Home or Show without rewriting the other page's layout.
    func updateVisibleLibraryPage() {
        homeCollectionView.isHidden = isShowMode
        showCollectionView.isHidden = !isShowMode
        homeCollectionView.accessibilityElementsHidden = isShowMode
        showCollectionView.accessibilityElementsHidden = !isShowMode
    }

    /// Pins both pages inside `gridHost` and starts on Home.
    func installLibraryPages() {
        view.addSubview(gridHost)
        gridHost.addSubview(homeCollectionView)
        gridHost.addSubview(showCollectionView)
        NSLayoutConstraint.activate([
            homeCollectionView.topAnchor.constraint(equalTo: gridHost.topAnchor),
            homeCollectionView.leadingAnchor.constraint(equalTo: gridHost.leadingAnchor),
            homeCollectionView.trailingAnchor.constraint(equalTo: gridHost.trailingAnchor),
            homeCollectionView.bottomAnchor.constraint(equalTo: gridHost.bottomAnchor),
            showCollectionView.topAnchor.constraint(equalTo: gridHost.topAnchor),
            showCollectionView.leadingAnchor.constraint(equalTo: gridHost.leadingAnchor),
            showCollectionView.trailingAnchor.constraint(equalTo: gridHost.trailingAnchor),
            showCollectionView.bottomAnchor.constraint(equalTo: gridHost.bottomAnchor)
        ])
        showCollectionView.addGestureRecognizer(reorderGesture)
        updateVisibleLibraryPage()
    }

    /// Home layout is fixed: hero carousel + Recent. Never a Show grid.
    func makeHomePageLayout() -> UICollectionViewCompositionalLayout {
        Self.makeHomeLayout(
            sectionInset: sectionInset,
            spacing: interitemSpacing
        ) { [weak self] in
            HomeLayoutState(
                isShowMode: false,
                showsSlideshowRibbon: false,
                showsRecentFormatFilter: self?.showsHomeRecentFormatFilter ?? false
            )
        }
    }

    /// Show layout is fixed: media grid + optional live ribbon. Never the
    /// Home carousel, even while this page is hidden.
    func makeShowPageLayout() -> UICollectionViewCompositionalLayout {
        Self.makeHomeLayout(
            sectionInset: sectionInset,
            spacing: interitemSpacing
        ) { [weak self] in
            HomeLayoutState(
                isShowMode: true,
                showsSlideshowRibbon: self?.showsInGridSlideshowRibbon ?? false
            )
        }
    }

    /// Rebuilds the Show page layout (ribbon on/off). Leaves Home alone.
    func applyShowPageLayout() {
        showCollectionView.setCollectionViewLayout(
            makeShowPageLayout(),
            animated: false
        )
        updateHomeVerticalScrollPolicy()
        updateHeroCollapse()
    }

    /// Invalidates both pages after a size or Display Mode change.
    func invalidatePageLayouts() {
        homeCollectionView.collectionViewLayout.invalidateLayout()
        showCollectionView.collectionViewLayout.invalidateLayout()
    }

    /// Builds a page collection view. `registersHero` is Home-only so a Show
    /// page cannot dequeue the marketing carousel.
    func makePageCollectionView(
        layout: UICollectionViewLayout,
        registersHero: Bool
    ) -> UICollectionView {
        let view = UICollectionView(frame: .zero, collectionViewLayout: layout)
        view.backgroundColor = .systemBackground
        view.alwaysBounceVertical = true
        view.register(
            LibraryThumbnailCell.self,
            forCellWithReuseIdentifier: LibraryThumbnailCell.reuseIdentifier
        )
        view.register(
            HomeShowTileCell.self,
            forCellWithReuseIdentifier: HomeShowTileCell.reuseIdentifier
        )
        view.register(
            HomeSectionHeaderView.self,
            forSupplementaryViewOfKind: UICollectionView.elementKindSectionHeader,
            withReuseIdentifier: HomeSectionHeaderView.reuseIdentifier
        )
        if registersHero {
            view.register(
                HomeHeroCarouselCell.self,
                forCellWithReuseIdentifier: HomeHeroCarouselCell.reuseIdentifier
            )
        }
        view.dataSource = self
        view.delegate = self
        view.translatesAutoresizingMaskIntoConstraints = false
        view.isDirectionalLockEnabled = true
        return view
    }
}
