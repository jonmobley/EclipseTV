//
//  SlideshowNaming.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import Foundation

/// Every slideshow has a name (tabs and the ribbon label it). A slideshow left
/// unnamed becomes "Slideshow 01", "Slideshow 02" and so on, numbered within
/// its Show. Same rule as Eclipse for Mac.
enum SlideshowNaming {

    /// Word before the number: "Slideshow 01".
    static let baseName = "Slideshow"

    /// Numbers are padded to at least this many digits.
    private static let minimumDigits = 2

    /// The next free numbered name, one above the highest "Slideshow NN" in use.
    static func nextName(existing: [String]) -> String {
        let highest = existing.compactMap(number(in:)).max() ?? 0
        let digits = String(highest + 1)
        let padding = String(repeating: "0", count: max(0, minimumDigits - digits.count))
        return "\(baseName) \(padding)\(digits)"
    }

    /// 7 from "Slideshow 07" or "Slideshow 7"; nil for any other name.
    private static func number(in name: String) -> Int? {
        let prefix = baseName + " "
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix(prefix) else { return nil }
        let digits = trimmed.dropFirst(prefix.count)
        guard !digits.isEmpty, digits.allSatisfy(\.isASCII), digits.allSatisfy(\.isNumber) else {
            return nil
        }
        return Int(digits)
    }
}
