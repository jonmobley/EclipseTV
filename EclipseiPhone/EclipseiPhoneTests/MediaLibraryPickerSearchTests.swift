//
//  MediaLibraryPickerSearchTests.swift
//  EclipseiPhoneTests
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import Testing
import UIKit
@testable import EclipseiPhone

@Suite(.serialized)
@MainActor
struct MediaLibraryPickerSearchTests {

    @Test func blankSearchKeepsTypeFilter() {
        let picker = MediaLibraryPickerViewController()
        picker.filter = .all
        picker.searchQuery = ""
        let photo = still(id: uniqueId(), name: "IMG_1.JPG")
        let video = clip(id: uniqueId(), name: "CLIP.MOV")
        let pdf = SavedPDF(title: "Bulletin")
        let items = picker.displayedItems(from: [photo, video], pdfs: [pdf])
        #expect(items.count == 3)
    }

    @Test func searchMatchesOverlayTitleNotFilename() {
        let titledId = uniqueId()
        let otherId = uniqueId()
        defer {
            MediaTitleStore.clear(forId: titledId)
            MediaTitleStore.clear(forId: otherId)
        }
        MediaTitleStore.setTitle("Opening hymn", forId: titledId)

        let picker = MediaLibraryPickerViewController()
        picker.searchQuery = "hymn"
        let titled = still(id: titledId, name: "IMG_1.JPG")
        let other = still(id: otherId, name: "IMG_2.JPG")
        let items = picker.displayedItems(from: [titled, other], pdfs: [])
        #expect(items == [.media(titledId)])
    }

    @Test func searchMatchesPDFTitle() {
        let picker = MediaLibraryPickerViewController()
        picker.searchQuery = "bulletin"
        let pdf = SavedPDF(title: "Sunday Bulletin")
        let other = SavedPDF(title: "Order of Service")
        let items = picker.displayedItems(from: [], pdfs: [pdf, other])
        #expect(items == [.pdf(pdf.id)])
    }

    @Test func searchMatchesFilenameWhenUntitled() {
        let picker = MediaLibraryPickerViewController()
        picker.searchQuery = "IMG_1"
        let photo = still(id: uniqueId(), name: "IMG_1.JPG")
        let other = still(id: uniqueId(), name: "CLIP.MOV")
        let items = picker.displayedItems(from: [photo, other], pdfs: [])
        #expect(items == [.media(photo.id)])
    }

    @Test func videoFilterExcludesPDFAndStills() {
        let picker = MediaLibraryPickerViewController()
        picker.filter = .video
        picker.searchQuery = ""
        let photo = still(id: uniqueId(), name: "IMG_1.JPG")
        let video = clip(id: uniqueId(), name: "CLIP.MOV")
        let pdf = SavedPDF(title: "Bulletin")
        let items = picker.displayedItems(from: [photo, video], pdfs: [pdf])
        #expect(items == [.media(video.id)])
    }

    private func uniqueId() -> String {
        "lib-search-\(UUID().uuidString)"
    }

    private func still(id: String, name: String) -> LibraryItemDTO {
        LibraryItemDTO(
            id: id, name: name, isVideo: false, duration: 0, isAvailable: true
        )
    }

    private func clip(id: String, name: String) -> LibraryItemDTO {
        LibraryItemDTO(
            id: id, name: name, isVideo: true, duration: 12, isAvailable: true
        )
    }
}
