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

    /// Creates a new saved page.
    init(id: UUID = UUID(), title: String, url: URL, createdAt: Date = Date()) {
        self.id = id
        self.title = title
        self.url = url
        self.createdAt = createdAt
    }

    /// YouTube / Vimeo / direct-file video when the URL should play fullscreen.
    ///
    /// Derived at use time from `url` — never stored — so CloudKit and History
    /// keep a single page shape.
    var videoLink: WebVideoLink? { WebVideoLink(url: url) }
}
