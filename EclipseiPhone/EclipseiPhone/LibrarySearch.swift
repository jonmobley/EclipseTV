//
//  LibrarySearch.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import Foundation

/// Case- and diacritic-insensitive match for Media Library search.
enum LibrarySearch {

    /// True when `query` is blank, or any haystack contains it.
    static func matches(_ query: String, in haystacks: [String?]) -> Bool {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !needle.isEmpty else { return true }
        return haystacks.contains { hay in
            guard let hay, !hay.isEmpty else { return false }
            return hay.localizedStandardContains(needle)
        }
    }
}
