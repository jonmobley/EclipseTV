//
//  AudioMusicRowViews.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import UIKit

/// Trailing accessories for compact Music list rows (count / duration / ⋯).
enum AudioMusicRowViews {

    /// Formats a track length as `m:ss`, or empty when unknown.
    static func formatDuration(_ seconds: TimeInterval) -> String {
        guard seconds.isFinite, seconds > 0 else { return "" }
        let total = Int(seconds.rounded())
        let m = total / 60
        let s = total % 60
        return String(format: "%d:%02d", m, s)
    }

    /// Right-aligned song count plus disclosure chevron for playlist rows.
    static func playlistAccessory(songCount: Int) -> UIView {
        let label = metaLabel()
        label.text = songCount == 1 ? "1 song" : "\(songCount) songs"
        let chevron = UIImageView(
            image: UIImage(systemName: "chevron.right")
        )
        chevron.tintColor = .tertiaryLabel
        chevron.preferredSymbolConfiguration = UIImage.SymbolConfiguration(
            pointSize: 13, weight: .semibold
        )
        chevron.setContentHuggingPriority(.required, for: .horizontal)
        let stack = UIStackView(arrangedSubviews: [label, chevron])
        stack.axis = .horizontal
        stack.alignment = .center
        stack.spacing = 6
        return sizedAccessory(stack)
    }

    /// Right-aligned duration plus a ⋯ menu button for track rows.
    static func trackAccessory(duration: TimeInterval, menu: UIMenu) -> UIView {
        let label = metaLabel()
        label.text = formatDuration(duration)
        label.isHidden = label.text?.isEmpty == true

        let more = moreButton(menu: menu)
        let stack = UIStackView(arrangedSubviews: [label, more])
        stack.axis = .horizontal
        stack.alignment = .center
        stack.spacing = 4
        return sizedAccessory(stack)
    }

    /// Duration only (used while arranging, when the ⋯ is hidden).
    static func durationAccessory(duration: TimeInterval) -> UIView? {
        let text = formatDuration(duration)
        guard !text.isEmpty else { return nil }
        let label = metaLabel()
        label.text = text
        return sizedAccessory(label)
    }

    private static func sizedAccessory(_ view: UIView) -> UIView {
        let size = view.systemLayoutSizeFitting(UIView.layoutFittingCompressedSize)
        view.bounds = CGRect(origin: .zero, size: size)
        return view
    }

    // MARK: - Private

    private static func metaLabel() -> UILabel {
        let label = UILabel()
        label.font = .preferredFont(forTextStyle: .subheadline)
        label.textColor = .secondaryLabel
        label.textAlignment = .right
        label.setContentHuggingPriority(.required, for: .horizontal)
        label.setContentCompressionResistancePriority(.required, for: .horizontal)
        return label
    }

    private static func moreButton(menu: UIMenu) -> UIButton {
        var config = UIButton.Configuration.plain()
        config.image = UIImage(
            systemName: "ellipsis",
            withConfiguration: UIImage.SymbolConfiguration(pointSize: 15, weight: .bold)
        )
        config.baseForegroundColor = .secondaryLabel
        config.contentInsets = NSDirectionalEdgeInsets(
            top: 8, leading: 8, bottom: 8, trailing: 4
        )
        let button = UIButton(configuration: config)
        button.menu = menu
        button.showsMenuAsPrimaryAction = true
        button.accessibilityLabel = "More"
        button.setContentHuggingPriority(.required, for: .horizontal)
        return button
    }
}
