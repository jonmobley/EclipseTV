//
//  ExportFileName.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import Foundation

/// Path-safe display names and zero-padded order prefixes for Show export.
enum ExportFileName {

    /// Soft cap so long titles still fit common Files / ZIP path limits.
    static let maxBaseLength = 80

    /// Strips characters that break paths; collapses whitespace; clamps length.
    ///
    /// Returns `Untitled` when nothing usable remains.
    static func sanitize(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "Untitled" }

        var scaled = ""
        scaled.reserveCapacity(min(trimmed.count, maxBaseLength))
        var lastWasSpace = false
        for scalar in trimmed.unicodeScalars {
            let isForbidden = Self.forbidden.contains(scalar)
                || scalar.value < 32
                || scalar.value == 127
            if isForbidden {
                if !lastWasSpace {
                    scaled.append("_")
                    lastWasSpace = true
                }
                continue
            }
            if scalar == " " {
                if !lastWasSpace {
                    scaled.append(" ")
                    lastWasSpace = true
                }
                continue
            }
            scaled.append(Character(scalar))
            lastWasSpace = false
        }

        var cleaned = scaled.trimmingCharacters(in: .whitespacesAndNewlines)
        // Forbidden edge chars become `_`; strip those and leftover dots so
        // `"A/B?"` → `A_B`, not `A_B_`.
        let edgeJunk = CharacterSet(charactersIn: "._")
            .union(.whitespacesAndNewlines)
        cleaned = cleaned.trimmingCharacters(in: edgeJunk)
        while cleaned.hasPrefix(".") {
            cleaned.removeFirst()
        }
        while cleaned.hasSuffix(".") {
            cleaned.removeLast()
            cleaned = cleaned.trimmingCharacters(in: edgeJunk)
        }
        if cleaned.isEmpty { return "Untitled" }
        if cleaned.count > maxBaseLength {
            cleaned = String(cleaned.prefix(maxBaseLength))
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return cleaned.isEmpty ? "Untitled" : cleaned
    }

    /// `01 Title` / `12 Title` with width from `totalCount` (at least 2 digits).
    static func numbered(_ title: String, index: Int, totalCount: Int) -> String {
        let width = max(2, String(max(totalCount, 1)).count)
        let prefix = String(format: "%0\(width)d", index)
        return "\(prefix) \(sanitize(title))"
    }

    /// Joins a sanitized base name with a filesystem-safe extension.
    static func fileName(base: String, pathExtension: String) -> String {
        let ext = pathExtension
            .trimmingCharacters(in: CharacterSet(charactersIn: "."))
            .lowercased()
            .filter { $0.isLetter || $0.isNumber }
        guard !ext.isEmpty else { return sanitize(base) }
        return "\(sanitize(base)).\(ext)"
    }

    // MARK: - Private

    private static let forbidden = CharacterSet(charactersIn: "/\\:*?\"<>|")
}
