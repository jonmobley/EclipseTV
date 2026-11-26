//
//  LiveHeaderView+PDFPreview.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import PDFKit
import UIKit

// MARK: - Interactive PDF in the hero

extension LiveHeaderView {

    /// Shows the PDF itself in the hero: sharp at any size, scrolls and pinches
    /// in place, with the Fit · Fill · Two Pages · Page by Page row top right.
    ///
    /// - Parameter drivesOutput: True when this is the live PDF; the TV then
    ///   follows the hero (until the full-screen reader takes over). False for a
    ///   private Preview, which never moves the TV.
    func showPDFPreview(documentId: UUID, fileURL: URL, drivesOutput: Bool) {
        if let driver = pdfPreviewDriver,
           driver.documentId == documentId, driver.drivesOutput == drivesOutput {
            if drivesOutput, PDFReaderDriver.active == nil {
                driver.becomeActive()
            }
            // A hero refresh (e.g. clearing a website preview) shows the still
            // again; keep it hidden behind the live PDF.
            setStaticPreviewHidden(true)
            bringPDFChromeToFront()
            setNeedsLayout()
            return
        }
        clearPDFPreview()
        guard let document = PDFDocument(url: fileURL), document.pageCount > 0 else { return }

        let host = UIView()
        host.backgroundColor = .black
        host.clipsToBounds = true
        host.translatesAutoresizingMaskIntoConstraints = false
        insertSubview(host, at: 0)
        NSLayoutConstraint.activate([
            host.topAnchor.constraint(equalTo: topAnchor),
            host.bottomAnchor.constraint(equalTo: bottomAnchor),
            host.leadingAnchor.constraint(equalTo: leadingAnchor),
            host.trailingAnchor.constraint(equalTo: trailingAnchor)
        ])
        let panel = UIView()
        panel.backgroundColor = .black
        panel.clipsToBounds = true
        host.addSubview(panel)
        pdfPreviewHost = host
        pdfPreviewPanel = panel

        let driver = PDFReaderDriver(document: document, documentId: documentId, drivesOutput: drivesOutput)
        pdfPreviewDriver = driver

        // Smaller on a phone, where the hero is only ~200pt tall.
        let bar = PDFViewOptionsBar(buttonSize: traitCollection.horizontalSizeClass == .compact ? 26 : 30)
        bar.translatesAutoresizingMaskIntoConstraints = false
        bar.onPreset = { [weak driver] preset in driver?.apply(preset) }
        bar.onToggleSnap = { [weak driver] in
            guard let driver else { return }
            driver.setSnapsToPages(!driver.state.snapsToPages)
        }
        driver.onOptionsChange = { [weak bar, weak driver] in
            guard let driver else { return }
            bar?.update(preset: driver.state.preset, snapsToPages: driver.state.snapsToPages)
        }
        bar.update(preset: driver.state.preset, snapsToPages: driver.state.snapsToPages)
        addSubview(bar)
        // Left of the expand control (36pt circle, 10pt in), at its height.
        NSLayoutConstraint.activate([
            bar.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -54),
            bar.centerYAnchor.constraint(equalTo: topAnchor, constant: 28)
        ])
        pdfOptionsBar = bar

        if drivesOutput {
            // The full-screen reader hands back when it closes.
            pdfResignObserver = NotificationCenter.default.addObserver(
                forName: PDFReaderDriver.didResignNotification, object: nil, queue: .main
            ) { [weak self] note in
                MainActor.assumeIsolated {
                    guard let self, let driver = self.pdfPreviewDriver,
                          note.object as AnyObject? !== driver else { return }
                    driver.becomeActive()
                }
            }
            if PDFReaderDriver.active == nil {
                driver.becomeActive()
            }
        }
        setStaticPreviewHidden(true)
        bringPDFChromeToFront()
        applyCollapseChrome()
        setNeedsLayout()
    }

    /// Keeps the audience-shaped page panel sized to the hero.
    func layoutPDFPreviewIfNeeded() {
        guard let host = pdfPreviewHost, let panel = pdfPreviewPanel,
              let driver = pdfPreviewDriver else { return }
        host.layoutIfNeeded()
        let bounds = host.bounds
        guard bounds.width > 1, bounds.height > 1 else { return }
        let rect = ExternalOutputSettings.panelRect(
            in: bounds, aspect: ExternalOutputSettings.outputAspectRatio
        )
        if panel.frame != rect {
            panel.frame = rect
        }
        driver.layout(in: panel)
    }

    /// Removes the in-hero PDF (the TV keeps whatever it shows).
    func clearPDFPreview() {
        guard pdfPreviewHost != nil || pdfPreviewDriver != nil else { return }
        if let observer = pdfResignObserver {
            NotificationCenter.default.removeObserver(observer)
        }
        pdfResignObserver = nil
        pdfPreviewDriver?.resignActive()
        pdfPreviewDriver = nil
        pdfOptionsBar?.removeFromSuperview()
        pdfOptionsBar = nil
        pdfPreviewPanel = nil
        pdfPreviewHost?.removeFromSuperview()
        pdfPreviewHost = nil
        setStaticPreviewHidden(false)
    }

    /// Whether a hero gesture started on the interactive PDF (it handles its own
    /// scrolling and pinching, so the hero's tap / swipes / adjust stay off it).
    func isTouchOnInteractivePDF(_ gesture: UIGestureRecognizer) -> Bool {
        guard let panel = pdfPreviewPanel, panel.isUserInteractionEnabled,
              !isCompactPresentation else { return false }
        return panel.bounds.contains(gesture.location(in: panel))
    }

    /// The PDF is a picture while the hero is tucked (a tap then expands it),
    /// and the button row fades with the rest of the chrome.
    func applyPDFPreviewCollapse(controlsFade: CGFloat) {
        guard let host = pdfPreviewHost else { return }
        let interactive = !isCompactPresentation
        if host.isUserInteractionEnabled != interactive {
            host.isUserInteractionEnabled = interactive
        }
        if let bar = pdfOptionsBar {
            bar.alpha = controlsFade
            let hide = controlsFade <= 0.01
            if bar.isHidden != hide { bar.isHidden = hide }
        }
    }

    private func bringPDFChromeToFront() {
        if let host = pdfPreviewHost {
            insertSubview(host, at: 0)
        }
        bringSubviewToFront(liveBadge)
        bringSubviewToFront(titleLabel)
        bringSubviewToFront(subtitleLabel)
        if let bar = pdfOptionsBar { bringSubviewToFront(bar) }
        bringExpandControlToFront()
        raiseInFlightTransitionSnapshot()
    }
}
