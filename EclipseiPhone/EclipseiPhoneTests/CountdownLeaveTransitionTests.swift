//
//  CountdownLeaveTransitionTests.swift
//  EclipseiPhoneTests
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import Foundation
import Testing
import UIKit
@testable import EclipseiPhone

/// Leaving a live countdown for other content must actually change the TV picture.
@MainActor
struct CountdownLeaveTransitionTests {

    private static func writeImage() throws -> URL {
        let image = UIGraphicsImageRenderer(size: CGSize(width: 16, height: 9)).image { ctx in
            UIColor.red.setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: 16, height: 9))
        }
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("eclipse-countdown-leave-\(UUID().uuidString).png")
        try image.pngData()!.write(to: url)
        return url
    }

    private static func settle(_ vc: PresentationViewController) async {
        for _ in 0..<60 where vc.isTransitionInFlight {
            try? await Task.sleep(nanoseconds: 100_000_000)
        }
    }

    private static func host(_ vc: PresentationViewController) -> UIWindow {
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 1280, height: 720))
        window.rootViewController = vc
        window.isHidden = false
        vc.view.layoutIfNeeded()
        return window
    }

    @Test func countdownToImageShowsTheImage() async throws {
        let vc = PresentationViewController()
        let window = Self.host(vc)
        defer { window.isHidden = true }

        vc.show(.countdown)
        await Self.settle(vc)
        #expect(vc.countdownContainer.isHidden == false)

        let url = try Self.writeImage()
        vc.show(.image(url))
        await Self.settle(vc)
        for _ in 0..<30 where vc.imageView.image == nil {
            try? await Task.sleep(nanoseconds: 100_000_000)
        }

        #expect(vc.isTransitionInFlight == false)
        #expect(vc.countdownContainer.isHidden)
        #expect(vc.mediaContainer.isHidden == false)
        #expect(vc.imageView.isHidden == false)
        #expect(vc.imageView.image != nil)
        #expect(vc.transitionOverlayContainer.isHidden)
        #expect(vc.presentedSource == .image(url))
    }

    @Test func countdownToBlackHidesTheClock() async {
        let vc = PresentationViewController()
        let window = Self.host(vc)
        defer { window.isHidden = true }

        vc.show(.countdown)
        await Self.settle(vc)
        vc.show(.black)
        await Self.settle(vc)

        #expect(vc.countdownContainer.isHidden)
        #expect(vc.transitionOverlayContainer.isHidden)
    }
}
