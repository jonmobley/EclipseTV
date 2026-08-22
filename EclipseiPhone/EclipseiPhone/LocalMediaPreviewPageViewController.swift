//
//  LocalMediaPreviewPageViewController.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import UIKit

/// Single image page inside `LocalMediaPreviewViewController`.
///
/// Videos use modal `LocalVideoPreviewViewController` with system player chrome
/// instead of living in this swipe gallery.
final class LocalMediaPreviewPageViewController: UIViewController {

    let index: Int
    private let item: LocalMediaPreviewItem
    private let zoomView = ZoomableImageView()

    /// Called when pinch/double-tap zoom crosses the fitted scale.
    var onZoomedChanged: ((Bool) -> Void)?

    init(item: LocalMediaPreviewItem, index: Int) {
        precondition(!item.isVideo, "Videos use LocalVideoPreviewViewController")
        self.item = item
        self.index = index
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        setupImage()
    }

    /// No-op kept so the gallery host can pause departing pages uniformly.
    func pausePlayback() {}

    /// Restores Photos-style fit after the page is no longer current.
    func resetZoom() {
        zoomView.resetZoom(animated: false)
    }

    // MARK: - Setup

    private func setupImage() {
        // Preview inspects the still like Photos (fit), not the TV Fit/Fill framing.
        zoomView.translatesAutoresizingMaskIntoConstraints = false
        zoomView.image = UIImage(contentsOfFile: item.fileURL.path)
        zoomView.onZoomedChanged = { [weak self] zoomed in
            self?.onZoomedChanged?(zoomed)
        }
        view.addSubview(zoomView)
        NSLayoutConstraint.activate([
            zoomView.topAnchor.constraint(equalTo: view.topAnchor),
            zoomView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            zoomView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            zoomView.trailingAnchor.constraint(equalTo: view.trailingAnchor)
        ])
    }
}
