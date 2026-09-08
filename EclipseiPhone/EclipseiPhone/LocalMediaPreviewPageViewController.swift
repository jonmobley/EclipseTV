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
    private let noteOverlay = MediaNoteOverlayView()
    private var noteObserver: NSObjectProtocol?
    private var isZoomed = false

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

    deinit {
        if let noteObserver {
            NotificationCenter.default.removeObserver(noteObserver)
        }
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        setupImage()
        setupNoteOverlay()
    }

    /// No-op kept so the gallery host can pause departing pages uniformly.
    func pausePlayback() {}

    /// Restores Photos-style fit after the page is no longer current.
    func resetZoom() {
        zoomView.resetZoom(animated: false)
        isZoomed = false
        noteOverlay.reload()
        applyNoteOverlayVisibility()
    }

    // MARK: - Setup

    private func setupImage() {
        zoomView.translatesAutoresizingMaskIntoConstraints = false
        loadStill()
        zoomView.onZoomedChanged = { [weak self] zoomed in
            guard let self else { return }
            self.isZoomed = zoomed
            self.applyNoteOverlayVisibility()
            self.onZoomedChanged?(zoomed)
        }
        view.addSubview(zoomView)
        NSLayoutConstraint.activate([
            zoomView.topAnchor.constraint(equalTo: view.topAnchor),
            zoomView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            zoomView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            zoomView.trailingAnchor.constraint(equalTo: view.trailingAnchor)
        ])
    }

    /// Shows the still the way it goes to the screen: cropped to a saved custom
    /// framing, then fitted Photos-style. Fit / Fill without framing shows the whole
    /// file. Uncropped stills paint synchronously; the crop runs off the main thread
    /// because it may redraw a full-resolution photo.
    private func loadStill() {
        let fileURL = item.fileURL
        guard let framing = MediaFramingStore.framing(forId: item.id) else {
            zoomView.image = UIImage(contentsOfFile: fileURL.path)
            return
        }
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let image = Self.framedStill(at: fileURL, framing: framing)
            DispatchQueue.main.async {
                self?.zoomView.image = image
            }
        }
    }

    /// Decodes `fileURL` and crops it to `framing`; falls back to the full still when
    /// the crop can't be produced.
    nonisolated static func framedStill(at fileURL: URL, framing: MediaFraming) -> UIImage? {
        guard let image = UIImage(contentsOfFile: fileURL.path) else { return nil }
        let normalized = MediaAspect.normalized(image)
        let crop = framing.rect(in: normalized.size)
        return MediaAspect.crop(normalized, to: crop) ?? normalized
    }

    private func setupNoteOverlay() {
        noteOverlay.translatesAutoresizingMaskIntoConstraints = false
        noteOverlay.onTap = { [weak self] in
            self?.presentNoteComposer()
        }
        view.addSubview(noteOverlay)
        NSLayoutConstraint.activate([
            noteOverlay.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            noteOverlay.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            noteOverlay.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            noteOverlay.heightAnchor.constraint(
                equalTo: view.heightAnchor, multiplier: 0.42
            )
        ])
        noteOverlay.configure(itemId: item.id)
        applyNoteOverlayVisibility()
        noteObserver = NotificationCenter.default.addObserver(
            forName: MediaNoteStore.didChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] note in
            guard let self else { return }
            if let changedId = note.object as? String, changedId != self.item.id {
                return
            }
            self.noteOverlay.reload()
            self.applyNoteOverlayVisibility()
        }
    }

    private func applyNoteOverlayVisibility() {
        guard MediaNoteStore.shouldShowOverlay(forId: item.id) else {
            noteOverlay.isHidden = true
            return
        }
        noteOverlay.isHidden = isZoomed
    }

    private func presentNoteComposer() {
        let nav = MediaNoteComposerViewController.makeNavigation(itemId: item.id)
        present(nav, animated: true)
    }
}
