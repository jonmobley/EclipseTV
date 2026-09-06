//
//  PreviewRevealTests.swift
//  EclipseiPhoneTests
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import Testing
import UIKit
@testable import EclipseiPhone

/// Closing a fullscreen Preview parks the grid on the tile the user swiped to.
struct PreviewRevealTests {

    @Test func fullyVisibleTileNeedsNoScroll() {
        let visible = CGRect(x: 0, y: 200, width: 400, height: 600)
        #expect(!UICollectionView.needsReveal(
            itemFrame: CGRect(x: 16, y: 300, width: 120, height: 90),
            visibleRect: visible
        ))
    }

    @Test func partiallyHiddenTileNeedsScroll() {
        let visible = CGRect(x: 0, y: 200, width: 400, height: 600)
        // Straddling the top edge (tucked under floating chrome).
        #expect(UICollectionView.needsReveal(
            itemFrame: CGRect(x: 16, y: 150, width: 120, height: 90),
            visibleRect: visible
        ))
        // Entirely below the fold.
        #expect(UICollectionView.needsReveal(
            itemFrame: CGRect(x: 16, y: 900, width: 120, height: 90),
            visibleRect: visible
        ))
    }

    @MainActor
    @Test func revealJumpsOffscreenItemIntoViewAndLeavesVisibleOnesAlone() {
        let layout = UICollectionViewFlowLayout()
        layout.itemSize = CGSize(width: 100, height: 100)
        layout.minimumLineSpacing = 0
        layout.minimumInteritemSpacing = 0
        let dataSource = FixedCountDataSource(count: 40)
        let grid = UICollectionView(
            frame: CGRect(x: 0, y: 0, width: 100, height: 300),
            collectionViewLayout: layout
        )
        grid.register(UICollectionViewCell.self, forCellWithReuseIdentifier: "cell")
        grid.dataSource = dataSource
        grid.layoutIfNeeded()

        grid.revealItemIfNeeded(at: IndexPath(item: 1, section: 0))
        #expect(grid.contentOffset.y == 0, "item 1 is already on screen")

        grid.revealItemIfNeeded(at: IndexPath(item: 30, section: 0))
        let visible = grid.bounds
        let frame = grid.layoutAttributesForItem(at: IndexPath(item: 30, section: 0))!.frame
        #expect(visible.contains(frame))
    }

    @Test func showMemberLookupResolvesToolTokens() {
        let grid: [ShowGridItem] = [.screensaver, .logo, .camera, .add]
        #expect(
            LibraryGridViewController.indexOfShowMember(ShowToolToken.screensaver, in: grid) == 0
        )
        #expect(LibraryGridViewController.indexOfShowMember(ShowToolToken.logo, in: grid) == 1)
        #expect(LibraryGridViewController.indexOfShowMember(ShowToolToken.camera, in: grid) == 2)
        #expect(LibraryGridViewController.indexOfShowMember("missing", in: grid) == nil)
    }
}

private final class FixedCountDataSource: NSObject, UICollectionViewDataSource {
    let count: Int

    init(count: Int) {
        self.count = count
    }

    func collectionView(
        _ collectionView: UICollectionView,
        numberOfItemsInSection section: Int
    ) -> Int {
        count
    }

    func collectionView(
        _ collectionView: UICollectionView,
        cellForItemAt indexPath: IndexPath
    ) -> UICollectionViewCell {
        collectionView.dequeueReusableCell(withReuseIdentifier: "cell", for: indexPath)
    }
}
