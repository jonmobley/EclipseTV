//
//  ShowPreviewViewController.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import UIKit

/// Fullscreen swipe gallery for a Show: stills plus Screensaver and Background.
///
/// Photos use Photos-style fit zoom. Screensaver / Background stay in a Display
/// Mode fill panel. Camera, PDF, web, slideshow, and library videos are omitted.
final class ShowPreviewViewController: UIViewController {

    private let items: [ShowPreviewItem]
    private let startIndex: Int
    /// Page currently on screen; swiping updates it once the transition lands.
    private var currentIndex: Int
    private let header = PreviewHeaderView()
    private var pageController: UIPageViewController!
    private var dismissDriver: PreviewDismissDriver?

    /// Called as the gallery closes with the id (library id or `ShowToolToken`) of
    /// the page that was on screen, so the Show grid can bring that tile into view.
    var onDismiss: ((String) -> Void)?

    /// Supplies the header ⋯ menu, so Preview mirrors the Show tile menu. Only
    /// stills carry an id, so Screensaver and Background pages hide the button.
    var optionsMenuProvider: ((PreviewMenuContext) -> UIMenu?)?

    /// - Parameters:
    ///   - items: Ordered gallery entries (must be non-empty).
    ///   - startIndex: Initial page within `items`.
    init(items: [ShowPreviewItem], startIndex: Int) {
        precondition(!items.isEmpty)
        precondition(items.indices.contains(startIndex))
        self.items = items
        self.startIndex = startIndex
        self.currentIndex = startIndex
        super.init(nibName: nil, bundle: nil)
        modalPresentationStyle = .fullScreen
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        setupPager()
        setupHeader()
        setupDismissDrag()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        // The note composer is a sheet, so this only fires for the gallery itself.
        guard isBeingDismissed else { return }
        // A drag-to-close that springs back still runs this, so wait for the
        // transition to land before parking the grid on a page we did not leave on.
        let id = items[currentIndex].id
        let notify = onDismiss
        guard let coordinator = transitionCoordinator else {
            notify?(id)
            return
        }
        coordinator.animate(alongsideTransition: nil) { context in
            guard !context.isCancelled else { return }
            notify?(id)
        }
    }

    // MARK: - Setup

    private func setupPager() {
        let pager = UIPageViewController(
            transitionStyle: .scroll,
            navigationOrientation: .horizontal,
            options: nil
        )
        pager.dataSource = self
        pager.delegate = self
        addChild(pager)
        pager.view.frame = view.bounds
        pager.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(pager.view)
        pager.didMove(toParent: self)
        pageController = pager

        guard let first = makePage(at: startIndex) else { return }
        pager.setViewControllers([first], direction: .forward, animated: false)
    }

    private func setupHeader() {
        header.translatesAutoresizingMaskIntoConstraints = false
        header.onClose = { [weak self] in
            self?.dismiss(animated: true)
        }
        header.onShare = { [weak self] url, button in
            self?.presentPreviewShareSheet(for: url, from: button)
        }
        if let build = optionsMenuProvider {
            header.menuProvider = { [weak self] itemId in
                guard let self else { return nil }
                return build(self.previewMenuContext(itemId: itemId))
            }
        }
        view.addSubview(header)
        view.bringSubviewToFront(header)
        NSLayoutConstraint.activate([
            header.topAnchor.constraint(equalTo: view.topAnchor),
            header.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            header.trailingAnchor.constraint(equalTo: view.trailingAnchor)
        ])
        updateHeader()
    }

    private func setupDismissDrag() {
        let driver = PreviewDismissDriver(host: self)
        driver.onDraggingChanged = { [weak self] dragging in
            self?.setPagingEnabled(!dragging)
        }
        dismissDriver = driver
    }

    /// Retitles the header for whichever page is on screen.
    private func updateHeader() {
        header.configure(with: .showPage(items[currentIndex]))
    }

    private func makePage(at index: Int) -> UIViewController? {
        guard items.indices.contains(index) else { return nil }
        switch items[index] {
        case .still(let item):
            let page = LocalMediaPreviewPageViewController(item: item, index: index)
            page.onZoomedChanged = { [weak self] zoomed in
                self?.pageZoomChanged(zoomed)
            }
            return page
        case .displayMode(let spec):
            let page = DisplayModeMediaPreviewPageViewController(
                fileURL: spec.fileURL,
                isVideo: spec.isVideo,
                usesSeamlessLoop: spec.usesSeamlessLoop,
                index: index
            )
            page.onZoomedChanged = { [weak self] zoomed in
                self?.pageZoomChanged(zoomed)
            }
            return page
        }
    }

    private func pageZoomChanged(_ zoomed: Bool) {
        setPagingEnabled(!zoomed)
        // Zoomed in, a drag pans the still; only a fitted page can be pulled away.
        dismissDriver?.isEnabled = !zoomed
    }

    private func setPagingEnabled(_ enabled: Bool) {
        pageController.view.subviews
            .compactMap { $0 as? UIScrollView }
            .forEach { $0.isScrollEnabled = enabled }
    }

    private func pageIndex(of viewController: UIViewController) -> Int? {
        if let page = viewController as? LocalMediaPreviewPageViewController {
            return page.index
        }
        if let page = viewController as? DisplayModeMediaPreviewPageViewController {
            return page.index
        }
        return nil
    }

    private func recycle(_ viewController: UIViewController) {
        (viewController as? LocalMediaPreviewPageViewController)?.pausePlayback()
        (viewController as? LocalMediaPreviewPageViewController)?.resetZoom()
        (viewController as? DisplayModeMediaPreviewPageViewController)?.pausePlayback()
        (viewController as? DisplayModeMediaPreviewPageViewController)?.resetZoom()
    }
}

// MARK: - UIPageViewControllerDataSource & Delegate

extension ShowPreviewViewController: UIPageViewControllerDataSource,
                                     UIPageViewControllerDelegate {

    func pageViewController(
        _ pageViewController: UIPageViewController,
        viewControllerBefore viewController: UIViewController
    ) -> UIViewController? {
        guard let index = pageIndex(of: viewController) else { return nil }
        return makePage(at: index - 1)
    }

    func pageViewController(
        _ pageViewController: UIPageViewController,
        viewControllerAfter viewController: UIViewController
    ) -> UIViewController? {
        guard let index = pageIndex(of: viewController) else { return nil }
        return makePage(at: index + 1)
    }

    func pageViewController(
        _ pageViewController: UIPageViewController,
        didFinishAnimating finished: Bool,
        previousViewControllers: [UIViewController],
        transitionCompleted completed: Bool
    ) {
        guard completed else { return }
        setPagingEnabled(true)
        if let current = pageViewController.viewControllers?.first,
           let index = pageIndex(of: current) {
            currentIndex = index
            updateHeader()
        }
        previousViewControllers.forEach(recycle)
    }
}
