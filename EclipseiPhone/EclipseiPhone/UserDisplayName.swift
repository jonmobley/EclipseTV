//
//  UserDisplayName.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import UIKit

/// Shared limits for user-typed Show / playlist / track / website titles.
enum UserDisplayName {

    /// Soft cap that fits the home header pill without crowding trailing chrome.
    static let maxLength = 48

    /// Trims whitespace; returns `nil` when empty. Clamps to `maxLength`.
    static func normalized(_ raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return clamp(trimmed)
    }

    /// Clamps an already-meaningful title (filename / host fallback).
    static func clamp(_ raw: String) -> String {
        guard raw.count > maxLength else { return raw }
        return String(raw.prefix(maxLength))
    }

    /// Caps typing and paste length for name/title alert fields.
    static func configureTextField(_ field: UITextField) {
        field.addTarget(
            TextFieldMaxLengthBridge.shared,
            action: #selector(TextFieldMaxLengthBridge.editingChanged(_:)),
            for: .editingChanged
        )
    }
}

// MARK: - Text field bridge

private final class TextFieldMaxLengthBridge: NSObject {
    static let shared = TextFieldMaxLengthBridge()

    @objc func editingChanged(_ field: UITextField) {
        guard let text = field.text, text.count > UserDisplayName.maxLength else { return }
        field.text = String(text.prefix(UserDisplayName.maxLength))
    }
}
