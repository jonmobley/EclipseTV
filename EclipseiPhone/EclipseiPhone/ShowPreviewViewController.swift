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
    private let closeButton = UIButton(type: .system)
    private var pageController: UIPageViewController!

    /// - Parameters:
    ///   - items: Ordered gallery entries (must be non-empty).
    ///   - startIndex: Initial page within `items`.
    init(items: [ShowPreviewItem], startIndex: Int) {
        precondition(!items.isEmpty)
        precondition(items.indices.contains(startIndex))
        self.items = items
        self.startIndex = startIndex
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
        setupCloseButton()
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

    private func setupCloseButton() {
        closeButton.applyPreviewCloseAppearance()
        closeButton.translatesAutoresizingMaskIntoConstraints = false
        closeButton.addTarget(self, action: #selector(closeTapped), for: .touchUpInside)
        view.addSubview(closeButton)
        view.bringSubviewToFront(closeButton)
        NSLayoutConstraint.activate([
            closeButton.topAnchor.constraint(
                equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 12),
            closeButton.trailingAnchor.constraint(
                equalTo: view.trailingAnchor, constant: -16)
        ])
    }

    private func makePage(at index: Int) -> UIViewController? {
        guard items.indices.contains(index) else { return nil }
        switch items[index] {
        case .still(let item):
            let page = LocalMediaPreviewPageViewController(item: item, index: index)
            page.onZoomedChanged = { [weak self] zoomed in
                self?.setPagingEnabled(!zoomed)
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
                self?.setPagingEnabled(!zoomed)
            }
            return page
        }
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

    @objc private func closeTapped() {
        dismiss(animated: true)
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
        previousViewControllers.forEach(recycle)
    }
}
