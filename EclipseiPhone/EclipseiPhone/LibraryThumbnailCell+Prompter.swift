//
//  LibraryThumbnailCell+Prompter.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import UIKit

// MARK: - Prompter Tile

extension LibraryThumbnailCell {

    static let prompterPlaceholderCaption = "Tap to write your script"

    /// Show-grid Prompter tile: the script's first line under the title, or a nudge
    /// to write one; the live stroke while the script is on output.
    func configurePrompter(
        excerpt: String?,
        isLive: Bool,
        isLocked: Bool = false,
        isPlaying: Bool = false
    ) {
        configureSpecial(
            title: "Prompter",
            systemImage: "text.alignleft",
            thumbnail: nil,
            fillColor: .specialTile,
            isLive: isLive,
            isLocked: isLocked,
            titleNumberOfLines: 2,
            typeIcon: .prompter
        )
        let detail = excerpt ?? Self.prompterPlaceholderCaption
        captionLabel.text = "Prompter\n\(detail)"
        captionLabel.numberOfLines = 2
        captionLabel.lineBreakMode = .byTruncatingTail
        updateCaptionScrim()

        var spoken = excerpt.map { "Prompter, \($0)" } ?? "Prompter, no script yet"
        if isLive { spoken += isPlaying ? ", live, scrolling" : ", live, paused" }
        if isLocked { spoken += ", locked" }
        accessibilityLabel = spoken
        isAccessibilityElement = true
    }

    /// First non-empty line of `script`, for the tile caption.
    static func prompterExcerpt(from script: String) -> String? {
        script
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .first { !$0.isEmpty }
    }
}
