//
//  SlideshowProtocolTests.swift
//  EclipseAppleTVTests
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import Foundation
import Testing
@testable import EclipseAppleTV

/// Wire compatibility for TV-run slideshows: old and new payloads both ways.
struct SlideshowProtocolTests {

    private func decode(_ json: String) -> EclipseShareEnvelope? {
        EclipseShareEnvelope.decode(from: Data(json.utf8))
    }

    private static let sampleSlideshow = SlideshowDTO(
        slides: [
            SlideshowSlideDTO(id: "a.jpg", isFill: true, framing: nil),
            SlideshowSlideDTO(
                id: "b.jpg", isFill: true,
                framing: MediaFramingDTO(x: 0.1, y: 0.2, width: 0.5, height: 0.5)
            )
        ],
        startIndex: 1, seconds: 5, loops: true, crossfades: false
    )

    @Test func oldManifestWithoutCapabilitiesDecodes() throws {
        let envelope = try #require(decode(#"{"eclipseMsg":"library_manifest","items":[]}"#))
        #expect(envelope.kind == .libraryManifest)
        #expect(envelope.capabilities == nil)
        #expect(EclipseShareCapability.supportsSlideshow(envelope.capabilities) == false)
    }

    @Test func newManifestCarriesSlideshowCapability() throws {
        var manifest = EclipseShareEnvelope.manifest(items: [], currentId: nil)
        manifest.capabilities = EclipseShareCapability.advertisedByTV
        let data = try #require(manifest.encoded())
        let decoded = try #require(EclipseShareEnvelope.decode(from: data))
        #expect(EclipseShareCapability.supportsSlideshow(decoded.capabilities))
    }

    @Test func playSlideshowRoundTrips() throws {
        let data = try #require(EclipseShareEnvelope.playSlideshow(Self.sampleSlideshow).encoded())
        let decoded = try #require(EclipseShareEnvelope.decode(from: data))
        #expect(decoded.kind == .playSlideshow)
        #expect(decoded.slideshow == Self.sampleSlideshow)
    }

    @Test func slideshowControlRoundTrips() throws {
        let goToData = try #require(EclipseShareEnvelope.slideshowGoTo(id: "b.jpg").encoded())
        let goTo = try #require(EclipseShareEnvelope.decode(from: goToData))
        #expect(goTo.kind == .slideshowControl)
        #expect(goTo.slideshowControlAction == .goTo)
        #expect(goTo.id == "b.jpg")

        let stopData = try #require(EclipseShareEnvelope.slideshowStop().encoded())
        let stop = try #require(EclipseShareEnvelope.decode(from: stopData))
        #expect(stop.slideshowControlAction == .stop)
    }

    @Test func unknownMessageFromNewerPhoneIsIgnoredNotRejected() throws {
        // What an older TV sees when a newer phone sends a kind it doesn't know:
        // the envelope decodes, its kind is nil, and the router falls into `.none`.
        let envelope = try #require(decode(#"{"eclipseMsg":"from_the_future","extra":{"x":1}}"#))
        #expect(envelope.kind == nil)
        #expect(TVSlideshowInterruption.stops(envelope.kind) == false)
    }

    @Test func playRequestFromOlderPhoneStillDecodes() throws {
        let envelope = try #require(decode(#"{"eclipseMsg":"play_request","id":"a.jpg","isFill":true}"#))
        #expect(envelope.kind == .playRequest)
        #expect(envelope.slideshow == nil)
    }

    @Test func unknownControlActionIsNil() throws {
        let envelope = try #require(decode(#"{"eclipseMsg":"slideshow_control","mode":"rewind"}"#))
        #expect(envelope.kind == .slideshowControl)
        #expect(envelope.slideshowControlAction == nil)
    }
}
