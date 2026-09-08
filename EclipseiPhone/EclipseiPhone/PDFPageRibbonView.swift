//
//  PDFPageRibbonView.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import PDFKit
import UIKit

/// Page strip for multi-page PDFs: a "Page 3 of 12" counter over a horizontal row
/// of tappable page thumbnails that tracks the attached `PDFView`.
///
/// Phone-side chrome only. Tapping a thumbnail moves the `PDFView`, which posts
/// `PDFViewPageChanged`, so the existing AirPlay sync path follows for free.
final class PDFPageRibbonView: UIView {

    // MARK: - Layout

    /// Height the ribbon needs when shown. Callers collapse it to zero for a
    /// single-page document.
    static let preferredHeight: CGFloat = 92

    private static let thumbnailSize = CGSize(width: 44, height: 60)
    private static let counterHeight: CGFloat = 16

    // MARK: - Subviews

    private let counter = UILabel()
    private let thumbnails = PDFThumbnailView()

    // MARK: - Init

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .black
        setupCounter()
        setupThumbnails()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - API

    /// Binds the strip to `pdfView`; selection and scrolling stay in sync both ways.
    func attach(to pdfView: PDFView) {
        thumbnails.pdfView = pdfView
        refreshCounter(from: pdfView)
    }

    /// Updates the "Page X of N" label from the view's current page.
    func refreshCounter(from pdfView: PDFView) {
        guard let document = pdfView.document, let page = pdfView.currentPage else {
            counter.text = nil
            return
        }
        let index = document.index(for: page) + 1
        let text = "Page \(index) of \(document.pageCount)"
        counter.text = text
        counter.accessibilityLabel = text
    }

    // MARK: - Setup

    private func setupCounter() {
        counter.font = .preferredFont(forTextStyle: .caption1)
        counter.textColor = .secondaryLabel
        counter.textAlignment = .center
        counter.adjustsFontForContentSizeCategory = true
        counter.translatesAutoresizingMaskIntoConstraints = false
        addSubview(counter)
        NSLayoutConstraint.activate([
            counter.topAnchor.constraint(equalTo: topAnchor, constant: 4),
            counter.leadingAnchor.constraint(equalTo: leadingAnchor),
            counter.trailingAnchor.constraint(equalTo: trailingAnchor),
            counter.heightAnchor.constraint(equalToConstant: Self.counterHeight)
        ])
    }

    private func setupThumbnails() {
        thumbnails.layoutMode = .horizontal
        thumbnails.thumbnailSize = Self.thumbnailSize
        thumbnails.backgroundColor = .black
        thumbnails.contentInset = UIEdgeInsets(top: 0, left: 12, bottom: 0, right: 12)
        thumbnails.translatesAutoresizingMaskIntoConstraints = false
        addSubview(thumbnails)
        // Non-required so the host can collapse the ribbon to zero height without
        // an unsatisfiable-constraints complaint.
        let bottom = thumbnails.bottomAnchor.constraint(equalTo: bottomAnchor)
        bottom.priority = .defaultHigh
        NSLayoutConstraint.activate([
            thumbnails.topAnchor.constraint(equalTo: counter.bottomAnchor, constant: 6),
            thumbnails.leadingAnchor.constraint(equalTo: leadingAnchor),
            thumbnails.trailingAnchor.constraint(equalTo: trailingAnchor),
            bottom
        ])
    }
}
