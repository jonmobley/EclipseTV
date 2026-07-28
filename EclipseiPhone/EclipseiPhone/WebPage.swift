//
//  WebPage.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import Foundation

/// A saved page the user can present full-bleed on an AirPlay display.
struct WebPage: Codable, Equatable, Identifiable, Hashable {
    let id: UUID
    var title: String
    var url: URL
    let createdAt: Date

    /// Stable id for the home-grid free browser (not a saved bookmark).
    static let freeBrowseId = UUID(uuidString: "00000000-0000-4000-8000-0000000000EB")!

    /// Ephemeral session for the home Website tile.
    static var freeBrowse: WebPage {
        WebPage(
            id: freeBrowseId,
            title: "Website",
            url: URL(string: "about:blank")!
        )
    }

    /// Whether this page is the home free-browser session.
    var isFreeBrowse: Bool { id == Self.freeBrowseId }

    /// Creates a new saved page.
    init(id: UUID = UUID(), title: String, url: URL, createdAt: Date = Date()) {
        self.id = id
        self.title = title
        self.url = url
        self.createdAt = createdAt
    }
}
