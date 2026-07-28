//
//  SavedPDF.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import Foundation

/// A PDF saved for AirPlay presentation (phone-only; not sent to the TV app).
struct SavedPDF: Codable, Equatable, Identifiable, Hashable {
    let id: UUID
    var title: String
    let createdAt: Date

    /// Creates a new saved PDF bookmark.
    init(id: UUID = UUID(), title: String, createdAt: Date = Date()) {
        self.id = id
        self.title = title
        self.createdAt = createdAt
    }
}
