//
//  PendingUploadStoreTests.swift
//  EclipseiPhoneTests
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import Testing
import Foundation
@testable import EclipseiPhone

@MainActor
struct PendingUploadStoreTests {

    private let defaultsKey = "EclipseTV.companion.pendingUploads"

    private func makeItem(id: String, isVideo: Bool = false) -> LibraryItemDTO {
        LibraryItemDTO(
            id: id,
            name: id,
            isVideo: isVideo,
            duration: isVideo ? 12 : 0,
            isLooping: isVideo ? false : nil,
            isMuted: isVideo ? false : nil,
            isAvailable: true
        )
    }

    /// Isolates each test from leftover queue state in the shared store / UserDefaults.
    private func withCleanStore(_ body: (PendingUploadStore) throws -> Void) rethrows {
        let store = PendingUploadStore.shared
        store.removeAll()
        defer { store.removeAll() }
        try body(store)
    }

    @Test func enqueueAddsAndDedupesById() {
        withCleanStore { store in
            let first = makeItem(id: "photo.jpg")
            let duplicate = makeItem(id: "photo.jpg", isVideo: true)
            let second = makeItem(id: "clip.mp4", isVideo: true)

            store.enqueue(first)
            store.enqueue(duplicate)
            store.enqueue(second)

            #expect(store.uploads.count == 2)
            #expect(store.contains(id: "photo.jpg"))
            #expect(store.contains(id: "clip.mp4"))
            #expect(store.pendingIds == Set(["photo.jpg", "clip.mp4"]))
            #expect(store.items.map(\.id) == ["photo.jpg", "clip.mp4"])
            // First enqueue wins; duplicate must not replace the original entry.
            #expect(store.items.first?.isVideo == false)
        }
    }

    @Test func removeDropsMatchingId() {
        withCleanStore { store in
            store.enqueue(makeItem(id: "a.jpg"))
            store.enqueue(makeItem(id: "b.jpg"))

            store.remove(id: "a.jpg")

            #expect(!store.contains(id: "a.jpg"))
            #expect(store.contains(id: "b.jpg"))
            #expect(store.uploads.count == 1)
        }
    }

    @Test func persistRoundTripsThroughUserDefaults() throws {
        try withCleanStore { store in
            store.enqueue(makeItem(id: "kept.png"))
            store.enqueue(makeItem(id: "gone.png"))
            store.remove(id: "gone.png")

            let data = try #require(UserDefaults.standard.data(forKey: defaultsKey))
            let decoded = try JSONDecoder().decode(
                [PendingUploadStore.PendingUpload].self, from: data
            )

            #expect(decoded.map(\.item.id) == ["kept.png"])
            #expect(store.isEmpty == false)

            store.removeAll()
            #expect(store.isEmpty)
            #expect(UserDefaults.standard.data(forKey: defaultsKey) == nil)
        }
    }
}
