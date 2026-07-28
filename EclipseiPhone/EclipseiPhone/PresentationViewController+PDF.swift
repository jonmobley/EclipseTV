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
        view.displayMode = .singlePageContinuous
        view.displayDirection = .vertical
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
    }

    /// Fills the AirPlay surface with the mode-aspect PDF panel (rotates when Vertical).
    func applyPDFLayout() {
        guard !pdfContainer.isHidden, let pdfView else { return }
        applyRotatedLayout(to: pdfView, in: pdfContainer, scale: 1)
        pdfView.autoScales = true
    }

    /// Jumps the AirPlay PDF to `index` when page-based sync drifts from scroll alone.
    func setPDFPageIndex(_ index: Int) {
        guard let pdfView, !pdfContainer.isHidden,
              let page = pdfView.document?.page(at: index) else { return }
        if pdfView.currentPage != page {
            pdfView.go(to: page)
        }
    }

    /// Mirrors normalized vertical scroll progress (0...1) from the phone PDF view.
    func setPDFScrollProgress(_ progress: CGFloat) {
        guard let pdfView, !pdfContainer.isHidden,
              let scroll = pdfView.eclipse_scrollView else { return }
        let maxY = max(0, scroll.contentSize.height - scroll.bounds.height)
        guard maxY > 0 else { return }
        let clamped = min(max(progress, 0), 1)
        let offset = CGPoint(x: scroll.contentOffset.x, y: clamped * maxY)
        if abs(scroll.contentOffset.y - offset.y) > 0.5 {
            scroll.contentOffset = offset
        }
    }

    /// Mirrors zoom relative to fit-scale from the phone PDF view.
    func setPDFRelativeScale(_ relative: CGFloat) {
        guard let pdfView, !pdfContainer.isHidden else { return }
        let fit = max(pdfView.scaleFactorForSizeToFit, 0.01)
        let next = max(relative, 0.25) * fit
        if abs(pdfView.scaleFactor - next) > 0.001 {
            pdfView.scaleFactor = next
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
