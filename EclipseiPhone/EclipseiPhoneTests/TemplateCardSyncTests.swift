//
//  TemplateCardSyncTests.swift
//  EclipseiPhoneTests
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//
//  TemplateCard iCloud record mapping, Show surface tokens, and the local store.
//

import CloudKit
import Foundation
import Testing
@testable import EclipseiPhone

@MainActor
struct TemplateCardSyncTests {

    // MARK: - Record Mapping

    @Test func recordRoundTripKeepsEveryField() throws {
        let config = try #require(OverlayCardConfig.fromSyncJSON(TemplateCardCodableTests.macFullJSON))
        let card = ShowTemplateCard(showId: UUID(), name: "Host", config: config, stackOrder: 4)
        let record = try #require(CloudKitRecordMapper.makeTemplateCardRecord(from: card))
        #expect(record.recordType == "TemplateCard")
        #expect(record.recordID.recordName == card.id.uuidString)
        #expect(record.recordID.zoneID == CloudKitSchema.zoneID)
        #expect(record["template"] as? String == "lowerThird")
        #expect(record["config"] as? String == TemplateCardCodableTests.macFullJSON)
        #expect(record["stackOrder"] as? Int64 == 4)
        #expect(record["showId"] as? String == card.showId.uuidString)
        #expect(record.parent == nil)

        let decoded = try #require(CloudKitRecordMapper.templateCard(from: record))
        #expect(decoded == card)
    }

    @Test func shareChildIsParentedToItsShow() throws {
        let card = ShowTemplateCard(
            showId: UUID(), config: OverlayCardTemplate.descriptor(for: .wifi).sampleConfig
        )
        let record = try #require(
            CloudKitRecordMapper.makeTemplateCardRecord(from: card, attachAsShareChild: true)
        )
        #expect(record.parent?.recordID == CloudKitSchema.showRecordID(for: card.showId))
    }

    @Test func recordFromTheMacDecodesLeniently() throws {
        let record = makeMacRecord(template: "wifi", config: TemplateCardCodableTests.macMinimalJSON)
        record["stackOrder"] = nil
        let card = try #require(CloudKitRecordMapper.templateCard(from: record))
        #expect(card.stackOrder == 0)
        #expect(card.config.template == .wifi)
    }

    @Test func unknownTemplateOrBadConfigIsSkipped() {
        let unknown = makeMacRecord(template: "hologram", config: TemplateCardCodableTests.macMinimalJSON)
        #expect(CloudKitRecordMapper.templateCard(from: unknown) == nil)
        let badConfig = makeMacRecord(template: "wifi", config: "{")
        #expect(CloudKitRecordMapper.templateCard(from: badConfig) == nil)
        let missing = makeMacRecord(template: "wifi", config: nil)
        #expect(CloudKitRecordMapper.templateCard(from: missing) == nil)
    }

    // MARK: - Surface Tokens

    @Test func templateTokenRoundTrips() {
        let id = UUID()
        let token = ShowTemplateToken.token(for: id)
        #expect(token == "__eclipse.template.\(id.uuidString)")
        #expect(ShowTemplateToken.templateId(from: token) == id)
        #expect(ShowTemplateToken.templateId(from: ShowCountdownToken.token(for: id)) == nil)
        #expect(!ShowToolToken.isTool(token))
    }

    @Test func sanitizerKeepsTemplateTokens() {
        let token = ShowTemplateToken.token(for: UUID())
        let result = LocalAlbum.sanitizedSurface(["a", token, "gone"], itemIds: ["a"])
        #expect(result == ["a", token])
    }

    @Test func addAndRemoveTemplateTombstonesTheToken() throws {
        let store = makeAlbumStore()
        let show = try store.create(name: "Graphics", orientation: .landscape)
        let cardId = UUID()
        let token = ShowTemplateToken.token(for: cardId)
        store.addTemplate(cardId, toAlbumId: show.id)
        var album = try #require(store.album(id: show.id))
        #expect(album.resolvedSurfaceIds.last == token)
        #expect(!album.itemIds.contains(token))

        store.removeTemplate(cardId, fromAlbumId: show.id)
        album = try #require(store.album(id: show.id))
        #expect(album.surfaceIds?.contains(token) != true)
        #expect(SyncTombstones.isRemoved(token, in: album.deletedSurfaceIds))
    }

    // MARK: - Store

    @Test func storeStacksNewCardsOnTopAndAppliesRemote() {
        let store = makeCardStore()
        let showId = UUID()
        let wifi = OverlayCardTemplate.descriptor(for: .wifi).sampleConfig
        let first = store.create(config: wifi, showId: showId)
        let second = store.create(config: wifi, name: "  Guest Wi-Fi ", showId: showId)
        #expect(first.stackOrder == 0)
        #expect(second.stackOrder == 1)
        #expect(second.name == "Guest Wi-Fi")
        #expect(first.name == OverlayCardTemplate.descriptor(for: .wifi).displayName)
        #expect(store.idsNeedingUpload.count == 2)

        store.markSynced(id: first.id)
        #expect(store.idsNeedingUpload == [second.id])

        var edited = second
        edited.name = "Edited on Mac"
        store.applyRemote(edited)
        #expect(store.card(id: second.id)?.name == "Edited on Mac")
        #expect(store.idsNeedingUpload.isEmpty)

        store.purgeRemote(id: first.id)
        #expect(store.cards(forShowId: showId).map(\.id) == [second.id])
    }

    // MARK: - Helpers

    private func makeMacRecord(template: String, config: String?) -> CKRecord {
        let record = CKRecord(
            recordType: "TemplateCard",
            recordID: CKRecord.ID(recordName: UUID().uuidString, zoneID: CloudKitSchema.zoneID)
        )
        record["showId"] = UUID().uuidString as CKRecordValue
        record["name"] = "From Mac" as CKRecordValue
        record["template"] = template as CKRecordValue
        record["config"] = config.map { $0 as CKRecordValue }
        record["stackOrder"] = Int64(2) as CKRecordValue
        record["createdAt"] = Date() as CKRecordValue
        record["modifiedAt"] = Date() as CKRecordValue
        return record
    }

    private func makeAlbumStore() -> LocalAlbumStore {
        let suite = "TemplateCardSyncTests.albums.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return LocalAlbumStore(defaults: defaults)
    }

    private func makeCardStore() -> TemplateCardStore {
        let suite = "TemplateCardSyncTests.cards.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return TemplateCardStore(defaults: defaults, schedulesSync: false)
    }
}
