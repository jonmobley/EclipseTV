//
//  MediaFitMenuTests.swift
//  EclipseiPhoneTests
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import Testing
import UIKit
@testable import EclipseiPhone

@Suite(.serialized)
@MainActor
struct MediaFitMenuTests {

    @Test func screenFitMenuListsFitFillCustom() {
        let id = "fit-menu-\(UUID().uuidString)"
        defer { MediaFramingStore.clear(forId: id) }
        let menu = MediaFitMenu.make(
            forId: id, offersFitFill: true, onSelectFit: { _ in }, onCustom: {}
        )
        #expect(titles(of: menu) == ["Fit", "Fill", "Custom"])
    }

    @Test func customRowIsCheckedWhenFramingIsSaved() {
        let id = "fit-menu-\(UUID().uuidString)"
        defer { MediaFramingStore.clear(forId: id) }
        MediaFramingStore.set(
            MediaFraming(x: 0, y: 0, width: 1, height: 1),
            forId: id
        )
        let menu = MediaFitMenu.make(
            forId: id, offersFitFill: true, onSelectFit: { _ in }, onCustom: {}
        )
        let custom = menu.children.compactMap { $0 as? UIAction }
            .first { $0.title == "Custom" }
        #expect(custom?.image == UIImage(systemName: "checkmark"))
    }

    @Test func aStillShapedLikeThePanelKeepsOnlyCustom() {
        // Fit and Fill are the same picture here, so offering them is offering a row
        // that does nothing. Custom stays: the cropper can still punch in and pan.
        let id = "fit-menu-\(UUID().uuidString)"
        defer { MediaFramingStore.clear(forId: id) }
        let menu = MediaFitMenu.make(
            forId: id, offersFitFill: false, onSelectFit: { _ in }, onCustom: {}
        )
        #expect(titles(of: menu) == ["Custom"])
    }

    @Test func resetAppearsOnlyWhereFitCannotServeAsIt() {
        let id = "fit-menu-\(UUID().uuidString)"
        defer { MediaFramingStore.clear(forId: id) }
        MediaFramingStore.set(
            MediaFraming(x: 0.2, y: 0.2, width: 0.4, height: 0.4),
            forId: id
        )
        #expect(
            titles(of: MediaFitMenu.make(
                forId: id, offersFitFill: false, onSelectFit: { _ in }, onCustom: {}
            )) == ["Custom", "Reset"]
        )
        // With Fit on screen there is already a row that drops the saved position.
        #expect(
            titles(of: MediaFitMenu.make(
                forId: id, offersFitFill: true, onSelectFit: { _ in }, onCustom: {}
            )) == ["Fit", "Fill", "Custom"]
        )
    }

    @Test func resetAsksForFitSoTheSavedPositionIsDropped() throws {
        let id = "fit-menu-\(UUID().uuidString)"
        defer { MediaFramingStore.clear(forId: id) }
        MediaFramingStore.set(
            MediaFraming(x: 0.2, y: 0.2, width: 0.4, height: 0.4),
            forId: id
        )
        var requested: [MediaFitMode] = []
        let menu = MediaFitMenu.make(
            forId: id,
            offersFitFill: false,
            onSelectFit: { requested.append($0) },
            onCustom: {}
        )
        let reset = try #require(
            menu.children.compactMap { $0 as? UIAction }.first { $0.title == "Reset" }
        )
        reset.performWithSender(nil, target: nil)
        #expect(requested == [.fit])
    }

    private func titles(of menu: UIMenu) -> [String] {
        menu.children.compactMap { ($0 as? UIAction)?.title }
    }
}
