//
//  LocalMediaPreviewViewController.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import UIKit

/// One locally stored media file that can be shown in the phone preview gallery.
struct LocalMediaPreviewItem {
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
    private let closeButton = UIButton(type: .system)
    private var pageController: UIPageViewController!

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

    /// - Parameters:
    ///   - items: Ordered gallery entries (must be non-empty).
    ///   - startIndex: Initial page within `items`.
    init(items: [LocalMediaPreviewItem], startIndex: Int) {
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

        let first = LocalMediaPreviewPageViewController(item: items[startIndex], index: startIndex)
        pager.setViewControllers([first], direction: .forward, animated: false)
    }

    private func setupCloseButton() {
        let config = UIImage.SymbolConfiguration(pointSize: 28, weight: .semibold)
        closeButton.setImage(
            UIImage(systemName: "xmark.circle.fill", withConfiguration: config),
            for: .normal
        )
        closeButton.tintColor = UIColor.white.withAlphaComponent(0.9)
        closeButton.translatesAutoresizingMaskIntoConstraints = false
        closeButton.addTarget(self, action: #selector(closeTapped), for: .touchUpInside)
        view.addSubview(closeButton)
        NSLayoutConstraint.activate([
            closeButton.topAnchor.constraint(
                equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 12),
            closeButton.trailingAnchor.constraint(
                equalTo: view.trailingAnchor, constant: -16)
        ])
    }

    private func page(at index: Int) -> LocalMediaPreviewPageViewController? {
        guard items.indices.contains(index) else { return nil }
        return LocalMediaPreviewPageViewController(item: items[index], index: index)
    }

    @objc private func closeTapped() {
        dismiss(animated: true)
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
        return self.page(at: page.index - 1)
    }

    func pageViewController(
        _ pageViewController: UIPageViewController,
        viewControllerAfter viewController: UIViewController
    ) -> UIViewController? {
        guard let page = viewController as? LocalMediaPreviewPageViewController else { return nil }
        return self.page(at: page.index + 1)
    }

    func pageViewController(
        _ pageViewController: UIPageViewController,
        didFinishAnimating finished: Bool,
        previousViewControllers: [UIViewController],
        transitionCompleted completed: Bool
    ) {
        guard completed else { return }
        for previous in previousViewControllers {
            (previous as? LocalMediaPreviewPageViewController)?.pausePlayback()
        }
    }
}
