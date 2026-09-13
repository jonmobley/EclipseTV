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
/// Stages a Display Mode aspect panel while a projector is available, and the
/// full screen otherwise — see `PDFReaderViewportLayout`. A page counter and
/// thumbnail ribbon sit beneath it for multi-page documents. Closing dismisses
/// the phone UI only — AirPlay stays live via `livePDFDocumentId`.
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
    private let pageRibbon = PDFPageRibbonView()
    private var ribbonHeight: NSLayoutConstraint?
    private var lastPanelFrame: CGRect = .zero
    /// Framing the last layout pass used, so a projector arriving or leaving
    /// relayouts even when the new panel happens to measure the same.
    private var lastPanelMatchedProjector: Bool?
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

    /// Stage on top, page ribbon pinned beneath it. The ribbon starts collapsed and
    /// only opens once a multi-page document has loaded.
    private func setupStageAndRibbon() -> UIView {
        let stage = UIView()
        stage.backgroundColor = .black
        stage.clipsToBounds = true
        stage.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stage)
        stageView = stage

        pageRibbon.isHidden = true
        pageRibbon.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(pageRibbon)
        let height = pageRibbon.heightAnchor.constraint(equalToConstant: 0)
        ribbonHeight = height

        // Stage takes the safe area down to the ribbon (zero-height until a
        // multi-page document opens); `PDFReaderViewportLayout` insets the panel
        // inside it when there is a projector to frame.
        let guide = view.safeAreaLayoutGuide
        NSLayoutConstraint.activate([
            stage.topAnchor.constraint(equalTo: guide.topAnchor),
            stage.leadingAnchor.constraint(equalTo: guide.leadingAnchor),
            stage.trailingAnchor.constraint(equalTo: guide.trailingAnchor),
            stage.bottomAnchor.constraint(equalTo: pageRibbon.topAnchor),
            pageRibbon.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            pageRibbon.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            pageRibbon.bottomAnchor.constraint(equalTo: guide.bottomAnchor),
            height
        ])
        return stage
    }

    /// Shows the page strip for documents with more than one page.
    private func configureRibbon(for document: PDFDocument, pdf: PDFView) {
        guard document.pageCount > 1 else { return }
        pageRibbon.isHidden = false
        ribbonHeight?.constant = PDFPageRibbonView.preferredHeight
        pageRibbon.attach(to: pdf)
    }

    private func setupPDFView() {
        let stage = setupStageAndRibbon()

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
        configureRibbon(for: document, pdf: pdf)

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
        if let pdfView { pageRibbon.refreshCounter(from: pdfView) }
        pushPageIndex()
        pushSyncState()
    }

    /// Fits the PDF into the reader viewport. Skips when the viewport is unchanged
    /// so layout passes don't reset the user's zoom.
    private func layoutPhonePDFViewport(force: Bool) {
        guard let stage = stageView, let pdf = pdfView else { return }
        let bounds = stage.bounds
        guard bounds.width > 0, bounds.height > 0 else { return }

        let matchesProjector = PDFReaderViewportLayout.matchesProjectorFraming
        let panel = PDFReaderViewportLayout.panelRect(
            in: bounds,
            matchesProjectorFraming: matchesProjector
        )
        if !force,
           panel == lastPanelFrame,
           matchesProjector == lastPanelMatchedProjector {
            return
        }
        lastPanelFrame = panel
        lastPanelMatchedProjector = matchesProjector

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
        pageRibbon.refreshCounter(from: pdf)
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

    /// Keeps the navigation title current after a rename (local or synced in).
    @objc private func pdfStoreChanged() {
        guard let latest = PDFStore.shared.documents.first(where: { $0.id == document.id })
        else { return }
        title = latest.title
    }

    /// Swaps between the projector panel and the full screen when a display
    /// arrives or drops while the reader is open.
    @objc private func externalDisplayChanged() {
        layoutPhonePDFViewport(force: false)
    }

    /// Re-reads the projector on foreground, because not every arrival posts:
    /// the iOS 27+ scene accessory is a polled flag with no notification behind
    /// it, so AirPlay started from Control Center over an open reader would
    /// leave the phone full-screen while the TV letterboxed. Foreground is also
    /// the safe moment to re-check — no pinch is in flight to stomp.
    @objc private func appDidBecomeActive() {
        ExternalDisplayManager.shared.refreshConnection()
        layoutPhonePDFViewport(force: false)
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
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(pdfStoreChanged),
            name: PDFStore.didChangeNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(externalDisplayChanged),
            name: ExternalDisplayManager.didChangeNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(appDidBecomeActive),
            name: UIApplication.didBecomeActiveNotification,
            object: nil
        )
    }
}
