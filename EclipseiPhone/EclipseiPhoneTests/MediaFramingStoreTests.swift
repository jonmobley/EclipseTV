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

    @Test func framedStillCropsToTheDisplayAspectAndLetterboxes() {
        let id = uniqueId()
        defer { MediaFramingStore.clear(forId: id) }
        // A square unit rect on a square bitmap. The crop still comes out 16:9,
        // because that is the shape the tile and the panel are.
        MediaFramingStore.set(
            MediaFraming(x: 0.25, y: 0.25, width: 0.5, height: 0.5),
            forId: id
        )
        let source = swatch(size: CGSize(width: 100, height: 100))
        let framed = ExternalOutputOrientationFixture.with(.landscape) {
            MediaFramingStore.framedStill(
                source, forId: id, fallback: .scaleAspectFill
            )
        }
        #expect(framed.contentMode == .scaleAspectFit)
        let size = framed.image?.size ?? .zero
        #expect(abs(size.height - 50) < 1, "height \(size)")
        #expect(
            abs(size.width / size.height - MediaAspect.landscape) < 0.05,
            "size \(size)"
        )
    }

    @Test func framedStillKeepsTheDisplayAspectOnADifferentlyShapedBitmap() {
        // The seam that showed the user a thin band: the editor measures against the
        // full photo, and a consumer applies the unit rect to whatever bitmap it holds.
        // A 4:3 framing landing on a 16:9 bitmap must not come out 2.4:1.
        let id = uniqueId()
        defer { MediaFramingStore.clear(forId: id) }
        MediaFramingStore.set(
            MediaFraming(x: 0.1, y: 0.1, width: 0.6, height: 0.45),
            forId: id
        )
        let framed = ExternalOutputOrientationFixture.with(.landscape) {
            MediaFramingStore.framedStill(
                swatch(size: CGSize(width: 1600, height: 900)),
                forId: id,
                fallback: .scaleAspectFill
            )
        }
        let size = framed.image?.size ?? .zero
        #expect(
            abs(size.width / size.height - MediaAspect.landscape) < 0.05,
            "size \(size)"
        )
    }

    @Test func framedStillReshapesAFramingSavedInTheOtherDisplayMode() {
        // Switching Landscape → Vertical must not letterbox a 16:9 crop into a 9:16
        // tile as a thin band; the saved region is re-shaped to the active mode.
        let id = uniqueId()
        defer { MediaFramingStore.clear(forId: id) }
        MediaFramingStore.set(
            MediaFraming(x: 0.0, y: 0.4, width: 1.0, height: 0.28),
            forId: id
        )
        let framed = ExternalOutputOrientationFixture.with(.portrait) {
            MediaFramingStore.framedStill(
                swatch(size: CGSize(width: 1200, height: 1600)),
                forId: id,
                fallback: .scaleAspectFill
            )
        }
        let size = framed.image?.size ?? .zero
        #expect(
            abs(size.width / size.height - MediaAspect.vertical) < 0.05,
            "size \(size)"
        )
    }

    @Test func framedStillRendersAFitFramingWithBarsNotACrop() throws {
        // A framing zoomed out to Fit is wider than the photo. The tile gets the photo on
        // black at the display aspect, no larger than the photo's own longest edge.
        let id = uniqueId()
        defer { MediaFramingStore.clear(forId: id) }
        let source = swatch(size: CGSize(width: 1200, height: 1600))
        let fit = MediaCropGeometry.fitRect(in: source.size, aspect: MediaAspect.landscape)
        MediaFramingStore.set(MediaFraming(rect: fit, in: source.size), forId: id)

        let framed = ExternalOutputOrientationFixture.with(.landscape) {
            MediaFramingStore.framedStill(source, forId: id, fallback: .scaleAspectFill)
        }
        let image = try #require(framed.image)
        #expect(framed.contentMode == .scaleAspectFit)
        #expect(abs(image.size.width / image.size.height - MediaAspect.landscape) < 0.01)
        #expect(image.size.width <= 1600.5, "capped to the photo's longest edge")
        #expect(image.size.height < source.size.height, "shrunk with the canvas")
    }

    @Test func resolvedRectStaysInsideTheImageForAnOutOfBoundsFraming() throws {
        // A framing that arrived from another device (or an older build) can describe a
        // region that runs off this bitmap. `CGImage.cropping` would quietly hand back
        // the intersection — a strip — so the rect is moved inside first.
        let framing = MediaFraming(x: 0.8, y: 0.9, width: 0.5, height: 0.3)
        let size = CGSize(width: 1000, height: 1000)
        let crop = try #require(
            framing.resolvedRect(in: size, aspect: MediaAspect.landscape)
        )
        #expect(crop.minX >= -0.01)
        #expect(crop.minY >= -0.01)
        #expect(crop.maxX <= size.width + 0.01)
        #expect(crop.maxY <= size.height + 0.01)
        #expect(abs(crop.width / crop.height - MediaAspect.landscape) < 0.001)
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
