//
//  TemplateCardCodableTests.swift
//  EclipseiPhoneTests
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//
//  Checks that `OverlayCardConfig` reads and writes exactly the JSON the Mac
//  writes into the `TemplateCard.config` field.
//

import Foundation
import Testing
@testable import EclipseiPhone

struct TemplateCardCodableTests {

    /// Written by hand to match the Mac's `OverlayCardConfig` encoded with
    /// `JSONEncoder()` + `.sortedKeys` (default strategies): every optional set.
    static let macFullJSON = """
    {"autoRemoveAfterSeconds":20,"corner":"bottomLeading",\
    "fields":{"name":"Jane Doe","org":"Eclipse","role":"Host"},\
    "madeByAI":true,"placement":{"centerX":0.25,"centerY":0.8,"scale":1.5},\
    "style":{"accentColor":{"alpha":1,"blue":0.1,"green":0.6,"red":1},\
    "backgroundColor":{"alpha":1,"blue":0.05,"green":0.04,"red":0.04},\
    "backgroundOpacity":0.9,"cornerRadius":12,"fontDesign":"serif",\
    "showsIcon":false,"subtitleColor":{"alpha":0.8,"blue":1,"green":1,"red":1},\
    "subtitleSize":28,"textAlignment":"center",\
    "textColor":{"alpha":1,"blue":1,"green":1,"red":1},\
    "titleSize":44,"titleWeight":"heavy"},"template":"lowerThird"}
    """

    /// An older Mac card: no style, placement, auto-remove, or AI flag.
    static let macMinimalJSON = """
    {"corner":"topTrailing","fields":{"network":"Venue","password":"secret"},"template":"wifi"}
    """

    @Test func decodesEveryFieldTheMacWrites() throws {
        let config = try #require(OverlayCardConfig.fromSyncJSON(Self.macFullJSON))
        #expect(config.template == .lowerThird)
        #expect(config.corner == .bottomLeading)
        #expect(config.fields["name"] == "Jane Doe")
        #expect(config.placement == OverlayCardPlacement(centerX: 0.25, centerY: 0.8, scale: 1.5))
        #expect(config.autoRemoveAfterSeconds == 20)
        #expect(config.madeByAI == true)
        let style = try #require(config.style)
        #expect(style.fontDesign == .serif)
        #expect(style.titleWeight == .heavy)
        #expect(style.textAlignment == .center)
        #expect(style.cornerRadius == 12)
        #expect(style.accentColor == RGBAColor(red: 1, green: 0.6, blue: 0.1))
    }

    @Test func reEncodesByteForByteLikeTheMac() throws {
        for json in [Self.macFullJSON, Self.macMinimalJSON] {
            let config = try #require(OverlayCardConfig.fromSyncJSON(json))
            #expect(config.syncJSONString() == json)
        }
    }

    @Test func olderMacCardDecodesWithDefaults() throws {
        let config = try #require(OverlayCardConfig.fromSyncJSON(Self.macMinimalJSON))
        #expect(config.template == .wifi)
        #expect(config.style == nil)
        #expect(config.placement == nil)
        #expect(config.madeByAI == nil)
        #expect(config.resolvedStyle == OverlayCardTemplate.descriptor(for: .wifi).defaultStyle)
    }

    @Test func unknownTemplateKindIsRejectedNotCrashed() {
        let json = Self.macMinimalJSON.replacingOccurrences(of: "\"wifi\"", with: "\"hologram\"")
        #expect(OverlayCardConfig.fromSyncJSON(json) == nil)
        #expect(OverlayCardConfig.fromSyncJSON("not json") == nil)
        #expect(OverlayCardConfig.fromSyncJSON(nil) == nil)
    }

    @Test func everyTemplateRoundTrips() throws {
        #expect(OverlayCardTemplateKind.allCases.count == 27)
        for template in OverlayCardTemplate.all {
            let json = try #require(template.sampleConfig.syncJSONString())
            #expect(OverlayCardConfig.fromSyncJSON(json) == template.sampleConfig)
        }
    }

    @Test func rawValuesMatchTheMac() {
        let raw = OverlayCardTemplateKind.allCases.map(\.rawValue)
        #expect(raw.first == "wifi")
        #expect(raw.contains("scoreboardSeries"))
        #expect(raw.contains("lowerThirdGlass"))
        #expect(OverlayCardCategory.sports.rawValue == "sports")
        #expect(OverlayCorner.bottomTrailing.rawValue == "bottomTrailing")
    }
}
