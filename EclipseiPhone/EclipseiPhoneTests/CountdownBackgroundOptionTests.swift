//
//  CountdownBackgroundOptionTests.swift
//  EclipseiPhoneTests
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import Foundation
import Testing
import UIKit
@testable import EclipseiPhone

struct CountdownBackgroundOptionTests {

    private func media(_ id: String, isVideo: Bool = false) -> LibraryItemDTO {
        LibraryItemDTO(id: id, name: id, isVideo: isVideo, duration: isVideo ? 12 : 0)
    }

    @Test func fixedChoicesAreNoneScreensaverBackgroundInOrder() {
        #expect(
            CountdownBackgroundOption.fixed.map(\.background)
                == [.black, .screensaver, .background]
        )
        #expect(
            CountdownBackgroundOption.fixed.map(\.title) == ["None", "Screensaver", "Background"]
        )
        #expect(CountdownBackgroundOption.fixed.allSatisfy { $0.mediaId == nil })
    }

    /// The raw import filename must never reach the menu: it is a UUID to the operator.
    @Test func showMediaIsLabelledByKindAndPositionNotFilename() {
        let library = [
            media("batch_0F5ECB32_A4AC.jpg"),
            media("batch_5895AB25_9E5C.mov", isVideo: true),
            media("batch_AD_C21AF5.jpg")
        ]
        let options = CountdownBackgroundOption.showMedia(
            itemIds: library.map(\.id),
            library: library,
            overlayTitle: { _ in nil },
            isOnDevice: { _ in true }
        )
        #expect(options.map(\.title) == ["Photo 1", "Video 2", "Photo 3"])
        #expect(options.map(\.systemImage) == ["photo", "film", "photo"])
        #expect(options.map(\.mediaId) == library.map(\.id))
        #expect(options[1].background == .libraryItem(id: "batch_5895AB25_9E5C.mov"))
    }

    @Test func overlayTitleWinsOverPositionalLabel() {
        let library = [media("a.jpg"), media("b.jpg")]
        let options = CountdownBackgroundOption.showMedia(
            itemIds: ["a.jpg", "b.jpg"],
            library: library,
            overlayTitle: { $0 == "b.jpg" ? "Welcome" : nil },
            isOnDevice: { _ in true }
        )
        #expect(options.map(\.title) == ["Photo 1", "Welcome"])
    }

    /// Numbering follows the grid: a purged member still holds its slot, so the ones
    /// that remain keep the numbers the operator sees on the Show.
    @Test func purgedMembersAreSkippedButKeepTheirSlot() {
        let library = [media("a.jpg"), media("b.jpg"), media("c.jpg")]
        let options = CountdownBackgroundOption.showMedia(
            itemIds: ["a.jpg", "b.jpg", "c.jpg"],
            library: library,
            overlayTitle: { _ in nil },
            isOnDevice: { $0 != "b.jpg" }
        )
        #expect(options.map(\.title) == ["Photo 1", "Photo 3"])
    }

    /// Websites, PDFs, tool tokens, and unknown ids are members too, but they are
    /// not media and must neither appear nor consume a number.
    @Test func nonMediaMembersAreIgnored() {
        let library = [media("a.jpg"), media("b.jpg")]
        let options = CountdownBackgroundOption.showMedia(
            itemIds: ["a.jpg", UUID().uuidString, ShowToolToken.screensaver, "b.jpg"],
            library: library,
            overlayTitle: { _ in nil },
            isOnDevice: { _ in true }
        )
        #expect(options.map(\.title) == ["Photo 1", "Photo 2"])
    }

    @Test func showOrderWinsOverLibraryOrder() {
        let library = [media("a.jpg"), media("b.jpg")]
        let options = CountdownBackgroundOption.showMedia(
            itemIds: ["b.jpg", "a.jpg"],
            library: library,
            overlayTitle: { _ in nil },
            isOnDevice: { _ in true }
        )
        #expect(options.map(\.mediaId) == ["b.jpg", "a.jpg"])
    }

    @Test func labelFallsBackWhenOverlayTitleIsEmpty() {
        #expect(
            CountdownBackgroundOption.label(overlayTitle: "", isVideo: true, ordinal: 4)
                == "Video 4"
        )
        #expect(
            CountdownBackgroundOption.label(overlayTitle: "Doors", isVideo: true, ordinal: 4)
                == "Doors"
        )
    }

    // MARK: - Glyph

    @Test func glyphIsMenuSizedAndKeepsItsColors() {
        let source = UIGraphicsImageRenderer(size: CGSize(width: 400, height: 300)).image {
            UIColor.systemOrange.setFill()
            $0.fill(CGRect(x: 0, y: 0, width: 400, height: 300))
        }
        let glyph = CountdownBackgroundGlyph.make(from: source)
        #expect(glyph.size == CountdownBackgroundGlyph.menuSize)
        // A template image would render as a flat tint in a menu.
        #expect(glyph.renderingMode == .alwaysOriginal)
    }

    @Test func aspectFillCoversTheBoundsAndStaysCentered() {
        let bounds = CGRect(x: 0, y: 0, width: 34, height: 24)
        let wide = CountdownBackgroundGlyph.aspectFillRect(
            for: CGSize(width: 160, height: 90), in: bounds
        )
        #expect(wide.height == 24)
        #expect(wide.width > bounds.width)
        #expect(abs(wide.midX - bounds.midX) < 0.001)

        let tall = CountdownBackgroundGlyph.aspectFillRect(
            for: CGSize(width: 90, height: 160), in: bounds
        )
        #expect(tall.width == 34)
        #expect(tall.height > bounds.height)
        #expect(abs(tall.midY - bounds.midY) < 0.001)

        #expect(CountdownBackgroundGlyph.aspectFillRect(for: .zero, in: bounds) == bounds)
    }
}
