//
//  CloudKitConflictResolverTests.swift
//  EclipseiPhoneTests
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import Foundation
import Testing
@testable import EclipseiPhone

struct CloudKitConflictResolverTests {

    @Test func unionMembershipPrefersOrderThenAppends() {
        let merged = CloudKitConflictResolver.unionMembership(
            preferredOrder: ["a", "b"],
            other: ["b", "c"]
        )
        #expect(merged == ["a", "b", "c"])
    }

    @Test func tombstonesRemoveMembershipOnMerge() {
        let older = Date(timeIntervalSince1970: 1)
        let newer = Date(timeIntervalSince1970: 2)
        let local = LocalAlbum(
            name: "Show",
            itemIds: ["keep", "gone"],
            deletedItemIds: ["gone"]
        )
        let remote = LocalAlbum(
            name: "Show",
            itemIds: ["keep", "gone", "added"]
        )
        let merged = CloudKitConflictResolver.mergeShows(
            local: local,
            localModified: newer,
            remote: remote,
            remoteModified: older
        )
        #expect(merged.itemIds == ["keep", "added"])
        #expect(merged.deletedItemIds.contains("gone"))
    }

    @Test func surfaceTombstonesRemoveTools() {
        let local = LocalAlbum(
            name: "Show",
            itemIds: ["m1"],
            surfaceIds: [ShowToolToken.camera, "m1"],
            deletedSurfaceIds: [ShowToolToken.logo]
        )
        let remote = LocalAlbum(
            name: "Show",
            itemIds: ["m1"],
            surfaceIds: [
                ShowToolToken.screensaver,
                ShowToolToken.logo,
                ShowToolToken.camera,
                "m1"
            ]
        )
        let merged = CloudKitConflictResolver.mergeShows(
            local: local,
            localModified: Date(),
            remote: remote,
            remoteModified: Date().addingTimeInterval(-10)
        )
        #expect(!(merged.surfaceIds ?? []).contains(ShowToolToken.logo))
        #expect((merged.surfaceIds ?? []).contains(ShowToolToken.camera))
    }
}
