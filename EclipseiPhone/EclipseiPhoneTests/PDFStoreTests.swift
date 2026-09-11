//
//  PDFStoreTests.swift
//  EclipseiPhoneTests
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//
//  Saved PDFs had no rename path: the title came from the file name at import and
//  could never change. These pin the store side of Rename — trimming, the blank
//  rejection, persistence across a reload — and the import-title fallbacks it shares.
//

import Foundation
import Testing
@testable import EclipseiPhone

@MainActor
struct PDFStoreTests {

    /// A throwaway defaults suite and scratch directory per test.
    private struct Scratch {
        let defaults: UserDefaults
        let root: URL
        let suite: String

        func cleanUp() {
            defaults.removePersistentDomain(forName: suite)
            try? FileManager.default.removeItem(at: root)
        }
    }

    private func makeScratch() throws -> Scratch {
        let suite = "PDFStoreTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(suite, isDirectory: true)
        return Scratch(defaults: defaults, root: root, suite: suite)
    }

    /// The store never parses the bytes on add, so any file stands in for a PDF.
    ///
    /// Uniqueness lives in the enclosing directory rather than the file name, because
    /// `add` derives the import title from the name — a prefix would land in the title.
    private func writeSourceFile(named name: String) throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(
            at: directory, withIntermediateDirectories: true
        )
        let url = directory.appendingPathComponent(name)
        try Data("not really a pdf".utf8).write(to: url)
        return url
    }

    @Test func renamePersistsTrimmedTitle() throws {
        let scratch = try makeScratch()
        defer { scratch.cleanUp() }
        let store = PDFStore(defaults: scratch.defaults, rootDirectory: scratch.root)
        let doc = try store.add(from: try writeSourceFile(named: "Deck.pdf"), title: nil)

        try store.rename(id: doc.id, to: "  Q3 Deck \n")

        #expect(store.documents.first?.title == "Q3 Deck")

        // A fresh store reading the same defaults sees the rename, not the import title.
        let reloaded = PDFStore(defaults: scratch.defaults, rootDirectory: scratch.root)
        #expect(reloaded.documents.first?.title == "Q3 Deck")
    }

    @Test func renameRejectsBlankTitle() throws {
        let scratch = try makeScratch()
        defer { scratch.cleanUp() }
        let store = PDFStore(defaults: scratch.defaults, rootDirectory: scratch.root)
        let doc = try store.add(from: try writeSourceFile(named: "Deck.pdf"), title: nil)

        #expect(throws: PDFStore.StoreError.self) {
            try store.rename(id: doc.id, to: "   ")
        }
        #expect(store.documents.first?.title == "Deck")
    }

    @Test func renameLeavesTheFileInPlace() throws {
        let scratch = try makeScratch()
        defer { scratch.cleanUp() }
        let store = PDFStore(defaults: scratch.defaults, rootDirectory: scratch.root)
        let doc = try store.add(from: try writeSourceFile(named: "Deck.pdf"), title: nil)
        let before = store.fileURL(for: doc.id)

        try store.rename(id: doc.id, to: "Renamed")

        #expect(before != nil)
        #expect(store.fileURL(for: doc.id) == before)
    }

    @Test func renameOfUnknownIdIsANoOp() throws {
        let scratch = try makeScratch()
        defer { scratch.cleanUp() }
        let store = PDFStore(defaults: scratch.defaults, rootDirectory: scratch.root)
        try store.add(from: try writeSourceFile(named: "Deck.pdf"), title: nil)

        try store.rename(id: UUID(), to: "Elsewhere")

        #expect(store.documents.map(\.title) == ["Deck"])
    }

    @Test func importTitleFallsBackToFileNameAndIsClamped() throws {
        let scratch = try makeScratch()
        defer { scratch.cleanUp() }
        let store = PDFStore(defaults: scratch.defaults, rootDirectory: scratch.root)
        let long = String(repeating: "x", count: UserDisplayName.maxLength + 20)

        let fromName = try store.add(
            from: try writeSourceFile(named: "\(long).pdf"), title: "  "
        )
        let explicit = try store.add(
            from: try writeSourceFile(named: "Ignored.pdf"), title: " Agenda "
        )

        #expect(fromName.title.count == UserDisplayName.maxLength)
        #expect(explicit.title == "Agenda")
    }
}
