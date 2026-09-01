//
//  AudioPlaylistDetailTitleTests.swift
//  EclipseiPhoneTests
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import Testing
import UIKit
@testable import EclipseiPhone

@MainActor
struct AudioPlaylistDetailTitleTests {

    @Test func largeTitleOnCompactWidthOnly() {
        #expect(
            AudioPlaylistDetailViewController.usesLargeTitle(
                horizontalSizeClass: .compact
            )
        )
        #expect(
            AudioPlaylistDetailViewController.usesLargeTitle(
                horizontalSizeClass: .regular
            ) == false
        )
    }

    @Test func playlistUsesLargeTitleOnCompactWidth() {
        let detail = Self.loadedDetail(horizontalSizeClass: .compact)
        #expect(detail.navigationItem.largeTitleDisplayMode == .always)
    }

    @Test func playlistUsesInlineTitleOnRegularWidth() {
        let detail = Self.loadedDetail(horizontalSizeClass: .regular)
        #expect(detail.navigationItem.largeTitleDisplayMode == .never)
    }

    /// A playlist screen whose horizontal size class is already `sizeClass`.
    private static func loadedDetail(
        horizontalSizeClass sizeClass: UIUserInterfaceSizeClass
    ) -> AudioPlaylistDetailViewController {
        let detail = AudioPlaylistDetailViewController(playlistId: UUID())
        detail.traitOverrides.horizontalSizeClass = sizeClass
        detail.loadViewIfNeeded()
        return detail
    }
}
