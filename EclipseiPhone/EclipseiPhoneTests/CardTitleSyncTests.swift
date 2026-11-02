//
//  CardTitleSyncTests.swift
//  EclipseiPhoneTests
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import CloudKit
import Foundation
import Testing
import UIKit
@testable import EclipseiPhone

/// Card titles (name + Show / Hide Title) match the Mac app and travel through
/// iCloud: `displayName` on MediaItem records, `titleShown` on every titled kind.
@Suite(.serialized)
@MainActor
struct CardTitleSyncTests {

    // MARK: - Defaults

    @Test func defaultsFollowTheMacRule() {
        #expect(!ThumbnailTypeIcon.photo.showsTitleByDefault)
        #expect(!ThumbnailTypeIcon.video.showsTitleByDefault)
        #expect(!ThumbnailTypeIcon.slideshow.showsTitleByDefault)
        #expect(!ThumbnailTypeIcon.pdf.showsTitleByDefault)
        #expect(ThumbnailTypeIcon.website.showsTitleByDefault)
        #expect(ThumbnailTypeIcon.webVideo.showsTitleByDefault)
        #expect(ThumbnailTypeIcon.livePoll.showsTitleByDefault)
        #expect(ThumbnailTypeIcon.countdown.showsTitleByDefault)
        #expect(ThumbnailTypeIcon.camera.showsTitleByDefault)
    }

    @Test func choiceOverridesTheDefault() {
        let id = uniqueId()
        defer { reset(id) }
        #expect(!CardTitleVisibility.isShown(forId: id, kind: .pdf))
        #expect(CardTitleVisibility.menuTitle(forId: id, kind: .pdf) == "Show Title")
        CardTitleVisibility.setShown(true, forId: id)
        #expect(CardTitleVisibility.isShown(forId: id, kind: .pdf))
        #expect(CardTitleVisibility.menuTitle(forId: id, kind: .pdf) == "Hide Title")
        CardTitleVisibility.setShown(false, forId: id)
        #expect(!CardTitleVisibility.isShown(forId: id, kind: .website))
    }

    @Test func fixedTitleTilesHaveNoChoice() {
        #expect(ShowGridItem.screensaver.cardTitle == nil)
        #expect(ShowGridItem.logo.cardTitle == nil)
        #expect(ShowGridItem.camera.cardTitle == nil)
        #expect(ShowGridItem.ptzCamera.cardTitle == nil)
        #expect(ShowGridItem.screensaver.isTitleShown)
    }

    // MARK: - iCloud: titleShown

    @Test func choiceRoundTripsThroughARecord() {
        let id = uniqueId()
        defer { reset(id) }
        let record = toolRecord()
        CardTitleVisibility.write(to: record, id: id)
        #expect(record[CloudKitSchema.titleShownKey] == nil)

        CardTitleVisibility.setShown(true, forId: id)
        CardTitleVisibility.write(to: record, id: id)
        #expect(record[CloudKitSchema.titleShownKey] as? Bool == true)
    }

    @Test func remoteChoiceAppliesOnceTheLocalOneWasSaved() {
        let id = uniqueId()
        defer { reset(id) }
        CardTitleVisibility.setShown(true, forId: id)

        let theirs = toolRecord(shown: false)
        CardTitleVisibility.applyRemote(from: theirs, id: id)
        #expect(CardTitleVisibility.choice(forId: id) == true)

        CardTitleVisibility.noteSaved(id: id)
        CardTitleVisibility.applyRemote(from: theirs, id: id)
        #expect(CardTitleVisibility.choice(forId: id) == false)
    }

    @Test func recordWithoutTheFieldKeepsTheDefault() {
        let id = uniqueId()
        defer { reset(id) }
        CardTitleVisibility.applyRemote(from: toolRecord(), id: id)
        #expect(CardTitleVisibility.choice(forId: id) == nil)
        #expect(CardTitleVisibility.isShown(forId: id, kind: .countdown))
    }

    @Test func toolRecordsCarryTheChoice() {
        let page = WebPage(title: "Site", url: URL(string: "https://example.com")!)
        defer { reset(page.id.uuidString) }
        CardTitleVisibility.setShown(false, forId: page.id.uuidString)
        let record = CloudKitRecordMapper.makeWebPageRecord(from: page)
        #expect(record[CloudKitSchema.titleShownKey] as? Bool == false)
        #expect(CloudKitRecordMapper.cardTitleId(for: record) == page.id.uuidString)
    }

    // MARK: - iCloud: media titles

    @Test func mediaTitleAndChoiceTravelOnTheMediaRecord() {
        let id = uniqueId()
        defer { reset(id) }
        MediaTitleStore.setTitle("Welcome", forId: id)
        CardTitleVisibility.setShown(true, forId: id)
        let outgoing = mediaRecord()
        CloudKitRecordMapper.applyMediaPrefs(to: outgoing, libraryId: id, isVideo: false)
        #expect(outgoing[CloudKitSchema.MediaKey.displayName] as? String == "Welcome")
        #expect(outgoing[CloudKitSchema.titleShownKey] as? Bool == true)

        // Deleting the title here removes the name instead of leaving the old one.
        MediaTitleStore.setTitle("", forId: id)
        CloudKitRecordMapper.applyMediaPrefs(to: outgoing, libraryId: id, isVideo: false)
        #expect(outgoing[CloudKitSchema.MediaKey.displayName] == nil)
    }

    @Test func untitledItemLeavesAMacNameAlone() {
        let id = uniqueId()
        defer { reset(id) }
        let outgoing = mediaRecord()
        outgoing[CloudKitSchema.MediaKey.displayName] = "From the Mac" as CKRecordValue
        CloudKitRecordMapper.applyMediaPrefs(to: outgoing, libraryId: id, isVideo: false)
        #expect(outgoing[CloudKitSchema.MediaKey.displayName] as? String == "From the Mac")
    }

