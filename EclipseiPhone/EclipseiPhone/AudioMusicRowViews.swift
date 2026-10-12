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

    /// Right-aligned duration for track rows (actions are on press-and-hold).
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
}
