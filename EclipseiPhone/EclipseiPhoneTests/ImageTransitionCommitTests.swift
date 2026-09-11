//
//  ImageTransitionCommitTests.swift
//  EclipseiPhoneTests
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import Foundation
import Testing
import UIKit
@testable import EclipseiPhone

@MainActor
struct ImageTransitionCommitTests {

    private static func makeImage() -> UIImage {
        UIGraphicsImageRenderer(size: CGSize(width: 4, height: 4)).image { context in
            UIColor.red.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 4, height: 4))
        }
    }

    /// Committing a Crossfade must promote the overlay's decoded still without
    /// clearing the primary or spinning up the loading indicator.
    @Test func commitAdoptsIncomingStillWithoutSpinner() {
        let vc = PresentationViewController()
        _ = vc.view
        let decoded = Self.makeImage()
        vc.incomingImageView = UIImageView(image: decoded)
        vc.isCommittingTransition = true

        vc.applyShowDirect(.image(URL(fileURLWithPath: "/tmp/eclipse-still-adopt.jpg")))

        #expect(vc.imageView.image === decoded)
        #expect(vc.imageView.isHidden == false)
        #expect(vc.activityIndicator.isAnimating == false)
    }

    /// Outside a commit there is nothing to adopt, so the normal decode path runs.
    @Test func directShowWithoutIncomingStillDecodes() {
        let vc = PresentationViewController()
        _ = vc.view
        vc.imageView.image = Self.makeImage()

        vc.applyShowDirect(.image(URL(fileURLWithPath: "/tmp/eclipse-still-missing.jpg")))

        #expect(vc.imageView.image == nil)
        #expect(vc.activityIndicator.isAnimating)
    }

    /// A stale overlay still from an unrelated transition is never adopted.
    @Test func staleIncomingStillIsIgnoredWhenNotCommitting() {
        let vc = PresentationViewController()
        _ = vc.view
        vc.incomingImageView = UIImageView(image: Self.makeImage())
        vc.isCommittingTransition = false

        vc.applyShowDirect(.image(URL(fileURLWithPath: "/tmp/eclipse-still-stale.jpg")))

        #expect(vc.imageView.image == nil)
        #expect(vc.activityIndicator.isAnimating)
    }
}
