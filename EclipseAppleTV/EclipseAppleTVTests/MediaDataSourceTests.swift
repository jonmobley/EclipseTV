//
//  MediaDataSourceTests.swift
//  EclipseAppleTVTests
//
//  Unit tests for the single source of truth: add/remove/move index math,
//  navigation bounds, persistence round-trips, and the directory-remap migration.
//

import Testing
import Foundation
@testable import EclipseAppleTV

struct MediaDataSourceTests {

    // MARK: - Helpers

    /// Creates a `MediaDataSource` backed by an isolated `UserDefaults` suite so tests
    /// never touch `.standard`. The returned cleanup closure removes the suite.
    private func makeSUT() -> (sut: MediaDataSource, cleanup: () -> Void) {
        let suiteName = "MediaDataSourceTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        let sut = MediaDataSource(defaults: defaults)
        return (sut, { defaults.removePersistentDomain(forName: suiteName) })
    }

    /// Writes `count` tiny temp files and returns their paths. Caller deletes them.
    private func makeTempFiles(_ count: Int) -> [String] {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("MediaDataSourceTests.\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return (0..<count).map { i in
            let url = dir.appendingPathComponent("file\(i).jpg")
            try? Data([0x00]).write(to: url)
            return url.path
        }
    }

    private func deleteTempFiles(_ paths: [String]) {
        for path in paths {
            try? FileManager.default.removeItem(atPath: path)
        }
    }

    // MARK: - Add

    @Test func addMediaAppendsAndDeduplicates() {
        let (sut, cleanup) = makeSUT()
        defer { cleanup() }

        sut.addMedia(at: "/tmp/a.jpg")
        sut.addMedia(at: "/tmp/b.jpg")
        sut.addMedia(at: "/tmp/a.jpg") // duplicate ignored

        #expect(sut.count == 2)
        #expect(sut.mediaPaths == ["/tmp/a.jpg", "/tmp/b.jpg"])
    }

    @Test func addMediaBatchFiltersDuplicates() {
        let (sut, cleanup) = makeSUT()
        defer { cleanup() }

        sut.addMedia(at: "/tmp/a.jpg")
        sut.addMediaBatch(paths: ["/tmp/a.jpg", "/tmp/b.jpg", "/tmp/c.jpg", "/tmp/b.jpg"])

        #expect(sut.mediaPaths == ["/tmp/a.jpg", "/tmp/b.jpg", "/tmp/c.jpg"])
    }

    // MARK: - Remove index adjustment

    @Test func removeBeforeCurrentShiftsIndexBack() {
        let (sut, cleanup) = makeSUT()
        defer { cleanup() }
        ["/tmp/a", "/tmp/b", "/tmp/c", "/tmp/d"].forEach { sut.addMedia(at: $0) }
        sut.setCurrentIndex(2) // "/tmp/c"

        sut.removeMedia(at: 0)

        #expect(sut.currentIndex == 1)
        #expect(sut.getCurrentPath() == "/tmp/c") // still pointing at same item
    }

    @Test func removeCurrentAtEndClampsToNewLast() {
        let (sut, cleanup) = makeSUT()
        defer { cleanup() }
        ["/tmp/a", "/tmp/b", "/tmp/c"].forEach { sut.addMedia(at: $0) }
        sut.setCurrentIndex(2) // "/tmp/c"

        sut.removeMedia(at: 2)

        #expect(sut.currentIndex == 1)
        #expect(sut.getCurrentPath() == "/tmp/b")
    }

    @Test func removeLastRemainingResetsToEmptyState() {
        let (sut, cleanup) = makeSUT()
        defer { cleanup() }
        sut.addMedia(at: "/tmp/only.jpg")

        sut.removeMedia(at: 0)

        #expect(sut.isEmpty)
        #expect(sut.currentIndex == 0)
        #expect(sut.getCurrentPath() == nil)
    }

    // MARK: - Move index adjustment

