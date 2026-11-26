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
/// Frames the page the way the audience sees it (Display Mode aspect or custom
/// screen size), with or without a projector, in both phone orientations — see
/// `PDFReaderViewportLayout`. The framed panel is the exact TV mirror; a
/// display-only copy behind it shows the surrounding page dimmed
/// (`PDFAudienceFrameView`), and drags anywhere on the stage move the frame's
/// PDF (`PDFReaderStageView`). A page counter and
/// thumbnail ribbon sit beneath it for multi-page documents. Closing dismisses
/// the phone UI only — AirPlay stays live via `livePDFDocumentId`.
///
/// The page itself, its presets (Fit / Fill / Two Pages, top right), page-by-page
/// scrolling and the pinch catch live in `PDFReaderDriver`, shared with the
/// Show hero; while the reader is open its driver is the one the TV follows.
final class PDFRemoteViewController: UIViewController {

    // MARK: - Properties

    let document: SavedPDF
    private let fileURL: URL
    private var driver: PDFReaderDriver?
    private var pdfView: PDFView? { driver?.pdfView }
    /// Display-only copy of the document behind the frame, kept aligned with
    /// `pdfView` so the page around the audience frame shows dimmed.
    private var contextPDFView: PDFView?
    private let frameOverlay = PDFAudienceFrameView()
    private var stageView: PDFReaderStageView?
    private var panelView: UIView?
    private let pageRibbon = PDFPageRibbonView()
    private let optionsBar = PDFViewOptionsBar(buttonSize: 32)
    private var ribbonHeight: NSLayoutConstraint?
    private var lastPanelFrame: CGRect = .zero

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

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        driver?.becomeActive()
    }

    /// Turns with the phone: the audience frame keeps the output shape either way,
    /// so a turned phone just gives the framed page more room.
    override var supportedInterfaceOrientations: UIInterfaceOrientationMask {
        .allButUpsideDown
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        guard isBeingDismissed || isMovingFromParent
            || navigationController?.isBeingDismissed == true else { return }
        // The hero takes back over from where the reader left the page.
        driver?.resignActive()
        // Put the grid behind it back upright if the reader was read sideways.
        restoreUprightSceneGeometry()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        layoutPhonePDFViewport(force: false)
        stageView?.forwardingTarget = pdfView?.eclipse_scrollView
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    // MARK: - Setup

    /// Stage on top, page ribbon pinned beneath it. The ribbon starts collapsed and
    /// only opens once a multi-page document has loaded.
    private func setupStageAndRibbon() -> UIView {
        let stage = PDFReaderStageView()
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
        // multi-page document opens); `PDFReaderViewportLayout` insets the
        // audience frame inside it.
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

    /// Non-interactive copy of the document behind the frame. Scale and offset
    /// follow `pdfView` (`alignContextView`); it never talks to the TV.
    private func makeContextPDFView(for document: PDFDocument) -> PDFView {
        let context = PDFView()
        context.displayMode = .singlePageContinuous
        context.displayDirection = .vertical
        context.autoScales = false
        context.backgroundColor = .black
        context.isUserInteractionEnabled = false
        context.accessibilityElementsHidden = true
        context.usePageViewController(false)
        context.document = document
        return context
    }

    private func setupPDFView() {
        let stage = setupStageAndRibbon()

        guard let pdfDocument = PDFDocument(url: fileURL), pdfDocument.pageCount > 0 else {
            DispatchQueue.main.async { [weak self] in
                self?.presentPDFOpenFailure()
            }
            return
        }
        // Drives the TV only when this is the PDF on it; otherwise a private Preview.
        let mgr = ExternalDisplayManager.shared
        let drives = mgr.isPDFLive && mgr.livePDFDocumentId == document.id
        let driver = PDFReaderDriver(document: pdfDocument, documentId: document.id, drivesOutput: drives)
        self.driver = driver
        driver.onChange = { [weak self] in
            guard let self, let pdf = self.pdfView else { return }
            self.alignContextView()
            self.pageRibbon.refreshCounter(from: pdf)
            self.stageView?.forwardingTarget = pdf.eclipse_scrollView
        }
        driver.onOptionsChange = { [weak self] in self?.syncOptionsBar() }
        optionsBar.onPreset = { [weak self] preset in self?.driver?.apply(preset) }
        optionsBar.onToggleSnap = { [weak self] in
            guard let driver = self?.driver else { return }
            driver.setSnapsToPages(!driver.state.snapsToPages)
        }
        syncOptionsBar()
        configureRibbon(for: pdfDocument, pdf: driver.pdfView)

        let context = makeContextPDFView(for: pdfDocument)
        stage.insertSubview(context, at: 0)
        contextPDFView = context
        frameOverlay.translatesAutoresizingMaskIntoConstraints = true
        frameOverlay.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        stage.addSubview(frameOverlay)

        // Top right over the page, as in the Show hero. (In the navigation bar,
        // iOS 26's bar glass repainted the lit buttons as blank white blobs.)
        optionsBar.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(optionsBar)
        NSLayoutConstraint.activate([
            optionsBar.topAnchor.constraint(equalTo: stage.topAnchor, constant: 8),
            optionsBar.trailingAnchor.constraint(equalTo: stage.trailingAnchor, constant: -12)
        ])
    }

    private func syncOptionsBar() {
        guard let driver else { return }
        optionsBar.update(preset: driver.state.preset, snapsToPages: driver.state.snapsToPages)
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

    /// Sizes the audience frame for the stage. Skips when the frame is unchanged
    /// so layout passes don't reset the user's zoom.
    private func layoutPhonePDFViewport(force: Bool) {
        guard let stage = stageView, let driver else { return }
        let bounds = stage.bounds
        guard bounds.width > 0, bounds.height > 0 else { return }

        let panel = PDFReaderViewportLayout.panelRect(in: bounds)
        if !force, panel == lastPanelFrame { return }
        lastPanelFrame = panel

        if panelView == nil {
            let host = UIView(frame: panel)
            host.backgroundColor = .black
            host.clipsToBounds = true
            stage.insertSubview(host, belowSubview: frameOverlay)
            panelView = host
        }
        panelView?.frame = panel
        guard let panelView else { return }
        frameOverlay.frame = bounds
        frameOverlay.frameRect = panel
        stage.panelRect = panel
        contextPDFView?.frame = PDFReaderViewportLayout.contextRect(for: panel, in: bounds)
        driver.layout(in: panelView)
        stageView?.forwardingTarget = driver.pdfView.eclipse_scrollView
        alignContextView()
        pageRibbon.refreshCounter(from: driver.pdfView)
    }

    /// Keeps the dimmed page behind the frame lined up with the framed page:
    /// same zoom, offset shifted by the frame's top, then corrected against
    /// where PDFKit actually drew the current page in both views (it can center
    /// or inset short documents differently in the taller context view).
    private func alignContextView() {
        guard let pdf = pdfView, let context = contextPDFView, let stage = stageView,
              let panelView,
              let scroll = pdf.eclipse_scrollView,
              let contextScroll = context.eclipse_scrollView else { return }
        if context.displayMode != pdf.displayMode {
            context.displayMode = pdf.displayMode
            context.layoutDocumentView()
        }
        if abs(context.scaleFactor - pdf.scaleFactor) > 0.0001 {
            context.minScaleFactor = min(pdf.minScaleFactor, pdf.scaleFactor)
            context.maxScaleFactor = max(pdf.maxScaleFactor, pdf.scaleFactor)
            context.scaleFactor = pdf.scaleFactor
            context.layoutIfNeeded()
        }
        contextScroll.contentOffset = PDFReaderViewportLayout.contextOffset(
            forPanelOffset: scroll.contentOffset,
            panelTop: panelView.frame.minY - context.frame.minY
        )
        guard let page = pdf.currentPage ?? pdf.document?.page(at: 0) else { return }
        let anchor = page.bounds(for: pdf.displayBox).origin
        let inPanel = pdf.convert(pdf.convert(anchor, from: page), to: stage)
        let inContext = context.convert(context.convert(anchor, from: page), to: stage)
        let dx = inContext.x - inPanel.x
        let dy = inContext.y - inPanel.y
        guard abs(dx) > 0.5 || abs(dy) > 0.5 else { return }
        contextScroll.contentOffset.x += dx
        contextScroll.contentOffset.y += dy
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

    /// Relayouts when a display arrives or drops while the reader is open
    /// (the frame itself only depends on the output shape).
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
