//
//  ShowCopyDestinationsTests.swift
//  EclipseiPhoneTests
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import Foundation
import Testing
@testable import EclipseiPhone

struct ShowCopyDestinationsTests {

    @Test func emptyWhenOnlyTheOpenShowExists() {
        let open = LocalAlbum(name: "Open", orientation: .landscape)
        let groups = ShowCopyDestinations.grouped(
            albums: [open],
            excluding: open.id,
            activeOrientation: .landscape
        )
        #expect(groups.isEmpty)
    }

    @Test func listsSameModeShowsBeforeOtherMode() {
        let open = LocalAlbum(name: "Open", orientation: .landscape)
        let same = LocalAlbum(name: "Wide", orientation: .landscape)
        let other = LocalAlbum(name: "Tall", orientation: .portrait)
        let groups = ShowCopyDestinations.grouped(
            albums: [open, same, other],
            excluding: open.id,
            activeOrientation: .landscape
        )
        #expect(groups.count == 2)
        #expect(groups[0].map(\.name) == ["Wide"])
        #expect(groups[1].map(\.name) == ["Tall"])
    }

    @Test func omitsEmptyOrientationGroup() {
        let open = LocalAlbum(name: "Open", orientation: .portrait)
        let peer = LocalAlbum(name: "Also Tall", orientation: .portrait)
        let groups = ShowCopyDestinations.grouped(
            albums: [open, peer],
            excluding: open.id,
            activeOrientation: .portrait
        )
        #expect(groups.count == 1)
        #expect(groups[0].map(\.name) == ["Also Tall"])
    }
}
