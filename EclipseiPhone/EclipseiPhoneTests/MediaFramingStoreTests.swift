//
//  MediaFramingStoreTests.swift
//  EclipseiPhoneTests
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import Testing
import UIKit
@testable import EclipseiPhone

@Suite(.serialized)
@MainActor
struct MediaFramingStoreTests {

    @Test func storeRoundTripPersistsNormalizedRect() {
        let id = uniqueId()
        defer { MediaFramingStore.clear(forId: id) }
        let framing = MediaFraming(x: 0.1, y: 0.2, width: 0.5, height: 0.4)
        MediaFramingStore.set(framing, forId: id)
        let loaded = MediaFramingStore.framing(forId: id)
        #expect(loaded == framing)
        #expect(MediaFramingStore.hasFraming(forId: id))
    }

    @Test func clearRemovesStoredFraming() {
        let id = uniqueId()
        MediaFramingStore.set(
            MediaFraming(x: 0, y: 0, width: 1, height: 1),
            forId: id
        )
        MediaFramingStore.clear(forId: id)
        #expect(MediaFramingStore.framing(forId: id) == nil)
        #expect(!MediaFramingStore.hasFraming(forId: id))
    }

    @Test func rectConvertersScaleAcrossImageSizes() {
        let framing = MediaFraming(x: 0.25, y: 0.1, width: 0.5, height: 0.8)
        let full = framing.rect(in: CGSize(width: 4000, height: 3000))
        let thumb = framing.rect(in: CGSize(width: 400, height: 300))
        #expect(abs(full.origin.x / 4000 - thumb.origin.x / 400) < 0.0001)
        #expect(abs(full.origin.y / 3000 - thumb.origin.y / 300) < 0.0001)
        #expect(abs(full.width / 4000 - thumb.width / 400) < 0.0001)
        #expect(abs(full.height / 3000 - thumb.height / 300) < 0.0001)

        let rebuilt = MediaFraming(rect: full, in: CGSize(width: 4000, height: 3000))
        #expect(abs(rebuilt.x - framing.x) < 0.0001)
        #expect(abs(rebuilt.y - framing.y) < 0.0001)
        #expect(abs(rebuilt.width - framing.width) < 0.0001)
        #expect(abs(rebuilt.height - framing.height) < 0.0001)
    }

    @Test func framedStillCropsAndLetterboxesWhenPresent() {
        let id = uniqueId()
        defer { MediaFramingStore.clear(forId: id) }
        // Solid 100×100; crop the center 50×50.
        MediaFramingStore.set(
            MediaFraming(x: 0.25, y: 0.25, width: 0.5, height: 0.5),
            forId: id
        )
        let source = swatch(size: CGSize(width: 100, height: 100))
        let framed = MediaFramingStore.framedStill(
            source, forId: id, fallback: .scaleAspectFill
        )
        #expect(framed.contentMode == .scaleAspectFit)
        #expect(framed.image != nil)
        #expect(abs((framed.image?.size.width ?? 0) - 50) < 1)
        #expect(abs((framed.image?.size.height ?? 0) - 50) < 1)
    }

    @Test func framedStillPassesThroughWithoutFraming() {
        let id = uniqueId()
        defer { MediaFramingStore.clear(forId: id) }
        let source = swatch(size: CGSize(width: 40, height: 40))
        let framed = MediaFramingStore.framedStill(
            source, forId: id, fallback: .scaleAspectFill
        )
        #expect(framed.contentMode == .scaleAspectFill)
        #expect(framed.image === source || framed.image?.size == source.size)
    }

    @Test func envelopeEncodesAndDecodesFraming() throws {
        let dto = MediaFramingDTO(x: 0.1, y: 0.2, width: 0.3, height: 0.4)
        let envelope = EclipseShareEnvelope.setImageFit(
            id: "photo.jpg",
            isFill: true,
            framing: dto
        )
        let data = try #require(envelope.encoded())
        let decoded = try #require(EclipseShareEnvelope.decode(from: data))
        #expect(decoded.framing == dto)
        #expect(decoded.isFill == true)
        #expect(decoded.id == "photo.jpg")
    }

    @Test func envelopeWithoutFramingStillDecodes() throws {
        let envelope = EclipseShareEnvelope.setImageFit(
            id: "photo.jpg",
            isFill: false
        )
        let data = try #require(envelope.encoded())
        let decoded = try #require(EclipseShareEnvelope.decode(from: data))
        #expect(decoded.framing == nil)
        #expect(decoded.isFill == false)
    }

    @Test func presentationSourceEqualityChangesWithFraming() {
        let url = URL(fileURLWithPath: "/tmp/still.jpg")
        let a = PresentationSource.image(url, fill: true)
        let framing = MediaFraming(x: 0, y: 0, width: 0.5, height: 0.5)
        let b = PresentationSource.image(url, fill: true, framing: framing)
        #expect(a != b)
        #expect(a == PresentationSource.image(url, fill: true))
    }

    private func uniqueId() -> String {
        "framing-test-\(UUID().uuidString)"
    }

    private func swatch(size: CGSize) -> UIImage {
        UIGraphicsImageRenderer(size: size).image { ctx in
            UIColor.gray.setFill()
            ctx.fill(CGRect(origin: .zero, size: size))
        }
    }
}
