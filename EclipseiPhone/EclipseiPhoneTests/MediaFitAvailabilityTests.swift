//
//  MediaFitAvailabilityTests.swift
//  EclipseiPhoneTests
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import Testing
import UIKit
@testable import EclipseiPhone

@Suite(.serialized)
@MainActor
struct MediaFitAvailabilityTests {

    @Test func aStillShapedLikeThePanelOffersNoChoice() {
        ExternalOutputOrientationFixture.with(.landscape) {
            #expect(
                MediaFitAvailability.fitDiffersFromFill(
                    forSize: CGSize(width: 1920, height: 1080)
                ) == false
            )
        }
    }

    @Test func aStillShapedUnlikeThePanelKeepsTheChoice() {
        ExternalOutputOrientationFixture.with(.landscape) {
            // 4:3 and a tall phone snap both crop or letterbox on a 16:9 panel.
            #expect(
                MediaFitAvailability.fitDiffersFromFill(
                    forSize: CGSize(width: 1600, height: 1200)
                ) == true
            )
            #expect(
                MediaFitAvailability.fitDiffersFromFill(
                    forSize: CGSize(width: 1170, height: 2532)
                ) == true
            )
        }
    }

    @Test func theSameStillFlipsAnswerWithDisplayMode() {
        ExternalOutputOrientationFixture.withSwitching { set in
            let tall = CGSize(width: 1080, height: 1920)
            set(.landscape)
            #expect(MediaFitAvailability.fitDiffersFromFill(forSize: tall) == true)
            // Vertical imports are force-cropped to 9:16, so this is the ordinary
            // case in a Vertical Show rather than a corner of one.
            set(.portrait)
            #expect(MediaFitAvailability.fitDiffersFromFill(forSize: tall) == false)
        }
    }

    @Test func thumbnailRoundingStaysInsideTheTolerance() {
        // Thumbnails are downsampled aspect-fit to a 640px long edge, so a 16:9 photo
        // arrives as whole pixels that are only approximately 16:9. That rounding must
        // not read as a still the user can meaningfully reframe.
        ExternalOutputOrientationFixture.with(.landscape) {
            #expect(
                MediaFitAvailability.fitDiffersFromFill(
                    forSize: CGSize(width: 640, height: 360)
                ) == false
            )
            #expect(
                MediaFitAvailability.fitDiffersFromFill(
                    forSize: CGSize(width: 639, height: 361)
                ) == false
            )
        }
    }

    @Test func aVisiblyOffStillKeepsTheChoiceTheImportGateWouldWaive() {
        // `MediaAspect.matches` defaults to 3% because waving a still through import
        // only skips a prompt. Taking the control away is a stronger claim, so 2% off
        // still counts as reframeable.
        ExternalOutputOrientationFixture.with(.landscape) {
            let size = CGSize(width: 1920, height: 1080 * 1.02)
            #expect(MediaAspect.matches(size, target: MediaAspect.landscape))
            #expect(MediaFitAvailability.fitDiffersFromFill(forSize: size) == true)
        }
    }

    @Test func anUnmeasuredStillHasNoAnswer() {
        #expect(
            MediaFitAvailability.fitDiffersFromFill(
                forId: "never-imported-\(UUID().uuidString)"
            ) == nil
        )
    }
}
