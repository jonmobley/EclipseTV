//
//  ScreensaverBundledLoopTests.swift
//  EclipseiPhoneTests
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import AVFoundation
import Foundation
import Testing
@testable import EclipseiPhone

@MainActor
struct ScreensaverBundledLoopTests {

    @Test func landscapeUsesTheWideLoop() throws {
        let url = try #require(ScreensaverStore.bundledVideoURL(vertical: false))
        #expect(url.lastPathComponent == "EclipseScreensaver.mp4")
    }

    @Test func verticalUsesTheTallLoop() throws {
        let url = try #require(ScreensaverStore.bundledVideoURL(vertical: true))
        #expect(url.lastPathComponent == "EclipseScreensaverTall.mp4")
    }

    @Test func bundledLoopsHaveTheExpectedShape() async throws {
        let wide = try #require(ScreensaverStore.bundledVideoURL(vertical: false))
        let tall = try #require(ScreensaverStore.bundledVideoURL(vertical: true))
        let wideSize = try await Self.videoSize(wide)
        let tallSize = try await Self.videoSize(tall)
        #expect(wideSize.width > wideSize.height)
        #expect(wideSize.height >= 2160)
        #expect(tallSize.height > tallSize.width)
    }

    private static func videoSize(_ url: URL) async throws -> CGSize {
        let track = try #require(
            try await AVURLAsset(url: url).loadTracks(withMediaType: .video).first
        )
        return try await track.load(.naturalSize)
    }
}