    @Test func remoteNameAndChoiceApply() {
        let id = uniqueId()
        defer { reset(id) }
        let incoming = mediaRecord()
        incoming[CloudKitSchema.MediaKey.displayName] = "Sermon slide" as CKRecordValue
        incoming[CloudKitSchema.titleShownKey] = true as CKRecordValue
        CloudKitRecordMapper.applyRemoteMediaPrefs(from: incoming, libraryId: id)
        #expect(MediaTitleStore.title(forId: id) == "Sermon slide")
        #expect(CardTitleVisibility.isShown(forId: id, kind: .photo))
    }

    @Test func sharedShowRecordsCarryTitlesToo() {
        let id = uniqueId()
        defer { reset(id) }
        let shared = mediaRecord()
        shared.parent = CKRecord.Reference(
            recordID: CKRecord.ID(recordName: UUID().uuidString), action: .none
        )
        shared[CloudKitSchema.MediaKey.displayName] = "Shared name" as CKRecordValue
        shared[CloudKitSchema.titleShownKey] = true as CKRecordValue
        CloudKitRecordMapper.applyRemoteMediaPrefs(from: shared, libraryId: id)
        #expect(MediaTitleStore.title(forId: id) == "Shared name")
        #expect(CardTitleVisibility.choice(forId: id) == true)
    }

    @Test func pendingLocalEditsKeepTheLocalName() {
        let id = uniqueId()
        defer { reset(id) }
        MediaTitleStore.setTitle("Mine", forId: id)
        let incoming = mediaRecord()
        incoming[CloudKitSchema.MediaKey.displayName] = "Older" as CKRecordValue
        CloudKitRecordMapper.applyRemoteMediaPrefs(
            from: incoming, libraryId: id, hasPendingLocalEdits: true
        )
        #expect(MediaTitleStore.title(forId: id) == "Mine")
    }

    @Test func titledItemsStayShownAfterTheUpgrade() {
        let titled = uniqueId()
        let hidden = uniqueId()
        defer {
            reset(titled)
            reset(hidden)
        }
        CardTitleVisibility.setShown(false, forId: hidden)
        let queued = CardTitleVisibility.keepShown([titled, hidden])
        #expect(queued == [titled, hidden])
        #expect(CardTitleVisibility.choice(forId: titled) == true)
        #expect(CardTitleVisibility.choice(forId: hidden) == false)
    }

    // MARK: - Tiles

    @Test func photoTileHidesItsTitleByDefault() {
        let id = uniqueId()
        defer { reset(id) }
        MediaTitleStore.setTitle("Welcome", forId: id)
        let cell = makeCell()
        cell.configure(with: item(id), thumbnail: nil, isLive: false)
        #expect(cell.captionLabel.isHidden)
        #expect(cell.accessibilityLabel?.hasPrefix("Welcome") == true)

        CardTitleVisibility.setShown(true, forId: id)
        cell.configure(with: item(id), thumbnail: nil, isLive: false)
        #expect(!cell.captionLabel.isHidden)
        #expect(cell.captionLabel.text == "Welcome")
    }

    @Test func shownUntitledPhotoSaysPhotoLikeTheMac() {
        let id = uniqueId()
        defer { reset(id) }
        CardTitleVisibility.setShown(true, forId: id)
        let cell = makeCell()
        cell.configure(with: item(id), thumbnail: nil, isLive: false)
        #expect(cell.captionLabel.text == "Photo")
    }

    @Test func hiddenSpecialTileDropsItsCaption() {
        let cell = makeCell()
        cell.configureSpecial(
            title: "Notes.pdf",
            systemImage: "doc.richtext",
            thumbnail: nil,
            fillColor: .darkGray,
            isLive: false,
            typeIcon: .pdf
        )
        cell.applyTitleVisibility(false)
        #expect(cell.captionLabel.isHidden)
        #expect(cell.accessibilityLabel?.contains("Notes.pdf") == true)
    }

    // MARK: - Helpers

    private func item(_ id: String) -> LibraryItemDTO {
        LibraryItemDTO(id: id, name: id, isVideo: false, duration: 0, isAvailable: true)
    }

    private func makeCell() -> LibraryThumbnailCell {
        LibraryThumbnailCell(frame: CGRect(x: 0, y: 0, width: 160, height: 90))
    }

    private func toolRecord(shown: Bool? = nil) -> CKRecord {
        let record = CKRecord(
            recordType: CloudKitSchema.RecordType.countdown,
            recordID: CKRecord.ID(recordName: UUID().uuidString)
        )
        if let shown { record[CloudKitSchema.titleShownKey] = shown as CKRecordValue }
        return record
    }

    private func mediaRecord() -> CKRecord {
        let record = CKRecord(
            recordType: CloudKitSchema.RecordType.mediaItem,
            recordID: CKRecord.ID(recordName: UUID().uuidString)
        )
        record[CloudKitSchema.MediaKey.isVideo] = false as CKRecordValue
        record[CloudKitSchema.MediaKey.fitMode] = MediaFitMode.fit.rawValue as CKRecordValue
        return record
    }

    private func uniqueId() -> String {
        "card-title-test-\(UUID().uuidString)"
    }

    private func reset(_ id: String) {
        MediaTitleStore.clear(forId: id)
        CardTitleVisibility.clear(forId: id)
        MediaFitSettings.clear(forId: id)
        MediaFramingStore.clear(forId: id)
    }
}
