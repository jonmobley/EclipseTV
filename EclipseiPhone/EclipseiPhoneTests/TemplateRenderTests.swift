//
//  TemplateRenderTests.swift
//  EclipseiPhoneTests
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//
//  Renders every template's sample card on a 1080p frame. When the test runner
//  has P3TPL_SHOTS set (TEST_RUNNER_P3TPL_SHOTS for xcodebuild), the stills are
//  written there as PNGs for side-by-side comparison with the Mac.
//

import Foundation
import Testing
import UIKit
@testable import EclipseiPhone

@MainActor
struct TemplateRenderTests {

    private static let frame = CGSize(width: 1920, height: 1080)

    @Test func everyTemplateRendersAVisibleCard() throws {
        let folder = ProcessInfo.processInfo.environment["P3TPL_SHOTS"].map {
            URL(fileURLWithPath: $0, isDirectory: true)
        }
        if let folder {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        }
        for template in OverlayCardTemplate.all {
            let image = try #require(
                OverlayCardThumbnail.render(template.sampleConfig, in: Self.frame),
                "\(template.kind.rawValue) did not render"
            )
            #expect(image.size == Self.frame)
            if let folder, let png = image.pngData() {
                try png.write(to: folder.appendingPathComponent("\(template.kind.rawValue).png"))
            }
        }
    }

    @Test func thumbnailIsCached() {
        let config = OverlayCardTemplate.descriptor(for: .lowerThird).sampleConfig
        let first = OverlayCardThumbnail.image(for: config)
        #expect(first != nil)
        #expect(OverlayCardThumbnail.image(for: config) === first)
    }
}