    @Test func moveCurrentItemFollowsToTarget() {
        let (sut, cleanup) = makeSUT()
        defer { cleanup() }
        ["/tmp/a", "/tmp/b", "/tmp/c", "/tmp/d"].forEach { sut.addMedia(at: $0) }
        sut.setCurrentIndex(1) // "/tmp/b"

        sut.moveMedia(from: 1, to: 3)

        #expect(sut.currentIndex == 3)
        #expect(sut.getCurrentPath() == "/tmp/b")
    }

    @Test func moveFromBeforeToAfterCurrentDecrementsIndex() {
        let (sut, cleanup) = makeSUT()
        defer { cleanup() }
        ["/tmp/a", "/tmp/b", "/tmp/c", "/tmp/d"].forEach { sut.addMedia(at: $0) }
        sut.setCurrentIndex(2) // "/tmp/c"

        sut.moveMedia(from: 0, to: 2)

        #expect(sut.currentIndex == 1)
        #expect(sut.getCurrentPath() == "/tmp/c")
    }

    @Test func moveFromAfterToBeforeCurrentIncrementsIndex() {
        let (sut, cleanup) = makeSUT()
        defer { cleanup() }
        ["/tmp/a", "/tmp/b", "/tmp/c", "/tmp/d"].forEach { sut.addMedia(at: $0) }
        sut.setCurrentIndex(1) // "/tmp/b"

        sut.moveMedia(from: 3, to: 0)

        #expect(sut.currentIndex == 2)
        #expect(sut.getCurrentPath() == "/tmp/b")
    }

    // MARK: - Navigation & bounds

    @Test func navigationRespectsBounds() {
        let (sut, cleanup) = makeSUT()
        defer { cleanup() }
        ["/tmp/a", "/tmp/b"].forEach { sut.addMedia(at: $0) }

        #expect(sut.previousIndex() == false) // already at 0
        #expect(sut.nextIndex() == true)
        #expect(sut.currentIndex == 1)
        #expect(sut.nextIndex() == false) // already at last
        #expect(sut.currentIndex == 1)
    }

    @Test func setCurrentIndexRejectsOutOfBounds() {
        let (sut, cleanup) = makeSUT()
        defer { cleanup() }
        sut.addMedia(at: "/tmp/a")

        sut.setCurrentIndex(5)
        #expect(sut.currentIndex == 0)
        sut.setCurrentIndex(-1)
        #expect(sut.currentIndex == 0)
    }

    // MARK: - Persistence

    @Test func persistsPathsAndIndexAcrossInstances() {
        let suiteName = "MediaDataSourceTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let files = makeTempFiles(3)
        defer { deleteTempFiles(files) }

        let first = MediaDataSource(defaults: defaults)
        files.forEach { first.addMedia(at: $0) }
        first.setCurrentIndex(2)

        let second = MediaDataSource(defaults: defaults)
        #expect(second.mediaPaths == files)
        #expect(second.currentIndex == 2)
    }

    @Test func loadDropsMissingFiles() {
        let suiteName = "MediaDataSourceTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let files = makeTempFiles(2)
        // Persist one real file plus one that does not exist on disk.
        defaults.set([files[0], "/tmp/definitely-missing-\(UUID().uuidString).jpg"],
                     forKey: "EclipseTV.recentImagesKey")
        defer { deleteTempFiles(files) }

        let sut = MediaDataSource(defaults: defaults)
        #expect(sut.mediaPaths == [files[0]])
    }

    @Test func loadRemapsMovedMediaDirectory() {
        let suiteName = "MediaDataSourceTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        // Place a file in the *current* media directory, then persist a stale path that
        // references the same filename under an old (now-missing) directory.
        let mediaDir = ImageStorage.shared.getImagesDirectory()
        let fileName = "remap_\(UUID().uuidString).jpg"
        let realURL = mediaDir.appendingPathComponent(fileName)
        try? Data([0x00]).write(to: realURL)
        defer { try? FileManager.default.removeItem(at: realURL) }

        let stalePath = "/old/caches/Media/\(fileName)"
        defaults.set([stalePath], forKey: "EclipseTV.recentImagesKey")

        let sut = MediaDataSource(defaults: defaults)
        #expect(sut.mediaPaths == [realURL.path])
    }
}
