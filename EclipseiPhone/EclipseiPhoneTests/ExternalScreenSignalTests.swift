//
//  ExternalScreenSignalTests.swift
//  EclipseiPhoneTests
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import CoreGraphics
import Testing
@testable import EclipseiPhone

/// An odd-shaped external screen (an LED wall behind an EDID box) is filled at
/// its real size. These cover the rules only; nothing here writes settings, so
/// the suite is safe beside tests that read the global output shape.
struct ExternalScreenSignalTests {

    private typealias Size = ExternalScreenSignal.PixelSize

    private func signal(_ width: Int, _ height: Int, offered: [Size] = []) -> ExternalScreenSignal {
        ExternalScreenSignal(current: Size(width: width, height: height), offered: offered)
    }

    @Test func ordinaryTVSizesAreNotOdd() {
        #expect(signal(1920, 1080).oddShape == nil)
        #expect(signal(1280, 720).oddShape == nil)
        #expect(signal(3840, 2160).oddShape == nil)
        // 1366×768 panels are 16:9 in everything but arithmetic.
        #expect(signal(1366, 768).oddShape == nil)
        #expect(signal(0, 0).oddShape == nil)
    }

    @Test func wallSizesAreOdd() throws {
        // One to five 512×768 panels side by side.
        for panels in 1...5 {
            let width = 512 * panels
            let shape = try #require(signal(width, 768).oddShape)
            #expect(abs(shape - CGFloat(width) / 768) < 0.0001)
        }
        // Two panels are plain 4:3, which is still not a 16:9 TV.
        #expect(signal(1024, 768).oddShape != nil)
        #expect(signal(1920, 1200).oddShape != nil)
    }

    @Test func otherOfferedDropsCurrentAndRepeats() {
        let wall = Size(width: 2048, height: 768)
        let hd = Size(width: 1920, height: 1080)
        let small = Size(width: 1280, height: 720)
        let reading = signal(2048, 768, offered: [hd, wall, small, hd])
        #expect(reading.otherOffered == [hd, small])
        #expect(signal(2048, 768, offered: [wall]).otherOffered.isEmpty)
    }

    @Test func switchesOnlyToAnOfferedOddSize() {
        let wall = Size(width: 2048, height: 768)
        let hd = Size(width: 1920, height: 1080)
        let small = Size(width: 1280, height: 720)
        let offered = [hd, small, wall]

        // The wall's size is offered but iOS chose 1080p: switch.
        #expect(ExternalScreenSignal.indexOfOffered(matching: wall, in: offered, current: hd) == 2)
        // Already sending it, nothing chosen, or not offered: leave the signal alone.
        #expect(ExternalScreenSignal.indexOfOffered(matching: wall, in: offered, current: wall) == nil)
        #expect(ExternalScreenSignal.indexOfOffered(matching: nil, in: offered, current: hd) == nil)
        #expect(ExternalScreenSignal.indexOfOffered(matching: wall, in: [hd, small], current: hd) == nil)
        // A 16:9 custom size is proportions only; it never lowers a TV's signal.
        #expect(ExternalScreenSignal.indexOfOffered(matching: small, in: offered, current: hd) == nil)
    }

    @Test func shapeChangeIsWhatObserversHearAbout() {
        let wall = signal(2048, 768)
        #expect(ExternalScreenSignal.shapeChanged(from: nil, to: wall))
        #expect(ExternalScreenSignal.shapeChanged(from: wall, to: nil))
        #expect(ExternalScreenSignal.shapeChanged(from: wall, to: signal(2560, 768)))
        // TVs coming and going never change the shape, so nothing is announced.
        #expect(!ExternalScreenSignal.shapeChanged(from: nil, to: signal(1920, 1080)))
        #expect(!ExternalScreenSignal.shapeChanged(from: signal(1920, 1080), to: signal(3840, 2160)))
        #expect(!ExternalScreenSignal.shapeChanged(from: wall, to: wall))
    }

    @Test func outputShapeFollowsAnOddScreenInLandscapeOnly() {
        let wallShape: CGFloat = 2048.0 / 768.0
        let custom = ExternalOutputCustomSize(name: "Lobby", width: 512, height: 786)

        let landscape = ExternalOutputSettings.outputAspectRatio(
            orientation: .landscape, customSize: nil, screenShape: wallShape
        )
        #expect(abs(landscape - wallShape) < 0.0001)

        // A custom size the operator chose still wins.
        let chosen = ExternalOutputSettings.outputAspectRatio(
            orientation: .landscape, customSize: custom, screenShape: wallShape
        )
        #expect(abs(chosen - custom.aspectRatio) < 0.0001)

        // Vertical keeps its rotated 9:16 picture.
        let vertical = ExternalOutputSettings.outputAspectRatio(
            orientation: .portrait, customSize: nil, screenShape: wallShape
        )
        #expect(abs(vertical - ExternalOutputOrientation.portrait.aspectRatio) < 0.0001)

        // No odd screen: exactly as before.
        let plain = ExternalOutputSettings.outputAspectRatio(orientation: .landscape, customSize: nil)
        #expect(abs(plain - 16.0 / 9.0) < 0.0001)
    }

    @Test func wallWidthsAreOneTapChoicesAndTVSizesAreNot() {
        // What an iPhone lists behind a wall box that offers all five widths.
        let listed = [
            Size(width: 720, height: 480), Size(width: 512, height: 768),
            Size(width: 720, height: 576), Size(width: 1024, height: 768),
            Size(width: 1280, height: 720), Size(width: 1536, height: 768),
            Size(width: 2048, height: 768), Size(width: 2560, height: 768),
            Size(width: 1920, height: 1080), Size(width: 3840, height: 2160)
        ]
        let wall = signal(2560, 768, offered: listed)
        #expect(wall.selectableOffered.map(\.label) == ["512×768", "1024×768", "1536×768", "2048×768"])
        // The size being sent is never offered again as a choice.
        #expect(signal(2048, 768, offered: listed).selectableOffered.map(\.label)
            == ["512×768", "1024×768", "1536×768", "2560×768"])

        // An ordinary TV offers nothing to choose: only TV and video sizes.
        let tv = signal(3840, 2160, offered: listed.filter { $0.height != 768 })
        #expect(tv.selectableOffered.isEmpty)
    }

    @Test func fullScreenLabelNamesTheRealSize() {
        #expect(ExternalOutputSettings.fullScreenLabel(signal: nil) == "Full Screen (16:9)")
        #expect(ExternalOutputSettings.fullScreenLabel(signal: signal(1920, 1080)) == "Full Screen (16:9)")
        #expect(ExternalOutputSettings.fullScreenLabel(signal: signal(2048, 768)) == "Full Screen (2048×768)")
    }
}
