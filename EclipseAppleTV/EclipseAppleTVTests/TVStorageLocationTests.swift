//
//  TVStorageLocationTests.swift
//  EclipseAppleTVTests
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import Testing
import Foundation
@testable import EclipseAppleTV

/// Pins where the Apple TV app keeps its data.
///
/// Caches is the reliable writable location on tvOS; an earlier move to Application
/// Support broke saving outright, and the fix was to move back. That history lives in a
/// comment in `ImageStorage` and in the repository's storage rule, but nothing failed
/// when the code drifted away from it — the breakage only showed up on a device, as
/// media that silently refused to save. These tests are the missing failure.
///
/// Relocating storage is a deliberate decision, not a cleanup. If one of these fails
/// because the move was intended, read the rule before updating the expectation.
@MainActor
struct TVStorageLocationTests {

    // MARK: - Helpers

    private var caches: URL {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
    }

    /// True when `url` is inside `directory`, comparing resolved paths so a symlinked
    /// container (`/var` → `/private/var` on a simulator) does not read as an escape.
    private func path(_ url: URL, isInside directory: URL) -> Bool {
        let child = resolved(url)
        let parent = resolved(directory)
        return child == parent || child.hasPrefix(parent + "/")
    }

    /// True when `url` sits directly in `directory` rather than deeper inside it.
    private func path(_ url: URL, isDirectlyIn directory: URL) -> Bool {
        resolved(url.deletingLastPathComponent()) == resolved(directory)
    }

    /// A path with no trailing separator, so directory URLs built with and without
    /// `isDirectory: true` compare equal.
    private func resolved(_ url: URL) -> String {
        URL(fileURLWithPath: url.path).resolvingSymlinksInPath().path
    }

    // MARK: - Library media

    @Test func mediaRootIsTheCachesMediaDirectory() {
        let root = ImageStorage.shared.getMediaRootDirectory()

        #expect(root.lastPathComponent == "Media")
        #expect(path(root, isInside: caches))
    }

    /// The specific regression: Application Support is the plausible-looking home for
    /// user media, and it is the one that broke saving.
    ///
    /// Library itself is not checked — Caches sits inside it.
    @Test func mediaRootIsNotInTheLocationThatBrokeSaving() {
        let root = ImageStorage.shared.getMediaRootDirectory()
        let fileManager = FileManager.default

        for domain: FileManager.SearchPathDirectory in [.applicationSupportDirectory,
                                                        .documentDirectory] {
            guard let url = fileManager.urls(for: domain, in: .userDomainMask).first else {
                continue
            }
            #expect(!path(root, isInside: url))
        }
    }

    @Test func eachLibraryModeGetsItsOwnSubdirectoryOfTheRoot() {
        let root = ImageStorage.shared.getMediaRootDirectory()

        for mode in EclipseShareProtocol.LibraryMode.allCases {
            let directory = ImageStorage.shared.getImagesDirectory(for: mode)
            #expect(directory.lastPathComponent == mode.directoryName)
            #expect(path(directory, isDirectlyIn: root))
        }

        let landscape = ImageStorage.shared.getImagesDirectory(for: .landscape)
        let vertical = ImageStorage.shared.getImagesDirectory(for: .vertical)
        #expect(landscape != vertical)
    }

    /// Both mode directories are created during initialisation, so a save never has to
    /// create one on a path where failure would be reported as a missing file.
    @Test func modeDirectoriesExistOnceTheStoreIsInitialised() {
        for mode in EclipseShareProtocol.LibraryMode.allCases {
            let directory = ImageStorage.shared.getImagesDirectory(for: mode)
            var isDirectory: ObjCBool = false
            let exists = FileManager.default.fileExists(
                atPath: directory.path,
                isDirectory: &isDirectory
            )
            #expect(exists)
            #expect(isDirectory.boolValue)
        }
    }

    // MARK: - Album media

    @Test func albumRootIsTheCachesAlbumDirectory() {
        #expect(AlbumStorage.directory.lastPathComponent == "Album")
        #expect(path(AlbumStorage.directory, isInside: caches))
    }

    /// Kept out of `Caches/Media` so downloaded album files never mix with the items the
    /// iPhone sent, which are subject to the local library's delete-on-remove logic.
    @Test func albumFilesAreKeptOutOfTheLocalLibrary() {
        let media = ImageStorage.shared.getMediaRootDirectory()

        #expect(!path(AlbumStorage.directory, isInside: media))
        #expect(!path(media, isInside: AlbumStorage.directory))
    }

    @Test func eachAlbumGetsItsOwnSubdirectory() {
        let first = AlbumStorage.directory(forAlbumId: "spring")
        let second = AlbumStorage.directory(forAlbumId: "summer")

        #expect(path(first, isDirectlyIn: AlbumStorage.directory))
        #expect(path(second, isDirectlyIn: AlbumStorage.directory))
        #expect(first != second)
    }

    @Test func albumFilePathsSitInsideTheirOwnAlbumDirectory() {
        let directory = AlbumStorage.directory(forAlbumId: "spring")
        let file = AlbumStorage.path(forAlbumId: "spring", fileName: "sunrise.jpg")

        #expect(file == directory.appendingPathComponent("sunrise.jpg").path)
        #expect(path(URL(fileURLWithPath: file), isInside: directory))
    }

