//
//  PDFReaderDriver.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import PDFKit
import UIKit

/// One interactive phone `PDFView` that can drive the live PDF on the TV.
///
/// Shared by the Show hero (`LiveHeaderView+PDFPreview`) and the full-screen
/// reader (`PDFRemoteViewController`): presets (Fit / Fill / Two Pages),
/// page-by-page scrolling, the pinch that catches at fill-width / fill-height,
/// and reporting the view to `ExternalDisplayManager.setPDFViewState`.
///
/// Only one driver talks to the TV at a time (`PDFReaderDriver.active`). The
/// reader takes over while it is open; when it closes the hero takes back over
/// from the state the reader left, so the two always agree with the TV.
///
/// Scroll and zoom stay on PDFKit: the driver watches the offset by KVO and
/// adds targets to the scroll view's own recognizers, never its delegate (that
/// would break pinch zoom).
@MainActor
final class PDFReaderDriver: NSObject {

    /// The driver whose changes reach the TV, if any.
    private(set) static weak var active: PDFReaderDriver?
    /// Posted when a driver stops driving (the reader closed), so a waiting one can take over.
    static let didResignNotification = Notification.Name("PDFReaderDriver.didResign")

    let pdfView = PDFView()
    let documentId: UUID
    /// False for a private Preview: it never touches the TV or the shared state.
    let drivesOutput: Bool
    /// Called after every page / zoom / scroll change (for counters, dimmed copies).
    var onChange: (() -> Void)?
    /// Called when the chosen preset or page-by-page setting changes (for buttons).
    var onOptionsChange: (() -> Void)?

    private(set) var state: PDFLiveViewState
    private var offsetObservation: NSKeyValueObservation?
    private weak var observedScrollView: UIScrollView?
    /// True while a page-by-page settle animates, so it isn't re-framed mid-way.
    private var isSettling = false
    /// True while a preset is being applied (it moves the page and re-posts).
    private var isFraming = false
    private var lastLaidOutSize: CGSize = .zero
    private var needsRestore = true

    // Pinch catch (see `PDFZoomSnap`).
    private var pinchSnapTargets: [CGFloat] = []
    private var heldSnapScale: CGFloat?
    private var pinchStartScale: CGFloat = 0
    private var pinchStartSpan: CGFloat = 0
    private var pinchSpan: CGFloat = 0
    private var pinchHasHeld = false
    private let snapHaptic = UIImpactFeedbackGenerator(style: .light)

    // MARK: - Init

    /// - Parameters:
    ///   - document: The opened PDF.
    ///   - documentId: Saved id; the driver only drives the TV while this is the live PDF.
    ///   - drivesOutput: False for a phone-only Preview.
    init(document: PDFDocument, documentId: UUID, drivesOutput: Bool) {
        self.documentId = documentId
        self.drivesOutput = drivesOutput
        let mgr = ExternalDisplayManager.shared
        state = drivesOutput && mgr.livePDFDocumentId == documentId
            ? mgr.pdfViewState : PDFLiveViewState()
        super.init()
        pdfView.displayMode = state.isTwoUp ? .twoUpContinuous : .singlePageContinuous
        pdfView.displayDirection = .vertical
        pdfView.displaysPageBreaks = true
        pdfView.autoScales = true
        pdfView.backgroundColor = .black
        pdfView.isUserInteractionEnabled = true
        pdfView.usePageViewController(false)
        pdfView.document = document
        NotificationCenter.default.addObserver(
            self, selector: #selector(pdfViewChanged),
            name: .PDFViewScaleChanged, object: pdfView
        )
        NotificationCenter.default.addObserver(
            self, selector: #selector(pageChanged),
            name: .PDFViewPageChanged, object: pdfView
        )
    }

    /// Whether this driver may move the TV right now (Live Lock, Blackout hold and
    /// the like turn it off for the hero). The view still scrolls and pinches.
    var allowsOutput: () -> Bool = { true }

