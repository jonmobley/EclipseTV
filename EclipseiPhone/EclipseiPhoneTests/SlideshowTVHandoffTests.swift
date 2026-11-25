//
//  SlideshowTVHandoffTests.swift
//  EclipseiPhoneTests
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import Foundation
import MultipeerConnectivity
import Testing
@testable import EclipseiPhone

/// When the phone hands a whole slideshow to the Apple TV, and when it falls
/// back to sending one photo at a time (older TVs, phone-only slides).
struct SlideshowTVHandoffTests {

    @Test func olderTVGetsPhotoByPhoto() {
        #expect(!SlideshowTVHandoff.tvRunsSlideshow(
            tvSupportsSlideshow: false, slideIds: ["a", "b"], isPhoneOnly: { _ in false }
        ))
    }

    @Test func capableTVRunsIt() {
        #expect(SlideshowTVHandoff.tvRunsSlideshow(
            tvSupportsSlideshow: true, slideIds: ["a", "b"], isPhoneOnly: { _ in false }
        ))
    }

    @Test func phoneOnlySlideKeepsPhotoByPhoto() {
        #expect(!SlideshowTVHandoff.tvRunsSlideshow(
            tvSupportsSlideshow: true, slideIds: ["a", "cap"], isPhoneOnly: { $0 == "cap" }
        ))
        #expect(!SlideshowTVHandoff.tvRunsSlideshow(
            tvSupportsSlideshow: true, slideIds: [], isPhoneOnly: { _ in false }
        ))
    }

    @Test func dtoCarriesTimingLoopCrossfadeAndFraming() {
        let show = Slideshow(
            showId: UUID(), name: "Test", itemIds: ["a", "b"],
            orientation: .landscape, autoplay: true, autoplaySeconds: .ten,
            loop: true, crossfade: false
        )
        let crop = MediaFramingDTO(x: 0, y: 0, width: 0.5, height: 0.5)
        let dto = SlideshowTVHandoff.makeDTO(
            for: show, slideIds: ["a", "b"], startIndex: 1,
            framing: { id in
                id == "b" ? .init(isFill: true, framing: crop) : .init(isFill: false, framing: nil)
            }
        )
        #expect(dto.seconds == 10)
        #expect(dto.loops)
        #expect(!dto.crossfades)
        #expect(dto.startIndex == 1)
        #expect(dto.slides == [
            SlideshowSlideDTO(id: "a", isFill: false, framing: nil),
            SlideshowSlideDTO(id: "b", isFill: true, framing: crop)
        ])
    }

    @Test func autoplayOffMeansTheTVWaitsForSteps() {
        let show = Slideshow(showId: UUID(), name: "Manual", itemIds: ["a"], orientation: .landscape)
        let dto = SlideshowTVHandoff.makeDTO(
            for: show, slideIds: ["a"], startIndex: 0,
            framing: { _ in .init(isFill: false, framing: nil) }
        )
        #expect(dto.seconds == nil)
    }

    @Test @MainActor func capabilitiesFollowEachTV() {
        let registry = AppleTVCapabilities()
        let newTV = MCPeerID(displayName: "New TV")
        let oldTV = MCPeerID(displayName: "Old TV")
        registry.record(EclipseShareCapability.advertisedByTV, for: newTV)
        registry.record(nil, for: oldTV)
        #expect(registry.supportsSlideshow(newTV))
        #expect(!registry.supportsSlideshow(oldTV))
        #expect(!registry.supportsSlideshow(nil))
        registry.forget(newTV)
        #expect(!registry.supportsSlideshow(newTV))
    }

    @Test func manifestFromOlderTVHasNoCapabilities() throws {
        let json = #"{"eclipseMsg":"library_manifest","items":[],"currentId":null}"#
        let envelope = try #require(EclipseShareEnvelope.decode(from: Data(json.utf8)))
        #expect(!EclipseShareCapability.supportsSlideshow(envelope.capabilities))
    }
}
