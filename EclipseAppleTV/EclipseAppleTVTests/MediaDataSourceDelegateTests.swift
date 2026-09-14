//
//  MediaDataSourceDelegateTests.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import Testing
import Foundation
@testable import EclipseAppleTV

/// Pins which delegate callback each mutation is allowed to send.
///
/// `addMedia`, `removeMedia`, and `moveMedia` drive a batch update on the grid. Sending
/// `mediaDataDidChange()` as well queues a full `reloadData()` behind that animation,
/// which cancels it and re-runs the selection work the granular handler has just done.
/// Adding the extra call reads like harmless belt and braces, so the call sites carry a
/// comment saying not to — these tests are what makes removing the comment fail.
///
/// Each test asserts the whole recorded sequence rather than a count, because the bug
/// being guarded against is an *additional* callback next to the correct one.
struct MediaDataSourceDelegateTests {

    // MARK: - Spy

    private final class DelegateSpy: MediaDataSourceDelegate {
        enum Event: Equatable {
            case reloadAll
            case added(index: Int)
            case removed(index: Int)
            case moved(from: Int, to: Int)
        }

        private(set) var events: [Event] = []

        func mediaDataDidChange() {
            events.append(.reloadAll)
        }

        func mediaData(_ dataSource: MediaDataSource, didAddItemAt index: Int) {
            events.append(.added(index: index))
        }

        func mediaData(_ dataSource: MediaDataSource, didRemoveItemAt index: Int) {
            events.append(.removed(index: index))
        }

        func mediaData(
            _ dataSource: MediaDataSource,
            didMoveItemFrom sourceIndex: Int,
            to targetIndex: Int
        ) {
            events.append(.moved(from: sourceIndex, to: targetIndex))
        }
    }

    // MARK: - Helpers

    /// A data source on an isolated `UserDefaults` suite, so tests never touch
    /// `.standard`. The returned closure removes the suite.
    private func makeSUT() -> (sut: MediaDataSource, cleanup: () -> Void) {
        let suiteName = "MediaDataSourceDelegateTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        let sut = MediaDataSource(defaults: defaults)
        return (sut, { defaults.removePersistentDomain(forName: suiteName) })
    }

    /// Attaches a spy after seeding, so setup never shows up in the recorded events.
    ///
    /// `MediaDataSource.delegate` is weak; the caller holds the returned spy.
    private func watch(_ sut: MediaDataSource) -> DelegateSpy {
        let spy = DelegateSpy()
        sut.delegate = spy
        return spy
    }

    /// Paths outside the media root and with a still's extension, so removal touches
    /// neither `ImageStorage` nor `VideoThumbnailCache`.
    private let paths = ["/tmp/a.jpg", "/tmp/b.jpg", "/tmp/c.jpg"]

    // MARK: - Granular mutations send one callback each

    @Test func addSendsOnlyTheInsert() {
        let (sut, cleanup) = makeSUT()
        defer { cleanup() }
        let spy = watch(sut)

        sut.addMedia(at: paths[0])

        #expect(spy.events == [.added(index: 0)])
    }

    @Test func removeSendsOnlyTheDelete() {
        let (sut, cleanup) = makeSUT()
        defer { cleanup() }
        paths.forEach { sut.addMedia(at: $0) }
        let spy = watch(sut)

        sut.removeMedia(at: 1)

        #expect(spy.events == [.removed(index: 1)])
    }

    @Test func moveSendsOnlyTheMove() {
        let (sut, cleanup) = makeSUT()
        defer { cleanup() }
        paths.forEach { sut.addMedia(at: $0) }
        let spy = watch(sut)

        sut.moveMedia(from: 0, to: 2)

        #expect(spy.events == [.moved(from: 0, to: 2)])
    }

    // MARK: - Rejected mutations stay silent

    @Test func addingAPathAlreadyPresentSendsNothing() {
        let (sut, cleanup) = makeSUT()
        defer { cleanup() }
        sut.addMedia(at: paths[0])
        let spy = watch(sut)

        sut.addMedia(at: paths[0])

        #expect(spy.events.isEmpty)
        #expect(sut.count == 1)
    }

    @Test func removingOutOfRangeSendsNothing() {
        let (sut, cleanup) = makeSUT()
        defer { cleanup() }
        paths.forEach { sut.addMedia(at: $0) }
        let spy = watch(sut)

        sut.removeMedia(at: 99)
        sut.removeMedia(at: -1)

        #expect(spy.events.isEmpty)
        #expect(sut.count == 3)
    }

    @Test func movingAnItemOntoItselfSendsNothing() {
        let (sut, cleanup) = makeSUT()
        defer { cleanup() }
        paths.forEach { sut.addMedia(at: $0) }
        let spy = watch(sut)

        sut.moveMedia(from: 1, to: 1)

        #expect(spy.events.isEmpty)
    }

    // MARK: - Whole-list changes ask for one reload

    /// The asymmetry is deliberate: a batch has no single index to animate, so it is the
    /// one append that should reload instead of inserting.
    @Test func batchAddAsksForOneReload() {
        let (sut, cleanup) = makeSUT()
        defer { cleanup() }
        let spy = watch(sut)

        sut.addMediaBatch(paths: paths)

        #expect(spy.events == [.reloadAll])
        #expect(sut.count == 3)
    }

    @Test func batchAddWithNothingNewSendsNothing() {
        let (sut, cleanup) = makeSUT()
        defer { cleanup() }
        paths.forEach { sut.addMedia(at: $0) }
        let spy = watch(sut)

        sut.addMediaBatch(paths: paths)

        #expect(spy.events.isEmpty)
    }

    @Test func switchingLibraryModeAsksForOneReload() {
        let (sut, cleanup) = makeSUT()
        defer { cleanup() }
        let spy = watch(sut)

        sut.setActiveLibraryMode(.vertical)

        #expect(spy.events == [.reloadAll])
    }

    @Test func switchingToTheModeAlreadyActiveSendsNothing() {
        let (sut, cleanup) = makeSUT()
        defer { cleanup() }
        let spy = watch(sut)

        sut.setActiveLibraryMode(sut.activeLibraryMode)

        #expect(spy.events.isEmpty)
    }
}
