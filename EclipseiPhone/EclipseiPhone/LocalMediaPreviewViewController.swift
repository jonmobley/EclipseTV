//
//  LocalMediaPreviewViewController.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import UIKit

/// One locally stored media file that can be shown in the phone preview gallery.
struct LocalMediaPreviewItem: Equatable {
    let id: String
    let fileURL: URL
    let isVideo: Bool
    /// Honored for system video Preview (matches AirPlay / EclipseTV).
    var isLooping: Bool = false
    var isMuted: Bool = false
}

/// Fullscreen swipeable gallery of **images** stored on the phone (`LocalMediaStore`).
///
/// Videos open via `LocalVideoPreviewViewController` (system player) instead.
/// Opened from long-press → Preview on an image. Swipe left/right through `items`.
final class LocalMediaPreviewViewController: UIViewController {

    private let items: [LocalMediaPreviewItem]
    private let header = PreviewHeaderView()
    private var pageController: UIPageViewController!
    private var dismissDriver: PreviewDismissDriver?

    /// Builds preview items from library DTOs that have a local full-res copy.
    static func previewableItems(from items: [LibraryItemDTO]) -> [LocalMediaPreviewItem] {
        items.compactMap { item in
            guard let url = LocalMediaStore.shared.localURL(forId: item.id) else { return nil }
            return LocalMediaPreviewItem(
                id: item.id,
                fileURL: url,
                isVideo: item.isVideo,
                isLooping: item.isLooping ?? false,
                isMuted: item.isMuted ?? false
            )
        }
    }

    /// Image-only subset for the swipe gallery.
    static func imagePreviewableItems(from items: [LibraryItemDTO]) -> [LocalMediaPreviewItem] {
        previewableItems(from: items).filter { !$0.isVideo }
    }

    private let startIndex: Int
    /// Page currently on screen; swiping updates it once the transition lands.
    private var currentIndex: Int

    /// Called as the gallery closes with the id of the page that was on screen, so
    /// the presenting grid can bring that tile back into view.
    var onDismiss: ((String) -> Void)?

    /// Supplies the header ⋯ menu, so Preview mirrors the tile menu of the screen
    /// that opened it. Leave `nil` to hide the button.
    var optionsMenuProvider: ((PreviewMenuContext) -> UIMenu?)?

    /// - Parameters:
    ///   - items: Ordered gallery entries (must be non-empty).
    ///   - startIndex: Initial page within `items`.
    init(items: [LocalMediaPreviewItem], startIndex: Int) {
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
        let item = items[currentIndex]
        header.configure(with: .libraryItem(id: item.id, fileURL: item.fileURL))
    }

    private func makePage(at index: Int) -> LocalMediaPreviewPageViewController? {
        guard items.indices.contains(index) else { return nil }
        let page = LocalMediaPreviewPageViewController(item: items[index], index: index)
        page.onZoomedChanged = { [weak self] zoomed in
            self?.setPagingEnabled(!zoomed)
            // Zoomed in, a drag pans the still; only a fitted page can be pulled away.
            self?.dismissDriver?.isEnabled = !zoomed
        }
        return page
    }

    private func setPagingEnabled(_ enabled: Bool) {
        pageController.view.subviews
            .compactMap { $0 as? UIScrollView }
            .forEach { $0.isScrollEnabled = enabled }
    }
}

// MARK: - UIPageViewControllerDataSource & Delegate

extension LocalMediaPreviewViewController: UIPageViewControllerDataSource,
                                          UIPageViewControllerDelegate {

    func pageViewController(
        _ pageViewController: UIPageViewController,
        viewControllerBefore viewController: UIViewController
    ) -> UIViewController? {
        guard let page = viewController as? LocalMediaPreviewPageViewController else { return nil }
        return self.makePage(at: page.index - 1)
    }

    func pageViewController(
        _ pageViewController: UIPageViewController,
        viewControllerAfter viewController: UIViewController
    ) -> UIViewController? {
        guard let page = viewController as? LocalMediaPreviewPageViewController else { return nil }
        return self.makePage(at: page.index + 1)
    }

    func pageViewController(
        _ pageViewController: UIPageViewController,
        didFinishAnimating finished: Bool,
        previousViewControllers: [UIViewController],
        transitionCompleted completed: Bool
    ) {
        guard completed else { return }
        setPagingEnabled(true)
        if let current = pageViewController.viewControllers?.first
            as? LocalMediaPreviewPageViewController {
            currentIndex = current.index
            updateHeader()
        }
        for previous in previousViewControllers {
            (previous as? LocalMediaPreviewPageViewController)?.pausePlayback()
            (previous as? LocalMediaPreviewPageViewController)?.resetZoom()
        }
    }
}
