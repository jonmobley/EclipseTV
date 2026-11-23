//
//  MusicSyncMappingTests.swift
//  EclipseiPhoneTests
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import CloudKit
import Foundation
import Testing
@testable import EclipseiPhone

/// Record contract for songs and playlists shared with the Mac app.
@MainActor
struct MusicSyncMappingTests {

    private let clock = Date(timeIntervalSince1970: 1_800_000_000)

    // MARK: - Record names

    @Test func recordNamesArePrefixedUppercaseIds() {
        let id = UUID()
        let song = CloudKitSchema.audioTrackRecordID(for: id)
        let list = CloudKitSchema.audioPlaylistRecordID(for: id)
        #expect(song.recordName == "audio-" + id.uuidString)
        #expect(list.recordName == "playlist-" + id.uuidString)
        #expect(song.zoneID == CloudKitSchema.zoneID)
        #expect(CloudKitSchema.audioTrackId(fromRecordName: song.recordName) == id)
        #expect(CloudKitSchema.audioPlaylistId(fromRecordName: list.recordName) == id)
    }

    @Test func deletionRoutingUsesNamePrefixOnly() {
        let id = UUID()
        #expect(CloudKitSchema.audioTrackId(fromRecordName: id.uuidString) == nil)
        #expect(CloudKitSchema.audioTrackId(fromRecordName: "playlist-\(id)") == nil)
        #expect(CloudKitSchema.audioPlaylistId(fromRecordName: "audio-\(id)") == nil)
        #expect(CloudKitSchema.audioTrackId(fromRecordName: "audio-nope") == nil)
        #expect(CloudKitSchema.prompterShowId(fromRecordName: "audio-\(id)") == nil)
        #expect(CloudKitSyncEngine.isMusicRecordName("audio-\(id.uuidString)"))
        #expect(CloudKitSyncEngine.isMusicRecordName("playlist-\(id.uuidString)"))
        #expect(!CloudKitSyncEngine.isMusicRecordName(id.uuidString))
        #expect(!CloudKitSyncEngine.isMusicRecordName("prompter-\(id.uuidString)"))
    }

