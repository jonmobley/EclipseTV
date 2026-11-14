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
/// Scroll/zoom stay on PDFKit; we observe offset via KVO so we never replace
/// `PDFView`'s scroll-view delegate (which would break pinch-zoom).
final class PDFRemoteViewController: UIViewController {

    // MARK: - Properties

    let document: SavedPDF
    private let fileURL: URL
    private var pdfView: PDFView?
    /// Display-only copy of the document behind the frame, kept aligned with
    /// `pdfView` so the page around the audience frame shows dimmed.
    private var contextPDFView: PDFView?
    private let frameOverlay = PDFAudienceFrameView()
    private var stageView: PDFReaderStageView?
    private var panelView: UIView?
    private let pageRibbon = PDFPageRibbonView()
    private var ribbonHeight: NSLayoutConstraint?
    private var lastPanelFrame: CGRect = .zero
    private var offsetObservation: NSKeyValueObservation?
    private weak var observedScrollView: UIScrollView?
    private var isSyncingScroll = false
    /// Snap sizes for the pinch in progress (page fills the frame's width / height).
    private var pinchSnapTargets: [CGFloat] = []
    /// The snap size the pinch is currently holding on, if any.
    private var heldSnapScale: CGFloat?
    private let snapHaptic = UIImpactFeedbackGenerator(style: .light)

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

    /// Turns with the phone: the audience frame keeps the output shape either way,
    /// so a turned phone just gives the framed page more room.
    override var supportedInterfaceOrientations: UIInterfaceOrientationMask {
        .allButUpsideDown
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        guard isBeingDismissed || isMovingFromParent
            || navigationController?.isBeingDismissed == true else { return }
        // Put the grid behind it back upright if the reader was read sideways.
        restoreUprightSceneGeometry()
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

        let context = makeContextPDFView(for: document)
        stage.insertSubview(context, at: 0)
        contextPDFView = context
        frameOverlay.translatesAutoresizingMaskIntoConstraints = true
        frameOverlay.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        stage.addSubview(frameOverlay)

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
        alignContextView()
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

        let panel = PDFReaderViewportLayout.panelRect(in: bounds)
        if !force, panel == lastPanelFrame { return }
        lastPanelFrame = panel

        if panelView == nil {
            let host = UIView(frame: panel)
            host.backgroundColor = .black
            host.clipsToBounds = true
            stage.insertSubview(host, belowSubview: frameOverlay)
            panelView = host
            host.addSubview(pdf)
        }
        panelView?.frame = panel
        guard let panelView else { return }
        frameOverlay.frame = bounds
        frameOverlay.frameRect = panel
        stage.panelRect = panel
        contextPDFView?.frame = PDFReaderViewportLayout.contextRect(for: panel, in: bounds)

        PresentationViewController.applyRotatedLayout(
            to: pdf, in: panelView, scale: 1, rotationDegrees: 0
        )

        // Fit once for the new panel size, then allow pinch beyond fit.
        pdf.autoScales = true
        let fit = max(pdf.scaleFactorForSizeToFit, 0.01)
        pdf.minScaleFactor = fit * 0.5
        pdf.maxScaleFactor = fit * 5
        observeScrollViewIfNeeded()
        alignContextView()
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
        stageView?.forwardingTarget = scroll
        // Added after the scroll view's own handler, so it sees the zoom the
        // scroll view just applied and can hold it on a snap size.
        scroll.pinchGestureRecognizer?.addTarget(self, action: #selector(pinchChanged(_:)))
        offsetObservation = scroll.observe(\.contentOffset, options: [.new]) { [weak self] _, _ in
            guard let self else { return }
            self.alignContextView()
            guard !self.isSyncingScroll else { return }
            self.pushSyncState()
        }
    }

    // MARK: - Zoom snap

    /// Makes the pinch catch where the page exactly fills the audience frame's
    /// width or height: within `PDFZoomSnap.holdBand` of one, the zoom holds there
    /// (with a light tap) until the pinch moves well past it.
    @objc private func pinchChanged(_ pinch: UIPinchGestureRecognizer) {
        guard let pdf = pdfView, let scroll = pdf.eclipse_scrollView else { return }
        switch pinch.state {
        case .began:
            pinchSnapTargets = currentSnapTargets()
            heldSnapScale = nil
            snapHaptic.prepare()
        case .changed:
            let target = PDFZoomSnap.target(for: pdf.scaleFactor, in: pinchSnapTargets)
            if let target, target != heldSnapScale {
                snapHaptic.impactOccurred()
                snapHaptic.prepare()
            }
            heldSnapScale = target
            if let target { hold(scroll, pdf: pdf, atScale: target, around: pinch) }
        default:
            if let held = heldSnapScale, pinch.state == .ended {
                hold(scroll, pdf: pdf, atScale: held, around: pinch)
            }
            heldSnapScale = nil
            pinchSnapTargets = []
        }
    }

    /// Snap sizes for the current page against the audience frame.
    private func currentSnapTargets() -> [CGFloat] {
        guard let pdf = pdfView, let panelView,
              let page = pdf.currentPage ?? pdf.document?.page(at: 0),
              pdf.scaleFactor > 0 else { return [] }
        let drawn = pdf.convert(page.bounds(for: pdf.displayBox), from: page)
        let atScaleOne = CGSize(
            width: drawn.width / pdf.scaleFactor,
            height: drawn.height / pdf.scaleFactor
        )
        return PDFZoomSnap.targets(
            pageSizeAtScaleOne: atScaleOne,
            container: panelView.bounds.size,
            range: pdf.minScaleFactor...pdf.maxScaleFactor
        )
    }

    /// Sets the zoom to `scale` while keeping the content under the fingers in place.
    private func hold(
        _ scroll: UIScrollView,
        pdf: PDFView,
        atScale scale: CGFloat,
        around pinch: UIPinchGestureRecognizer
    ) {
        let current = pdf.scaleFactor
        guard current > 0, abs(current - scale) > 0.0001,
              let content = scroll.delegate?.viewForZooming?(in: scroll) else { return }
        let anchor = pinch.location(in: scroll)
        let anchorInContent = scroll.convert(anchor, to: content)
        scroll.setZoomScale(scroll.zoomScale * scale / current, animated: false)
        let moved = content.convert(anchorInContent, to: scroll)
        var offset = scroll.contentOffset
        offset.x += moved.x - anchor.x
        offset.y += moved.y - anchor.y
        let minX = -scroll.adjustedContentInset.left
        let minY = -scroll.adjustedContentInset.top
        let maxX = max(minX, scroll.contentSize.width - scroll.bounds.width + scroll.adjustedContentInset.right)
        let maxY = max(minY, scroll.contentSize.height - scroll.bounds.height + scroll.adjustedContentInset.bottom)
        offset.x = min(max(offset.x, minX), maxX)
        offset.y = min(max(offset.y, minY), maxY)
        scroll.contentOffset = offset
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
