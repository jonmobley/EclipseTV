//
//  DisplayModeMediaPreviewViewController.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import UIKit

/// Fullscreen Preview for a single Show tool framed like AirPlay (Home / fallback).
///
/// Content sits in a Display Mode panel (16:9 or 9:16) and **always aspect-fills**,
/// matching vertical tiles — landscape art is cropped in Vertical mode rather than
/// letterboxed on the phone.
final class DisplayModeMediaPreviewViewController: UIViewController {

    private let page: DisplayModeMediaPreviewPageViewController
    private let closeButton = UIButton(type: .system)

    /// - Parameters:
    ///   - fileURL: Local still or video file.
    ///   - isVideo: Plays video instead of showing a still.
    ///   - usesSeamlessLoop: Screensaver dual-player crossfade; otherwise simple loop.
    init(fileURL: URL, isVideo: Bool, usesSeamlessLoop: Bool = false) {
        page = DisplayModeMediaPreviewPageViewController(
            fileURL: fileURL,
            isVideo: isVideo,
            usesSeamlessLoop: usesSeamlessLoop,
            index: 0
        )
        super.init(nibName: nil, bundle: nil)
        modalPresentationStyle = .fullScreen
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        addChild(page)
        page.view.frame = view.bounds
        page.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(page.view)
        page.didMove(toParent: self)
        setupCloseButton()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        view.bringSubviewToFront(closeButton)
    }

    // MARK: - Setup

    private func setupCloseButton() {
        closeButton.applyPreviewCloseAppearance()
        closeButton.translatesAutoresizingMaskIntoConstraints = false
        closeButton.addTarget(self, action: #selector(closeTapped), for: .touchUpInside)
        view.addSubview(closeButton)
        NSLayoutConstraint.activate([
            closeButton.topAnchor.constraint(
                equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 12
            ),
            closeButton.trailingAnchor.constraint(
                equalTo: view.trailingAnchor, constant: -16
            )
        ])
    }

    @objc private func closeTapped() {
        dismiss(animated: true)
    }
}
