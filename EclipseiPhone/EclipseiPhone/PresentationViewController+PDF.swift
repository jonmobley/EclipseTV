//
//  PresentationViewController+PDF.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import UIKit
import PDFKit

// MARK: - PDF Presentation

extension PresentationViewController {

    /// Lazily creates the external-display PDF view (non-interactive).
    func ensurePDFView() -> PDFView {
        if let pdfView { return pdfView }

        let view = PDFView()
        view.displayMode = ExternalDisplayManager.shared.pdfViewState.isTwoUp
            ? .twoUpContinuous : .singlePageContinuous
        view.displayDirection = .vertical
        view.displaysPageBreaks = true
        view.autoScales = true
        view.backgroundColor = .black
        view.isUserInteractionEnabled = false
        pdfContainer.addSubview(view)
        pdfView = view
        return view
    }

    /// Loads `url` into the external PDF view and applies Vertical/scale layout.
    func showPDF(url: URL) {
        hideCamera()
        hideWeb()
        hideMediaContainer()
        messageLabel.text = nil
        imageView.isHidden = true
        imageView.image = nil

        pdfContainer.isHidden = false
        let view = ensurePDFView()
        applyPDFLayout()

        if view.document?.documentURL != url {
            activityIndicator.startAnimating()
            guard let document = PDFDocument(url: url), document.pageCount > 0 else {
                view.document = nil
                activityIndicator.stopAnimating()
                messageLabel.text = "Couldn't open PDF"
                return
            }
            view.document = document
            view.autoScales = true
            activityIndicator.stopAnimating()
        }
        setPDFTwoUp(ExternalDisplayManager.shared.pdfViewState.isTwoUp)
        applyPDFViewState(ExternalDisplayManager.shared.pdfViewState)
    }

    /// Hides the PDF view without destroying it.
    func hidePDF() {
        pdfContainer.isHidden = true
        pdfView?.transform = .identity
        pdfView?.bounds = .zero
    }

    /// Tears down the PDF view entirely (Stop / clear / overlay end).
    func teardownPDF() {
        pdfView?.document = nil
        pdfView?.removeFromSuperview()
        pdfView = nil
        pdfContainer.isHidden = true
        if case .pdf = presentedSource?.content { presentedSource = nil }
    }

    /// Fills the AirPlay surface with the mode-aspect PDF panel (rotates when
    /// Vertical), then puts the page back where the phone has it.
    func applyPDFLayout() {
        guard !pdfContainer.isHidden, let pdfView else { return }
        applyRotatedLayout(to: pdfView, in: pdfContainer, scale: 1)
        pdfView.layoutIfNeeded()
        applyPDFViewState(ExternalDisplayManager.shared.pdfViewState)
    }

    /// One page or two to a row, matching the phone.
    func setPDFTwoUp(_ twoUp: Bool) {
        guard let pdfView else { return }
        let mode: PDFDisplayMode = twoUp ? .twoUpContinuous : .singlePageContinuous
        guard pdfView.displayMode != mode else { return }
        pdfView.displayMode = mode
        pdfView.layoutDocumentView()
    }

    /// Mirrors the phone's zoom (relative to fit) and scroll position.
    ///
    /// Both views have the audience frame's shape, so the same zoom relative to
    /// fit and the same fractions of the scroll range land on the same picture.
    func applyPDFViewState(_ state: PDFLiveViewState) {
        guard let pdfView, !pdfContainer.isHidden, pdfView.document != nil,
              pdfView.bounds.width > 0 else { return }
        let fit = max(pdfView.scaleFactorForSizeToFit, 0.01)
        let next = max(state.relativeScale, 0.1) * fit
        pdfView.minScaleFactor = min(pdfView.minScaleFactor, next)
        pdfView.maxScaleFactor = max(pdfView.maxScaleFactor, next)
        if abs(pdfView.scaleFactor - next) > 0.0005 {
            pdfView.autoScales = false
            pdfView.scaleFactor = next
            pdfView.layoutIfNeeded()
        }
        guard let scroll = pdfView.eclipse_scrollView else { return }
        let inset = scroll.adjustedContentInset
        let minX = -inset.left
        let minY = -inset.top
        let maxX = max(minX, scroll.contentSize.width - scroll.bounds.width + inset.right)
        let maxY = max(minY, scroll.contentSize.height - scroll.bounds.height + inset.bottom)
        let px = min(max(state.progress.x, 0), 1)
        let py = min(max(state.progress.y, 0), 1)
        let offset = CGPoint(
            x: minX + (maxX - minX) * px,
            y: minY + (maxY - minY) * py
        )
        if abs(scroll.contentOffset.x - offset.x) > 0.5
            || abs(scroll.contentOffset.y - offset.y) > 0.5 {
            scroll.contentOffset = offset
        }
    }
}

// MARK: - PDFView Scroll Access

extension PDFView {
    /// The internal scroll view PDFKit uses for continuous display.
    var eclipse_scrollView: UIScrollView? {
        if let scroll = subviews.compactMap({ $0 as? UIScrollView }).first {
            return scroll
        }
        for sub in subviews {
            if let scroll = Self.findScrollView(in: sub) { return scroll }
        }
        return nil
    }

    private static func findScrollView(in view: UIView) -> UIScrollView? {
        if let scroll = view as? UIScrollView { return scroll }
        for sub in view.subviews {
            if let scroll = findScrollView(in: sub) { return scroll }
        }
        return nil
    }
}
