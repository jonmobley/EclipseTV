//
//  VideoPosterFrameTests.swift
//  EclipseiPhoneTests
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import Testing
import UIKit
@testable import EclipseiPhone

struct VideoPosterFrameTests {

    @Test func prefersZeroThenLaterTimesOnTypicalClips() {
        let times = VideoPosterFrame.candidateSeconds(duration: 10)
        #expect(times.first == 0)
        #expect(times.contains { abs($0 - 0.2) < 0.02 })
        #expect(times.contains { abs($0 - 0.5) < 0.02 })
        #expect(times.contains { abs($0 - 1) < 0.02 })
    }

    @Test func shortClipsStayInsideDuration() {
        let times = VideoPosterFrame.candidateSeconds(duration: 0.2)
        #expect(!times.isEmpty)
        #expect(times.allSatisfy { $0 >= 0 && $0 <= 0.2 })
        #expect(!times.contains { $0 > 0.2 })
    }

    @Test func solidBlackIsNotAUsablePoster() {
        #expect(VideoPosterFrame.isUsable(swatch(.black)) == false)
    }

    @Test func aLitFrameIsAUsablePoster() {
        #expect(VideoPosterFrame.isUsable(swatch(.systemBlue)))
        #expect(VideoPosterFrame.isUsable(swatch(.white)))
    }

    @Test func missingFileReportsZeroDuration() async {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("missing-clip.mov")
        try? FileManager.default.removeItem(at: url)
        let seconds = await VideoPosterFrame.durationSeconds(at: url)
        #expect(seconds == 0)
    }

    private func swatch(_ color: UIColor) -> UIImage {
        let size = CGSize(width: 32, height: 32)
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { context in
            color.setFill()
            context.fill(CGRect(origin: .zero, size: size))
        }
    }
}
