//
//  WebVideoLinkTests.swift
//  EclipseiPhoneTests
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import Foundation
import Testing
@testable import EclipseiPhone

struct WebVideoLinkTests {

    // MARK: - YouTube

    @Test func parsesWatchURL() throws {
        let link = try #require(WebVideoLink(url: url(
            "https://www.youtube.com/watch?v=dQw4w9WgXcQ"
        )))
        #expect(link == .youTube(id: "dQw4w9WgXcQ", startAt: 0))
    }

    @Test func parsesYoutuBeShortLink() throws {
        let link = try #require(WebVideoLink(url: url("https://youtu.be/dQw4w9WgXcQ")))
        #expect(link == .youTube(id: "dQw4w9WgXcQ", startAt: 0))
    }

    @Test func parsesShortsLiveEmbedAndMobileHosts() throws {
        let samples: [(String, String)] = [
            ("https://www.youtube.com/shorts/abcdefghijk", "abcdefghijk"),
            ("https://www.youtube.com/live/abcdefghijk", "abcdefghijk"),
            ("https://www.youtube.com/embed/abcdefghijk", "abcdefghijk"),
            ("https://m.youtube.com/watch?v=abcdefghijk", "abcdefghijk"),
            ("https://music.youtube.com/watch?v=abcdefghijk", "abcdefghijk")
        ]
        for (raw, id) in samples {
            let link = try #require(WebVideoLink(url: url(raw)))
            #expect(link == .youTube(id: id, startAt: 0))
        }
    }

    @Test func parsesYouTubeStartTimestamp() throws {
        let seconds = try #require(WebVideoLink(url: url(
            "https://www.youtube.com/watch?v=dQw4w9WgXcQ&t=90"
        )))
        #expect(seconds == .youTube(id: "dQw4w9WgXcQ", startAt: 90))

        let compound = try #require(WebVideoLink(url: url(
            "https://youtu.be/dQw4w9WgXcQ?t=1m30s"
        )))
        #expect(compound == .youTube(id: "dQw4w9WgXcQ", startAt: 90))

        let startParam = try #require(WebVideoLink(url: url(
            "https://www.youtube.com/watch?v=dQw4w9WgXcQ&start=45"
        )))
        #expect(startParam == .youTube(id: "dQw4w9WgXcQ", startAt: 45))
    }

    @Test func youTubeEmbedURLIncludesAutoplayAndApi() throws {
        let link = WebVideoLink.youTube(id: "dQw4w9WgXcQ", startAt: 12)
        let embed = try #require(link.embedURL)
        let items = URLComponents(url: embed, resolvingAgainstBaseURL: false)?.queryItems ?? []
        var map: [String: String] = [:]
        for item in items {
            if let value = item.value { map[item.name] = value }
        }
        #expect(embed.path.hasSuffix("/embed/dQw4w9WgXcQ"))
        #expect(map["autoplay"] == "1")
        #expect(map["playsinline"] == "1")
        #expect(map["controls"] == "0")
        #expect(map["enablejsapi"] == "1")
        #expect(map["start"] == "12")
    }

    // MARK: - Vimeo

    @Test func parsesVimeoNumericURL() throws {
        let link = try #require(WebVideoLink(url: url("https://vimeo.com/123456789")))
        #expect(link == .vimeo(id: "123456789", hash: nil, startAt: 0))
    }

    @Test func parsesVimeoUnlistedHash() throws {
        let link = try #require(WebVideoLink(url: url(
            "https://vimeo.com/123456789/abcdef12"
        )))
        #expect(link == .vimeo(id: "123456789", hash: "abcdef12", startAt: 0))
    }

    @Test func parsesVimeoPlayerAndChannelURLs() throws {
        let player = try #require(WebVideoLink(url: url(
            "https://player.vimeo.com/video/123456789?h=deadbeef"
        )))
        #expect(player == .vimeo(id: "123456789", hash: "deadbeef", startAt: 0))

        let channel = try #require(WebVideoLink(url: url(
            "https://vimeo.com/channels/staffpicks/123456789"
        )))
        #expect(channel == .vimeo(id: "123456789", hash: nil, startAt: 0))
    }

    @Test func vimeoEmbedURLIncludesHashAndChromeFlags() throws {
        let link = WebVideoLink.vimeo(id: "123", hash: "abc", startAt: 5)
        let embed = try #require(link.embedURL)
        let items = URLComponents(url: embed, resolvingAgainstBaseURL: false)?.queryItems ?? []
        var map: [String: String] = [:]
        for item in items {
            if let value = item.value { map[item.name] = value }
        }
        #expect(embed.path.hasSuffix("/video/123"))
        #expect(map["autoplay"] == "1")
        #expect(map["controls"] == "0")
        #expect(map["h"] == "abc")
        #expect(map["t"] == "5s")
    }

    // MARK: - Direct file

    @Test func parsesDirectMediaExtensions() throws {
        let samples = [
            "https://cdn.example.com/clip.mp4",
            "https://cdn.example.com/clip.m4v",
            "https://cdn.example.com/clip.mov",
            "https://cdn.example.com/stream.m3u8",
            "https://cdn.example.com/clip.mp4?token=abc"
        ]
        for raw in samples {
            let link = try #require(WebVideoLink(url: url(raw)))
            guard case .directFile(let fileURL) = link else {
                Issue.record("Expected directFile for \(raw)")
                continue
            }
            #expect(fileURL.absoluteString == raw)
        }
    }

    // MARK: - Non-video

    @Test func rejectsOrdinaryWebsites() {
        let samples = [
            "https://example.com/page",
            "https://www.youtube.com/",
            "https://www.youtube.com/feed",
            "https://vimeo.com/watch",
            "https://vimeo.com/channels/staffpicks",
            "https://questpoll.live/present?code=ABCD"
        ]
        for raw in samples {
            #expect(WebVideoLink(url: url(raw)) == nil, "Unexpected parse of \(raw)")
        }
    }

    // MARK: - Timestamp helpers

    @Test func parseTimestampValueHandlesCompoundForms() {
        #expect(WebVideoLink.parseTimestampValue("90") == 90)
        #expect(WebVideoLink.parseTimestampValue("1m30s") == 90)
        #expect(WebVideoLink.parseTimestampValue("1h2m3s") == 3723)
        #expect(WebVideoLink.parseTimestampValue("45s") == 45)
        #expect(WebVideoLink.parseTimestampValue("") == 0)
    }

    // MARK: - Helpers

    private func url(_ string: String) -> URL {
        URL(string: string)!
    }
}