    /// Album ids arrive from a server manifest, so they are untrusted input. Sanitising
    /// keeps one album to one directory: an id carrying a separator must not be able to
    /// nest a directory or climb out of the album root.
    @Test func albumIdsCannotIntroduceAPathSeparator() {
        for id in ["a/b", "a\\b", "../secret", "with: colon", "star*"] {
            let directory = AlbumStorage.directory(forAlbumId: id)

            #expect(!AlbumStorage.sanitize(id).contains("/"))
            #expect(!AlbumStorage.sanitize(id).contains("\\"))
            #expect(path(directory, isDirectlyIn: AlbumStorage.directory))
        }
    }

    // MARK: - Album metadata

    /// The literal key strings here are the point: `RemoteAlbumStore` reads them from
    /// `UserDefaults`, and these tests fail if the keys are renamed or the metadata is
    /// moved to another store, either of which strands what a shipped build persisted.
    private static let albumsKey = "EclipseTV.album.albums"
    private static let lastSyncKey = "EclipseTV.album.lastSync"

    /// A store over an isolated suite, never `.standard`. The returned closure removes
    /// the suite.
    private func makeIsolatedDefaults() -> (defaults: UserDefaults, cleanup: () -> Void) {
        let suiteName = "TVStorageLocationTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        return (defaults, { defaults.removePersistentDomain(forName: suiteName) })
    }

    private func encoded(_ albums: [Album]) -> Data {
        try! JSONEncoder().encode(albums)
    }

    private func item(albumId: String, fileName: String) -> AlbumItem {
        AlbumItem(
            id: "\(albumId)-\(fileName)",
            albumId: albumId,
            name: fileName,
            isVideo: false,
            remoteURL: "https://example.invalid/\(fileName)",
            checksum: nil,
            localFileName: fileName,
            thumbnailFileName: nil
        )
    }

    @Test func albumsAndLastSyncRestoreFromTheDocumentedKeys() {
        let (defaults, cleanup) = makeIsolatedDefaults()
        defer { cleanup() }
        let album = Album(id: "spring", name: "Spring", items: [])
        let synced = Date(timeIntervalSince1970: 1_700_000_000)
        defaults.set(encoded([album]), forKey: Self.albumsKey)
        defaults.set(synced, forKey: Self.lastSyncKey)

        let store = RemoteAlbumStore(defaults: defaults)

        #expect(store.albums == [album])
        #expect(store.lastSyncDate == synced)
    }

    /// tvOS purges Caches under storage pressure, so a persisted item whose file is gone
    /// is an expected state, not corruption: it is dropped on load and the next sync
    /// downloads it again. Treating it as a failure — or keeping it and letting the grid
    /// show an item that cannot open — is the regression this guards.
    @Test func purgedAlbumFilesAreDroppedOnLoadRatherThanFailingTheRead() throws {
        let (defaults, cleanup) = makeIsolatedDefaults()
        defer { cleanup() }

        // A directory of this test's own, so nothing the host app downloaded is touched.
        let albumId = "purge-test-\(UUID().uuidString)"
        let directory = AlbumStorage.directory(forAlbumId: albumId)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let present = item(albumId: albumId, fileName: "present.jpg")
        try Data([0xFF]).write(to: URL(fileURLWithPath: present.localPath))

        let purged = item(albumId: albumId, fileName: "purged.jpg")
        let album = Album(id: albumId, name: "Trip", items: [present, purged])
        defaults.set(encoded([album]), forKey: Self.albumsKey)

        let store = RemoteAlbumStore(defaults: defaults)

        #expect(store.albums.count == 1)
        #expect(store.albums.first?.id == albumId)
        #expect(store.albums.first?.items == [present])

        // The pruned list is written back, so the drop survives a relaunch.
        let reread = try #require(defaults.data(forKey: Self.albumsKey))
        let decoded = try JSONDecoder().decode([Album].self, from: reread)
        #expect(decoded.first?.items == [present])
    }

    @Test func anAlbumWhoseFilesAreAllPurgedSurvivesAsAnEmptyAlbum() {
        let (defaults, cleanup) = makeIsolatedDefaults()
        defer { cleanup() }
        let albumId = "purge-test-\(UUID().uuidString)"
        let album = Album(
            id: albumId,
            name: "Trip",
            items: [item(albumId: albumId, fileName: "gone.jpg")]
        )
        defaults.set(encoded([album]), forKey: Self.albumsKey)

        let store = RemoteAlbumStore(defaults: defaults)

        #expect(store.albums.count == 1)
        #expect(store.albums.first?.items.isEmpty == true)
    }

    /// Undecodable metadata starts the store empty and leaves the stored bytes alone.
    /// Writing an empty list over them would turn a decode bug into the permanent loss
    /// of a synced library, and the next sync restores the albums anyway.
    @Test func anUnreadableAlbumBlobLeavesTheStoreEmptyAndTheBytesIntact() {
        let (defaults, cleanup) = makeIsolatedDefaults()
        defer { cleanup() }
        let blob = Data("not json".utf8)
        defaults.set(blob, forKey: Self.albumsKey)

        let store = RemoteAlbumStore(defaults: defaults)

        #expect(store.albums.isEmpty)
        #expect(defaults.data(forKey: Self.albumsKey) == blob)
    }
}
