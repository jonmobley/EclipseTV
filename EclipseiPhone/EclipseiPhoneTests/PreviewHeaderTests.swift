//
//  PreviewHeaderTests.swift
//  EclipseiPhoneTests
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import Testing
import UIKit
@testable import EclipseiPhone

@Suite(.serialized)
@MainActor
struct PreviewHeaderTests {

    // MARK: - Header payload

    @Test func stillShowPageCarriesTitleAndShareFile() {
        let url = URL(fileURLWithPath: "/tmp/eclipse-preview-still.jpg")
        let page = ShowPreviewItem.still(
            LocalMediaPreviewItem(id: "still-1", fileURL: url, isVideo: false)
        )

        let item = PreviewHeaderItem.showPage(page)
        #expect(item.itemId == "still-1")
        #expect(item.shareURL == url)
    }

    @Test func displayModeShowPageHasNoTitleOrShareFile() {
        let page = ShowPreviewItem.displayMode(DisplayModePreviewSpec(
            id: ShowToolToken.screensaver,
            fileURL: URL(fileURLWithPath: "/tmp/eclipse-screensaver.mov"),
            isVideo: true,
            usesSeamlessLoop: true
        ))

        #expect(PreviewHeaderItem.showPage(page) == .untitled)
    }

    // MARK: - Menu context

    @Test func menuActionsPresentFromPreviewNotTheScreenBehindIt() {
        let preview = LocalMediaPreviewViewController(
            items: [LocalMediaPreviewItem(id: "a", fileURL: sampleURL(), isVideo: false)],
            startIndex: 0
        )

        let context = preview.previewMenuContext(itemId: "a")
        #expect(context.itemId == "a")
        // Presenting from the grid or picker would be dropped: Preview covers it.
        #expect(context.presenter === preview)
    }

    // MARK: - Header view

    @Test func titleAppearsOnlyWhenTheItemHasOne() {
        let id = uniqueId()
        defer { MediaTitleStore.clear(forId: id) }
        let header = makeHeader()
        let payload = PreviewHeaderItem.libraryItem(id: id, fileURL: sampleURL())

        header.configure(with: payload)
        #expect(header.titleLabel.isHidden)

        MediaTitleStore.setTitle("Opening slide", forId: id)
        header.configure(with: payload)
        #expect(header.titleLabel.isHidden == false)
        #expect(header.titleLabel.text == "Opening slide")
    }

    @Test func shareIsHiddenWithoutAFile() {
        let header = makeHeader()

        header.configure(with: .untitled)
        #expect(header.shareButton.isHidden)

        header.configure(with: .libraryItem(id: uniqueId(), fileURL: sampleURL()))
        #expect(header.shareButton.isHidden == false)
    }

    @Test func shareHandsBackTheFileAndItsAnchor() {
        let url = sampleURL()
        let header = makeHeader()
        var shared: URL?
        var anchor: UIButton?
        header.onShare = { sharedURL, button in
            shared = sharedURL
            anchor = button
        }

        header.configure(with: .libraryItem(id: uniqueId(), fileURL: url))
        header.shareButton.sendActions(for: .touchUpInside)
        #expect(shared == url)
        #expect(anchor === header.shareButton)
    }

    @Test func moreIsHiddenUntilAHostSuppliesAMenu() {
        let header = makeHeader()

        header.configure(with: .libraryItem(id: uniqueId(), fileURL: sampleURL()))
        #expect(header.moreButton.isHidden)

        header.menuProvider = { _ in UIMenu(children: [UIAction(title: "Delete") { _ in }]) }
        #expect(header.moreButton.isHidden == false)
    }

    @Test func moreIsHiddenOnShowToolPages() {
        let header = makeHeader()
        header.menuProvider = { _ in UIMenu(children: [UIAction(title: "Delete") { _ in }]) }

        // Screensaver and Background carry no library id, so there is nothing to act on.
        header.configure(with: .untitled)
        #expect(header.moreButton.isHidden)
    }

    @Test func menuIsBuiltForThePageOnScreen() {
        let first = uniqueId()
        let second = uniqueId()
        let header = makeHeader()
        header.menuProvider = { itemId in
            UIMenu(children: [UIAction(title: "Delete \(itemId)") { _ in }])
        }

        header.configure(with: .libraryItem(id: first, fileURL: sampleURL()))
        #expect(header.menuChildrenForCurrentItem().first?.title == "Delete \(first)")

        header.configure(with: .libraryItem(id: second, fileURL: sampleURL()))
        #expect(header.menuChildrenForCurrentItem().first?.title == "Delete \(second)")
    }

    @Test func chromeButtonsAreGlassWithAnEdge() {
        let header = makeHeader()

        for button in [header.shareButton, header.moreButton, header.closeButton] {
            let background = button.configuration?.background
            // The edge is what keeps a dark blur visible against letterboxing.
            #expect(background?.strokeWidth == 0.5)
            #expect(button.configuration?.baseForegroundColor == .white)
            if UIAccessibility.isReduceTransparencyEnabled {
                #expect(background?.backgroundColor != nil)
            } else {
                #expect(background?.visualEffect != nil)
            }
        }
    }

    @Test func closeReportsTheTap() {
        let header = makeHeader()
        var closed = false
        header.onClose = { closed = true }

        header.closeButton.sendActions(for: .touchUpInside)
        #expect(closed)
    }

    @Test func onlyTheButtonsCaptureTouches() {
        let id = uniqueId()
        defer { MediaTitleStore.clear(forId: id) }
        MediaTitleStore.setTitle("Long enough to sit under the notch", forId: id)
        let header = makeHeader()
        header.configure(with: .libraryItem(id: id, fileURL: sampleURL()))
        header.layoutIfNeeded()

        // Zoom and pan must still reach the media behind the title and scrim.
        let middle = CGPoint(x: header.bounds.midX, y: header.bounds.midY)
        #expect(header.hitTest(middle, with: nil) == nil)

        let onClose = CGPoint(x: header.closeButton.frame.midX, y: header.closeButton.frame.midY)
        #expect(header.hitTest(onClose, with: nil) === header.closeButton)
    }

    // MARK: - Helpers

    private func makeHeader() -> PreviewHeaderView {
        let host = UIView(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        let header = PreviewHeaderView()
        header.translatesAutoresizingMaskIntoConstraints = false
        host.addSubview(header)
        NSLayoutConstraint.activate([
            header.topAnchor.constraint(equalTo: host.topAnchor),
            header.leadingAnchor.constraint(equalTo: host.leadingAnchor),
            header.trailingAnchor.constraint(equalTo: host.trailingAnchor)
        ])
        host.layoutIfNeeded()
        return header
    }

    private func uniqueId() -> String {
        "preview-header-\(UUID().uuidString)"
    }

    private func sampleURL() -> URL {
        URL(fileURLWithPath: "/tmp/eclipse-preview-\(UUID().uuidString).jpg")
    }
}
