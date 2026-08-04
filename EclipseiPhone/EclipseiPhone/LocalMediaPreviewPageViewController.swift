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
    private let imageView = UIImageView()

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

    // MARK: - Setup

    private func setupImage() {
        // Match the framing the item gets on the external screen / Apple TV.
        imageView.contentMode = MediaFitSettings.mode(forId: item.id).contentMode
        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.image = UIImage(contentsOfFile: item.fileURL.path)
        view.addSubview(imageView)
        NSLayoutConstraint.activate([
            imageView.topAnchor.constraint(equalTo: view.topAnchor),
            imageView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            imageView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            imageView.trailingAnchor.constraint(equalTo: view.trailingAnchor)
        ])
    }
}