    @Test func tombstonesRouteByPrefixFromThePrivateZoneOnly() {
        let id = UUID()
        let zone = CloudKitSchema.zoneID
        let foreign = CKRecordZone.ID(zoneName: CloudKitSchema.zoneName, ownerName: "_someoneElse")
        typealias Schema = CloudKitSchema
        #expect(Schema.musicDeletion(recordName: "audio-\(id.uuidString)", zoneID: zone)
            == .track(id))
        #expect(Schema.musicDeletion(recordName: "playlist-\(id.uuidString)", zoneID: zone)
            == .playlist(id))
        #expect(Schema.musicDeletion(recordName: "audio-\(id.uuidString)", zoneID: foreign)
            == .ignored)
        #expect(Schema.musicDeletion(recordName: "playlist-\(id.uuidString)", zoneID: foreign)
            == .ignored)
        #expect(Schema.musicDeletion(recordName: id.uuidString, zoneID: zone) == nil)
        #expect(Schema.musicDeletion(recordName: "eclipse.background", zoneID: zone) == nil)
        #expect(Schema.musicDeletion(recordName: "prompter-\(id.uuidString)", zoneID: zone) == nil)
    }

    @Test func onlyTheOwnersPrivateLibraryZoneCounts() {
        #expect(CloudKitSchema.isPrivateLibraryZone(CloudKitSchema.zoneID))
        let shared = CKRecordZone.ID(zoneName: CloudKitSchema.zoneName, ownerName: "_someoneElse")
        #expect(!CloudKitSchema.isPrivateLibraryZone(shared))
        let other = CKRecordZone.ID(zoneName: "Other", ownerName: CKCurrentUserDefaultName)
        #expect(!CloudKitSchema.isPrivateLibraryZone(other))
    }

    @Test func songRecordFromSharedZoneIsNotApplied() {
        let recordID = CKRecord.ID(
            recordName: "audio-\(UUID().uuidString)",
            zoneID: CKRecordZone.ID(zoneName: CloudKitSchema.zoneName, ownerName: "_someoneElse")
        )
        let record = CKRecord(recordType: "AudioTrack", recordID: recordID)
        #expect(!CloudKitSchema.isPrivateLibraryZone(record.recordID.zoneID))
        #expect(!CloudKitRecordMapper.isPrivateToMe(record))
    }

    // MARK: - AudioTrack

    @Test func songRoundTripsWithIdFromName() throws {
        let track = AudioTrack(
            title: "Walk-in", artist: "House Band", duration: 182.5,
            fileExtension: "m4a", createdAt: Date(timeIntervalSince1970: 1_700_000_000)
        )
        let record = CloudKitRecordMapper.makeAudioTrackRecord(
            from: SyncedAudioTrack(track: track, modifiedAt: clock), assetURL: nil
        )
        #expect(record.recordType == "AudioTrack")
        #expect(record.parent == nil)
        #expect(record[CloudKitSchema.AudioTrackKey.asset] == nil)
        let decoded = try #require(CloudKitRecordMapper.audioTrack(from: record))
        #expect(decoded.track == track)
        #expect(decoded.modifiedAt == clock)
    }

    @Test func missingArtistIsAbsentAndReadsAsNone() throws {
        let track = AudioTrack(title: "Intro", artist: "  ", fileExtension: "mp3")
        let record = CloudKitRecordMapper.makeAudioTrackRecord(
            from: SyncedAudioTrack(track: track, modifiedAt: clock), assetURL: nil
        )
        #expect(record[CloudKitSchema.AudioTrackKey.artist] == nil)
        #expect(try #require(CloudKitRecordMapper.audioTrack(from: record)).track.artist == nil)
    }

    @Test func assetIsAttachedOnlyWhenGiven() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(UUID().uuidString).mp3")
        try Data([1, 2, 3]).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        let track = AudioTrack(title: "Song", fileExtension: "mp3")
        let record = CloudKitRecordMapper.makeAudioTrackRecord(
            from: SyncedAudioTrack(track: track, modifiedAt: clock), assetURL: url
        )
        #expect(CloudKitRecordMapper.audioTrackAssetURL(from: record) == url)
    }

    @Test func songWithNonMusicNameIsRejected() {
        let record = CKRecord(
            recordType: "AudioTrack",
            recordID: CKRecord.ID(recordName: UUID().uuidString, zoneID: CloudKitSchema.zoneID)
        )
        record[CloudKitSchema.AudioTrackKey.title] = "x" as CKRecordValue
        record[CloudKitSchema.AudioTrackKey.fileExtension] = "mp3" as CKRecordValue
        #expect(CloudKitRecordMapper.audioTrack(from: record) == nil)
    }

    // MARK: - AudioPlaylist

    @Test func playlistRoundTripsKeepingUnknownIdsInOrder() throws {
        let ids = [UUID(), UUID(), UUID()]
        let playlist = AudioPlaylist(
            name: "Pre-show", trackIds: ids, createdAt: Date(timeIntervalSince1970: 1_700_000_000)
        )
        let record = CloudKitRecordMapper.makeAudioPlaylistRecord(
            from: SyncedAudioPlaylist(playlist: playlist, modifiedAt: clock)
        )
        #expect(record.recordType == "AudioPlaylist")
        #expect(record.parent == nil)
        #expect(record[CloudKitSchema.AudioPlaylistKey.trackIds] as? [String]
            == ids.map(\.uuidString))
        let decoded = try #require(CloudKitRecordMapper.audioPlaylist(from: record))
        #expect(decoded.playlist == playlist)
        #expect(decoded.modifiedAt == clock)
    }

    @Test func emptyPlaylistClearsTrackIdsAndReadsBackEmpty() throws {
        let existing = CKRecord(
            recordType: "AudioPlaylist",
            recordID: CloudKitSchema.audioPlaylistRecordID(for: UUID())
        )
        existing[CloudKitSchema.AudioPlaylistKey.trackIds] = [UUID().uuidString] as CKRecordValue
        let id = try #require(CloudKitSchema.audioPlaylistId(
            fromRecordName: existing.recordID.recordName
        ))
        let playlist = AudioPlaylist(id: id, name: "Empty")
        let record = CloudKitRecordMapper.makeAudioPlaylistRecord(
            from: SyncedAudioPlaylist(playlist: playlist, modifiedAt: clock), existing: existing
        )
        #expect(record[CloudKitSchema.AudioPlaylistKey.trackIds] == nil)
        #expect(try #require(CloudKitRecordMapper.audioPlaylist(from: record)).playlist.trackIds
            .isEmpty)
    }

    @Test func playlistNameIsTrimmedAndClamped() throws {
        let long = "  " + String(repeating: "a", count: 60) + "  "
        let playlist = AudioPlaylist(name: long)
        let record = CloudKitRecordMapper.makeAudioPlaylistRecord(
            from: SyncedAudioPlaylist(playlist: playlist, modifiedAt: clock)
        )
        let name = try #require(record[CloudKitSchema.AudioPlaylistKey.name] as? String)
        #expect(name.count == UserDisplayName.maxLength)
        #expect(!name.hasPrefix(" "))
    }

    // MARK: - Policy

    @Test func protectedItemsAreNeverSendable() {
        let bundled = AudioTrack(
            id: DefaultBackgroundMusic.trackId, title: "Chill", fileExtension: "mp3"
        )
        let flagged = AudioTrack(title: "Mine", fileExtension: "mp3", isProtected: true)
        #expect(!MusicSyncPolicy.canSend(bundled, fileBytes: 10))
        #expect(!MusicSyncPolicy.canSend(flagged, fileBytes: 10))
        #expect(!MusicSyncPolicy.canSend(AudioPlaylist(
            id: DefaultBackgroundMusic.playlistId, name: "Background Music"
        )))
        #expect(!MusicSyncPolicy.canSend(AudioPlaylist(name: "P", isProtected: true)))
        #expect(MusicSyncPolicy.canSend(AudioPlaylist(name: "P")))
    }

    @Test func onlySupportedFormatsAndSizesAreSendable() {
        let mp3 = AudioTrack(title: "a", fileExtension: "mp3")
        let caf = AudioTrack(title: "a", fileExtension: "caf")
        #expect(MusicSyncPolicy.canSend(mp3, fileBytes: 1))
        #expect(MusicSyncPolicy.canSend(mp3, fileBytes: MusicSyncPolicy.maxFileBytes))
        #expect(!MusicSyncPolicy.canSend(mp3, fileBytes: 0))
        #expect(!MusicSyncPolicy.canSend(mp3, fileBytes: nil))
        #expect(!MusicSyncPolicy.canSend(mp3, fileBytes: MusicSyncPolicy.maxFileBytes + 1))
        #expect(!MusicSyncPolicy.canSend(caf, fileBytes: 10))
    }

    @Test func reorderKeepsUnknownIdsInTheirSlots() {
        let (a, b, x, c) = (UUID(), UUID(), UUID(), UUID())
        let merged = MusicSyncPolicy.mergeOrder(existing: [a, x, b, c], reordered: [c, a, b])
        #expect(merged == [c, x, a, b])
        #expect(MusicSyncPolicy.mergeOrder(existing: [x], reordered: []) == [x])
    }
}