    /// Stops listening to the PDF view's scroll view. Call before letting go of the
    /// driver: its pinch / pan recognizers keep unretained targets, and a hero torn
    /// down mid-gesture would otherwise message a freed driver.
    func detach() {
        if let scroll = observedScrollView {
            scroll.pinchGestureRecognizer?.removeTarget(self, action: #selector(pinchChanged(_:)))
            scroll.panGestureRecognizer.removeTarget(self, action: #selector(panChanged(_:)))
        }
        observedScrollView = nil
        offsetObservation?.invalidate()
        offsetObservation = nil
        NotificationCenter.default.removeObserver(self)
    }

    deinit {
        offsetObservation?.invalidate()
        NotificationCenter.default.removeObserver(self)
    }

    // MARK: - Driving

    /// Whether this driver's changes reach the TV right now.
    var isActive: Bool { Self.active === self }

    /// Makes this the driver the TV follows, first catching up with where the
    /// previous one left the shared state.
    func becomeActive() {
        guard drivesOutput, !isActive,
              ExternalDisplayManager.shared.livePDFDocumentId == documentId else { return }
        Self.active = self
        state = ExternalDisplayManager.shared.pdfViewState
        needsRestore = true
        restoreIfPossible()
        onOptionsChange?()
    }

    /// Stops driving; a waiting driver (the hero) may take over.
    func resignActive() {
        guard isActive else { return }
        Self.active = nil
        NotificationCenter.default.post(name: Self.didResignNotification, object: self)
    }

    // MARK: - Layout

    /// Frames the PDF to fill `container` (the audience frame). Re-applies the
    /// preset only when the frame's size changes, so layout never undoes a pinch.
    func layout(in container: UIView) {
        if pdfView.superview !== container {
            container.addSubview(pdfView)
        }
        let size = container.bounds.size
        guard size.width > 0, size.height > 0 else { return }
        pdfView.transform = .identity
        pdfView.frame = container.bounds
        observeScrollViewIfNeeded()
        guard size != lastLaidOutSize else {
            restoreIfPossible()
            return
        }
        lastLaidOutSize = size
        pdfView.layoutIfNeeded()
        updateScaleLimits()
        needsRestore = true
        restoreIfPossible()
    }

    // MARK: - Options

    /// Fit, Fill or Two Pages, centred on the page being read.
    func apply(_ preset: PDFViewPreset, animated: Bool = true) {
        state.preset = preset
        setTwoUp(preset.isTwoUp)
        applyPresetGeometry(preset, animated: animated)
        stateChanged()
        onOptionsChange?()
    }

    /// Page by page on or off. Turning it on settles on the nearest page now.
    func setSnapsToPages(_ snaps: Bool) {
        state.snapsToPages = snaps
        if snaps, let scroll = pdfView.eclipse_scrollView,
           let target = snapTarget(in: scroll, velocityY: 0) {
            settle(scroll, atY: target)
        }
        stateChanged()
        onOptionsChange?()
    }

    /// Moves to a page, keeping the current preset's framing.
    func go(toPageAt index: Int) {
        guard let page = pdfView.document?.page(at: index) else { return }
        pdfView.go(to: page)
        if let preset = state.preset {
            applyPresetGeometry(preset, animated: false)
        }
        stateChanged()
    }

    // MARK: - Private: presets

    private func setTwoUp(_ twoUp: Bool) {
        state.isTwoUp = twoUp
        let mode: PDFDisplayMode = twoUp ? .twoUpContinuous : .singlePageContinuous
        guard pdfView.displayMode != mode else { return }
        let page = pdfView.currentPage
        pdfView.displayMode = mode
        pdfView.layoutDocumentView()
        if let page { pdfView.go(to: page) }
        updateScaleLimits()
    }

    /// Pages in the row that holds `page` (one, or the pair in two-page view).
    private func rowPages(containing page: PDFPage) -> [PDFPage] {
        guard let doc = pdfView.document else { return [page] }
        let index = doc.index(for: page)
        guard state.isTwoUp else { return [page] }
        let first = index - index % 2
        return [first, first + 1].compactMap { doc.page(at: $0) }
    }

    /// A row's rectangle in the scroll view's content coordinates.
    private func rowRect(_ pages: [PDFPage], in scroll: UIScrollView) -> CGRect? {
        let rects = pages.map { page in
            pdfView.convert(pdfView.convert(page.bounds(for: pdfView.displayBox), from: page), to: scroll)
        }
        guard var union = rects.first else { return nil }
        for rect in rects.dropFirst() { union = union.union(rect) }
        return union
    }

    private func applyPresetGeometry(_ preset: PDFViewPreset, animated: Bool) {
        guard let page = pdfView.currentPage ?? pdfView.document?.page(at: 0),
              let scroll = pdfView.eclipse_scrollView,
              pdfView.scaleFactor > 0,
              let row = rowRect(rowPages(containing: page), in: scroll),
              !isFraming else { return }
        isFraming = true
        defer { isFraming = false }
        let atOne = CGSize(width: row.width / pdfView.scaleFactor, height: row.height / pdfView.scaleFactor)
        guard let scale = PDFViewMath.scale(
            for: preset, rowSizeAtScaleOne: atOne, container: pdfView.bounds.size
        ) else { return }
        pdfView.minScaleFactor = min(pdfView.minScaleFactor, scale)
        pdfView.maxScaleFactor = max(pdfView.maxScaleFactor, scale)
        pdfView.autoScales = false
        pdfView.scaleFactor = scale
        pdfView.layoutIfNeeded()
        if let placed = rowRect(rowPages(containing: page), in: scroll) {
            let bounds = scroll.bounds.size
            let y = preset == .fill && placed.height > bounds.height
                ? placed.minY
                : placed.midY - bounds.height / 2
            let target = clampedOffset(CGPoint(x: placed.midX - bounds.width / 2, y: y), in: scroll)
            scroll.setContentOffset(target, animated: animated)
        }
    }

    private func updateScaleLimits() {
        let fit = max(pdfView.scaleFactorForSizeToFit, 0.01)
        var low = fit * 0.5
        var high = fit * 5
        if let page = pdfView.currentPage ?? pdfView.document?.page(at: 0) {
            let size = page.bounds(for: pdfView.displayBox).size
            let row = CGSize(width: size.width * (state.isTwoUp ? 2 : 1), height: size.height)
            if let fitPage = PDFViewMath.scale(for: .fit, rowSizeAtScaleOne: row, container: pdfView.bounds.size),
               let fill = PDFViewMath.scale(for: .fill, rowSizeAtScaleOne: row, container: pdfView.bounds.size) {
                low = min(low, fitPage * 0.75)
                high = max(high, fill * 4)
            }
        }
        pdfView.minScaleFactor = low
        pdfView.maxScaleFactor = high
    }

    /// Puts the view where `state` says, once it has a size.
    private func restoreIfPossible() {
        guard needsRestore, pdfView.bounds.width > 0, pdfView.document != nil,
              let scroll = pdfView.eclipse_scrollView else { return }
        needsRestore = false
        setTwoUp(state.isTwoUp)
        if let page = pdfView.document?.page(at: state.pageIndex) {
            pdfView.go(to: page)
        }
        if let preset = state.preset {
            applyPresetGeometry(preset, animated: false)
        } else {
                let fit = max(pdfView.scaleFactorForSizeToFit, 0.01)
            pdfView.autoScales = false
            pdfView.scaleFactor = max(state.relativeScale, 0.1) * fit
            pdfView.layoutIfNeeded()
            let range = offsetRange(in: scroll)
            scroll.contentOffset = CGPoint(
                x: range.minX + range.width * state.progress.x,
                y: range.minY + range.height * state.progress.y
            )
            }
        stateChanged()
    }

    // MARK: - Private: tracking

    private func observeScrollViewIfNeeded() {
        guard let scroll = pdfView.eclipse_scrollView, observedScrollView !== scroll else { return }
        offsetObservation?.invalidate()
        observedScrollView = scroll
        // Added after the scroll view's own handlers, so they see what it just did.
        scroll.pinchGestureRecognizer?.addTarget(self, action: #selector(pinchChanged(_:)))
        scroll.panGestureRecognizer.addTarget(self, action: #selector(panChanged(_:)))
        offsetObservation = scroll.observe(\.contentOffset, options: [.new]) { [weak self] _, _ in
            MainActor.assumeIsolated { self?.stateChanged() }
        }
    }

    @objc private func pdfViewChanged() {
        observeScrollViewIfNeeded()
        stateChanged()
    }

    /// A jump to another page that the user didn't scroll to (the page strip)
    /// keeps the chosen preset's framing, so Fit still shows the whole page.
    @objc private func pageChanged() {
        observeScrollViewIfNeeded()
        if let preset = state.preset, !isSettling,
           let scroll = observedScrollView,
           !scroll.isTracking, !scroll.isDragging, !scroll.isDecelerating {
            applyPresetGeometry(preset, animated: false)
        }
        stateChanged()
    }

    /// Reads the view into `state` and hands it on.
    private func stateChanged() {
        guard let scroll = pdfView.eclipse_scrollView, pdfView.bounds.width > 0 else {
            onChange?()
            return
        }
        if let page = pdfView.currentPage, let doc = pdfView.document {
            state.pageIndex = doc.index(for: page)
        }
        let range = offsetRange(in: scroll)
        state.progress = CGPoint(
            x: range.width > 0 ? min(max((scroll.contentOffset.x - range.minX) / range.width, 0), 1) : 0,
            y: range.height > 0 ? min(max((scroll.contentOffset.y - range.minY) / range.height, 0), 1) : 0
        )
        state.relativeScale = pdfView.scaleFactor / max(pdfView.scaleFactorForSizeToFit, 0.01)
        if drivesOutput, isActive, allowsOutput() {
            ExternalDisplayManager.shared.setPDFViewState(state)
        }
        onChange?()
    }

    private func offsetRange(in scroll: UIScrollView) -> CGRect {
        let inset = scroll.adjustedContentInset
        let minX = -inset.left
        let minY = -inset.top
        let maxX = max(minX, scroll.contentSize.width - scroll.bounds.width + inset.right)
        let maxY = max(minY, scroll.contentSize.height - scroll.bounds.height + inset.bottom)
        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }

    private func clampedOffset(_ point: CGPoint, in scroll: UIScrollView) -> CGPoint {
        let range = offsetRange(in: scroll)
        return CGPoint(
            x: min(max(point.x, range.minX), range.maxX),
            y: min(max(point.y, range.minY), range.maxY)
        )
    }

    // MARK: - Private: page by page

    @objc private func panChanged(_ pan: UIPanGestureRecognizer) {
        guard state.snapsToPages, pan.state == .ended || pan.state == .cancelled,
              let scroll = observedScrollView else { return }
        let velocity = -pan.velocity(in: scroll).y
        guard let target = snapTarget(in: scroll, velocityY: velocity) else { return }
        // After the scroll view has started its own glide, which this replaces.
        DispatchQueue.main.async { [weak self] in
            self?.settle(scroll, atY: target)
        }
    }

    private func settle(_ scroll: UIScrollView, atY y: CGFloat) {
        isSettling = true
        scroll.setContentOffset(CGPoint(x: scroll.contentOffset.x, y: y), animated: true)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) { [weak self] in
            self?.isSettling = false
        }
    }

    private func snapTarget(in scroll: UIScrollView, velocityY: CGFloat) -> CGFloat? {
        guard let doc = pdfView.document, doc.pageCount > 0 else { return nil }
        var rows: [ClosedRange<CGFloat>] = []
        let step = state.isTwoUp ? 2 : 1
        var index = 0
        while index < doc.pageCount {
            let pages = (index..<min(index + step, doc.pageCount)).compactMap { doc.page(at: $0) }
            if let rect = rowRect(pages, in: scroll) {
                rows.append(rect.minY...rect.maxY)
            }
            index += step
        }
        let range = offsetRange(in: scroll)
        let offset = scroll.contentOffset.y
        return PDFViewMath.snapOffset(
            rows: rows,
            offset: offset,
            projected: PDFViewMath.projectedOffset(offset, velocity: velocityY),
            viewport: scroll.bounds.height,
            range: range.minY...range.maxY
        )
    }

    // MARK: - Private: pinch

    /// Catches where the page exactly fills the frame's width or height: within
    /// `PDFZoomSnap.holdBand` the zoom holds there (light tap) until the pinch
    /// moves well past it. Once a pinch has held, the zoom follows finger spread,
    /// since the scroll view would otherwise pinch on from the held zoom forever.
    @objc private func pinchChanged(_ pinch: UIPinchGestureRecognizer) {
        guard let scroll = observedScrollView else { return }
        switch pinch.state {
        case .began:
            if state.preset != nil {
                state.preset = nil
                onOptionsChange?()
            }
            pinchSnapTargets = currentSnapTargets()
            heldSnapScale = nil
            pinchHasHeld = false
            pinchStartScale = pdfView.scaleFactor
            pinchStartSpan = fingerSpan(of: pinch) ?? 0
            pinchSpan = pinchStartSpan
            snapHaptic.prepare()
        case .changed:
            if let span = fingerSpan(of: pinch) { pinchSpan = span }
            let fingers = PDFZoomSnap.fingerScale(
                startScale: pinchStartScale,
                startSpan: pinchStartSpan,
                span: pinchSpan,
                range: pdfView.minScaleFactor...pdfView.maxScaleFactor
            ) ?? pdfView.scaleFactor
            let target = PDFZoomSnap.target(for: fingers, in: pinchSnapTargets)
            if let target, target != heldSnapScale {
                snapHaptic.impactOccurred()
                snapHaptic.prepare()
            }
            heldSnapScale = target
            if let target {
                pinchHasHeld = true
                hold(scroll, atScale: target, around: pinch)
            } else if pinchHasHeld {
                hold(scroll, atScale: fingers, around: pinch)
            }
        default:
            if let held = heldSnapScale, pinch.state == .ended {
                hold(scroll, atScale: held, around: pinch)
            }
            heldSnapScale = nil
            pinchHasHeld = false
            pinchSnapTargets = []
        }
    }

    private func fingerSpan(of pinch: UIPinchGestureRecognizer) -> CGFloat? {
        guard pinch.numberOfTouches >= 2 else { return nil }
        let a = pinch.location(ofTouch: 0, in: pdfView)
        let b = pinch.location(ofTouch: 1, in: pdfView)
        return hypot(a.x - b.x, a.y - b.y)
    }

    private func currentSnapTargets() -> [CGFloat] {
        guard let page = pdfView.currentPage ?? pdfView.document?.page(at: 0),
              let scroll = observedScrollView,
              pdfView.scaleFactor > 0,
              let row = rowRect(rowPages(containing: page), in: scroll) else { return [] }
        let atScaleOne = CGSize(
            width: row.width / pdfView.scaleFactor,
            height: row.height / pdfView.scaleFactor
        )
        return PDFZoomSnap.targets(
            pageSizeAtScaleOne: atScaleOne,
            container: pdfView.bounds.size,
            range: pdfView.minScaleFactor...pdfView.maxScaleFactor
        )
    }

    /// Sets the zoom to `scale` while keeping the content under the fingers in place.
    private func hold(_ scroll: UIScrollView, atScale scale: CGFloat, around pinch: UIPinchGestureRecognizer) {
        let current = pdfView.scaleFactor
        guard current > 0, abs(current - scale) > 0.0001,
              let content = scroll.delegate?.viewForZooming?(in: scroll) else { return }
        let anchor = pinch.location(in: scroll)
        let anchorInContent = scroll.convert(anchor, to: content)
        scroll.setZoomScale(scroll.zoomScale * scale / current, animated: false)
        let moved = content.convert(anchorInContent, to: scroll)
        var offset = scroll.contentOffset
        offset.x += moved.x - anchor.x
        offset.y += moved.y - anchor.y
        scroll.contentOffset = clampedOffset(offset, in: scroll)
    }
}
