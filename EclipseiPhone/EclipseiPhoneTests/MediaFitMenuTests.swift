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
        let menu = MediaFitMenu.make(forId: id, onSelectFit: { _ in }, onCustom: {})
        let titles = menu.children.compactMap { ($0 as? UIAction)?.title }
        #expect(titles == ["Fit", "Fill", "Custom"])
    }

    /// Video has Fit and Fill but no Custom: there is no video equivalent of the
    /// pre-rendered crop a still's Custom position produces.
    @Test func screenFitMenuDropsCustomWhenNotAllowed() {
        let id = "fit-menu-\(UUID().uuidString)"
        defer { MediaFramingStore.clear(forId: id) }
        let menu = MediaFitMenu.make(
            forId: id,
            allowsCustom: false,
            onSelectFit: { _ in },
            onCustom: {}
        )
        let titles = menu.children.compactMap { ($0 as? UIAction)?.title }
        #expect(titles == ["Fit", "Fill"])
    }

    @Test func customRowIsCheckedWhenFramingIsSaved() {
        let id = "fit-menu-\(UUID().uuidString)"
        defer { MediaFramingStore.clear(forId: id) }
        MediaFramingStore.set(
            MediaFraming(x: 0, y: 0, width: 1, height: 1),
            forId: id
        )
        let menu = MediaFitMenu.make(forId: id, onSelectFit: { _ in }, onCustom: {})
        let custom = menu.children.compactMap { $0 as? UIAction }
            .first { $0.title == "Custom" }
        #expect(custom?.image == UIImage(systemName: "checkmark"))
    }
}
