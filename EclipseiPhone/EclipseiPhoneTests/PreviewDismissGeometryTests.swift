//
//  PreviewDismissGeometryTests.swift
//  EclipseiPhoneTests
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import Testing
import UIKit
@testable import EclipseiPhone

struct PreviewDismissGeometryTests {

    // MARK: - Offset

    @Test func sidewaysDragIsDampedAndUpwardDragResists() {
        let sideways = PreviewDismissGeometry.cardOffset(
            for: CGPoint(x: 100, y: 50)
        )
        #expect(sideways.x == 100 * PreviewDismissGeometry.horizontalDamping)
        #expect(sideways.y == 50)

        let upward = PreviewDismissGeometry.cardOffset(for: CGPoint(x: 0, y: -100))
        #expect(upward.y == -100 * PreviewDismissGeometry.upwardResistance)
    }

    @Test func progressClampsToTheDragRange() {
        #expect(PreviewDismissGeometry.progress(forVerticalOffset: -80) == 0)
        #expect(PreviewDismissGeometry.progress(forVerticalOffset: 0) == 0)
        #expect(PreviewDismissGeometry.progress(
            forVerticalOffset: PreviewDismissGeometry.travel / 2
        ) == 0.5)
        #expect(PreviewDismissGeometry.progress(forVerticalOffset: 10_000) == 1)
    }

    // MARK: - Appearance

    @Test func cardShrinksWithProgressAndNeverInverts() {
        #expect(PreviewDismissGeometry.scale(at: 0) == 1)
        #expect(PreviewDismissGeometry.scale(at: 1) == PreviewDismissGeometry.minimumScale)
        #expect(PreviewDismissGeometry.scale(at: 4) == PreviewDismissGeometry.minimumScale)
        #expect(PreviewDismissGeometry.scale(at: 0.5) < 1)
    }

    /// The corners have to read as a detached card early in the drag; waiting until
    /// the end makes the pull look like the whole screen sliding rather than a sheet.
    @Test func cornersRoundOffWellBeforeTheDragCompletes() {
        #expect(PreviewDismissGeometry.cornerRadius(at: 0) == 0)
        #expect(PreviewDismissGeometry.cornerRadius(
            at: PreviewDismissGeometry.cornerRampProgress
        ) == CornerRadii.large)
        #expect(PreviewDismissGeometry.cornerRadius(at: 1) == CornerRadii.large)
        #expect(PreviewDismissGeometry.cornerRampProgress < 0.5)
    }

    @Test func backdropStartsDimmedAndClearsAsTheCardLeaves() {
        #expect(PreviewDismissGeometry.dimAlpha(at: 0) == PreviewDismissGeometry.restingDim)
        #expect(PreviewDismissGeometry.dimAlpha(at: 1) == 0)
        #expect(PreviewDismissGeometry.dimAlpha(at: 2) == 0)
    }

    // MARK: - Commit

    @Test func shortDragSpringsBackAndLongDragCloses() {
        #expect(!PreviewDismissGeometry.shouldComplete(progress: 0.1, verticalVelocity: 0))
        #expect(PreviewDismissGeometry.shouldComplete(
            progress: PreviewDismissGeometry.commitProgress, verticalVelocity: 0
        ))
    }

    /// A flick is the common way to close, so speed has to beat distance both ways:
    /// a fast short pull closes, and yanking back up cancels a long one.
    @Test func velocityOutranksDistanceInBothDirections() {
        #expect(PreviewDismissGeometry.shouldComplete(
            progress: 0.02, verticalVelocity: PreviewDismissGeometry.commitVelocity
        ))
        #expect(!PreviewDismissGeometry.shouldComplete(
            progress: 0.95, verticalVelocity: -PreviewDismissGeometry.commitVelocity
        ))
    }
}
