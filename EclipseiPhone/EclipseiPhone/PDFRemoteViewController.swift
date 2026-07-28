//
//  PDFRemoteViewController.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import UIKit
import PDFKit

/// Phone-side PDF reader that drives a live AirPlay PDFView.
///
/// Stages a Display Mode aspect panel. Closing dismisses the phone UI only —
/// AirPlay stays live via `livePDFDocumentId`.
///
/// Scroll/zoom stay on PDFKit; we observe offset via KVO so we never replace
/// `PDFView`'s scroll-view delegate (which would break pinch-zoom).
final class PDFRemoteViewController: UIViewController {

    // MARK: - Properties

    let document: SavedPDF
    private let fileURL: URL
    private var pdfView: PDFView?
    private var stageView: UIView?
    private var panelView: UIView?
    private var lastPanelFrame: CGRect = .zero
    private var offsetObservation: NSKeyValueObservation?
    private weak var observedScrollView: UIScrollView?
    private var isSyncingScroll = false

    // MARK: - Init

    /// Creates a remote for a saved PDF. `fileURL` must exist on disk.
    init(document: SavedPDF, fileURL: URL) {
        self.document = document
        self.fileURL = fileURL
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        title = document.title
        navigationItem.largeTitleDisplayMode = .never
        let close = UIBarButtonItem(
            barButtonSystemItem: .close,
            target: self,
            action: #selector(closeTapped)
        )
        close.accessibilityHint = "Closes the remote. The TV keeps showing this PDF."
        navigationItem.rightBarButtonItem = close
        setupPDFView()
        observePresentationChanges()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        ExternalDisplayManager.shared.refreshConnection()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        layoutPhonePDFViewport(force: false)
        observeScrollViewIfNeeded()
    }

    deinit {
        offsetObservation?.invalidate()
        NotificationCenter.default.removeObserver(self)
    }

    // MARK: - Setup

    private func setupPDFView() {
        let stage = UIView()
        stage.backgroundColor = .black
        stage.clipsToBounds = true
        stage.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stage)
        stageView = stage

        let inset: CGFloat = 12
        let guide = view.safeAreaLayoutGuide
        NSLayoutConstraint.activate([
            stage.topAnchor.constraint(equalTo: guide.topAnchor, constant: inset),
            stage.bottomAnchor.constraint(equalTo: guide.bottomAnchor, constant: -inset),
            stage.leadingAnchor.constraint(equalTo: guide.leadingAnchor, constant: inset),
            stage.trailingAnchor.constraint(equalTo: guide.trailingAnchor, constant: -inset)
        ])

        let pdf = PDFView()
        pdf.displayMode = .singlePageContinuous
        pdf.displayDirection = .vertical
        pdf.autoScales = true
        pdf.backgroundColor = .black
        pdf.isUserInteractionEnabled = true
        pdf.usePageViewController(false)
        stage.addSubview(pdf)
        pdfView = pdf

        guard let document = PDFDocument(url: fileURL), document.pageCount > 0 else {
            DispatchQueue.main.async { [weak self] in
                self?.presentPDFOpenFailure()
            }
            return
        }
        pdf.document = document

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(pdfViewChanged),
            name: .PDFViewScaleChanged,
            object: pdf
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(pdfViewChanged),
            name: .PDFViewPageChanged,
            object: pdf
        )
    }

    private func presentPDFOpenFailure() {
        let alert = UIAlertController(
            title: "Couldn't Open PDF",
            message: "That file may be damaged or unreadable.",
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "OK", style: .default) { [weak self] _ in
            ExternalDisplayManager.shared.stopPDFAndRestoreLibrary()
            self?.closeTapped()
        })
        present(alert, animated: true)
    }

    @objc private func pdfViewChanged() {
        observeScrollViewIfNeeded()
        pushPageIndex()
        pushSyncState()
    }

    /// Fits the PDF into the Display Mode panel. Skips when the panel is unchanged
    /// so layout passes don't reset the user's zoom.
    private func layoutPhonePDFViewport(force: Bool) {
        guard let stage = stageView, let pdf = pdfView else { return }
        let bounds = stage.bounds
        guard bounds.width > 0, bounds.height > 0 else { return }

        let panel = ExternalOutputSettings.displayModePanelRect(in: bounds)
        if !force, panel == lastPanelFrame { return }
        lastPanelFrame = panel

        if panelView == nil {
            let host = UIView(frame: panel)
            host.backgroundColor = .black
            host.clipsToBounds = true
            stage.addSubview(host)
            panelView = host
            host.addSubview(pdf)
        }
        panelView?.frame = panel
        guard let panelView else { return }

        PresentationViewController.applyRotatedLayout(
            to: pdf, in: panelView, scale: 1, rotationDegrees: 0
        )

        // Fit once for the new panel size, then allow pinch beyond fit.
        pdf.autoScales = true
        let fit = max(pdf.scaleFactorForSizeToFit, 0.01)
        pdf.minScaleFactor = fit * 0.5
        pdf.maxScaleFactor = fit * 5
        observeScrollViewIfNeeded()
        pushPageIndex()
        pushSyncState()
    }

    /// Watches scroll offset without becoming the scroll view's delegate.
    private func observeScrollViewIfNeeded() {
        guard let scroll = pdfView?.eclipse_scrollView else { return }
        if observedScrollView === scroll { return }
        offsetObservation?.invalidate()
        observedScrollView = scroll
        offsetObservation = scroll.observe(\.contentOffset, options: [.new]) { [weak self] _, _ in
            guard let self, !self.isSyncingScroll else { return }
            self.pushSyncState()
        }
    }

    // MARK: - Sync

    private func pushPageIndex() {
        guard let pdf = pdfView,
              let page = pdf.currentPage,
              let doc = pdf.document else { return }
        ExternalDisplayManager.shared.setPDFPageIndex(doc.index(for: page))
    }

    private func pushSyncState() {
        guard let pdf = pdfView, let scroll = pdf.eclipse_scrollView else { return }
        let maxY = scroll.contentSize.height - scroll.bounds.height
        let progress = maxY > 0 ? min(max(scroll.contentOffset.y / maxY, 0), 1) : 0
        let fit = max(pdf.scaleFactorForSizeToFit, 0.01)
        let relative = pdf.scaleFactor / fit
        ExternalDisplayManager.shared.setPDFScrollProgress(progress)
        ExternalDisplayManager.shared.setPDFRelativeScale(relative)
    }

    // MARK: - Actions

    @objc private func closeTapped() {
        if let nav = navigationController, nav.viewControllers.count > 1 {
            nav.popViewController(animated: true)
        } else {
            dismiss(animated: true)
        }
    }

    @objc private func pdfEndedExternally() {
        closeTapped()
    }

    @objc private func outputSettingsChanged() {
        lastPanelFrame = .zero
        layoutPhonePDFViewport(force: true)
        ExternalDisplayManager.shared.reloadPDFLayout()
    }

    // MARK: - Observers

    private func observePresentationChanges() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(pdfEndedExternally),
            name: ExternalDisplayManager.pdfDidEndNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(outputSettingsChanged),
            name: ExternalOutputSettings.didChangeNotification,
            object: nil
        )
    }
}
