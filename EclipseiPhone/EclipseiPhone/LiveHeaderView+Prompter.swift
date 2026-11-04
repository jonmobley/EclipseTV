//
//  LiveHeaderView+Prompter.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import UIKit

/// Three script lines for the hero: the one on the reading guide, bright, with its
/// neighbours dimmed above and below.
final class PrompterHeroLinesView: UIView {

    /// Wrapped-line ordinal currently shown, so ticks repaint only on a change.
    private(set) var lineIndex = -1

    private let eyebrow = UILabel()
    private let labels = [UILabel(), UILabel(), UILabel()]
    private let stack = UIStackView()

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        eyebrow.text = "PROMPTER"
        eyebrow.font = .systemFont(ofSize: 11, weight: .bold)
        eyebrow.textColor = UIColor.white.withAlphaComponent(0.55)
        eyebrow.textAlignment = .center
        for (index, label) in labels.enumerated() {
            label.textAlignment = .center
            label.numberOfLines = 1
            label.lineBreakMode = .byTruncatingTail
            label.adjustsFontSizeToFitWidth = true
            label.minimumScaleFactor = 0.7
            let isCurrent = index == 1
            label.font = .systemFont(ofSize: isCurrent ? 20 : 15, weight: isCurrent ? .semibold : .regular)
            label.textColor = isCurrent ? .white : UIColor.white.withAlphaComponent(0.45)
        }
        stack.axis = .vertical
        stack.alignment = .fill
        stack.spacing = 4
        stack.translatesAutoresizingMaskIntoConstraints = false
        [eyebrow] .forEach(stack.addArrangedSubview)
        labels.forEach(stack.addArrangedSubview)
        stack.setCustomSpacing(10, after: eyebrow)
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.centerYAnchor.constraint(equalTo: centerYAnchor),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16)
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// Shows `lines` with the one at `currentIndex` in the middle slot.
    func apply(lines: [String], currentIndex: Int, lineIndex: Int, isPlaying: Bool) {
        self.lineIndex = lineIndex
        let previous = currentIndex > 0 ? lines[currentIndex - 1] : ""
        let current = lines.indices.contains(currentIndex) ? lines[currentIndex] : ""
        let next = currentIndex + 1 < lines.count ? lines[currentIndex + 1] : ""
        labels[0].text = previous
        labels[1].text = current
        labels[2].text = next
        eyebrow.text = isPlaying ? "PROMPTER" : "PROMPTER · PAUSED"
    }

    var currentLine: String { labels[1].text ?? "" }
}

// MARK: - Prompter Hero

extension LiveHeaderView {

    /// Hero for a live Prompter: the current line and its neighbours on black.
    ///
    /// Uses a stable content key so per-line updates do not crossfade the hero.
    func configurePrompterLive(lines: [String], currentIndex: Int, lineIndex: Int, isPlaying: Bool) {
        let showLiveBadge = LiveOutputRouting.showsHeroLiveBadge()
        applyContent(key: "overlay:prompter") {
            self.clearWebPreview(parking: true)
            self.clearScreensaverPreview()
            self.clearCameraPreview()
            self.clearLibraryVideoPreview()
            self.hideCountdownClock()
            self.backgroundColor = .black
            self.imageView.image = nil
            self.imageView.isHidden = true
            self.placeholderIcon.isHidden = true
            self.titleLabel.isHidden = true
            self.subtitleLabel.isHidden = true

            self.wantsPlaybackControls = false
            self.resetTapAffordances()
            self.gradientLayer.isHidden = true
            self.liveBadge.isHidden = !showLiveBadge
            self.controls.isHidden = true
            self.updatePlayback(PlaybackState())

            self.installPrompterLinesIfNeeded()
            self.prompterLinesView.isHidden = false
            self.prompterLinesView.apply(
                lines: lines, currentIndex: currentIndex, lineIndex: lineIndex, isPlaying: isPlaying
            )
            self.bringSubviewToFront(self.prompterLinesView)
            self.bringSubviewToFront(self.liveBadge)
            // The expand button reopens the operator view.
            self.allowsOverlayControllerTap = true
            self.applyCollapseChrome()
            let line = self.prompterLinesView.currentLine
            self.accessibilityLabel = line.isEmpty ? "Prompter, live" : "Prompter, \(line)"
        }
    }

    /// Updates the lines during ticks without rebuilding hero chrome.
    func applyPrompterLines(_ lines: [String], currentIndex: Int, lineIndex: Int, isPlaying: Bool) {
        guard !prompterLinesView.isHidden else { return }
        prompterLinesView.apply(lines: lines, currentIndex: currentIndex, lineIndex: lineIndex, isPlaying: isPlaying)
    }

    /// Hides the prompter lines so they cannot leak onto other content.
    func hidePrompterLines() {
        prompterLinesView.isHidden = true
    }

    private func installPrompterLinesIfNeeded() {
        guard prompterLinesView.superview == nil else { return }
        prompterLinesView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(prompterLinesView)
        NSLayoutConstraint.activate([
            prompterLinesView.topAnchor.constraint(equalTo: topAnchor),
            prompterLinesView.bottomAnchor.constraint(equalTo: bottomAnchor),
            prompterLinesView.leadingAnchor.constraint(equalTo: leadingAnchor),
            prompterLinesView.trailingAnchor.constraint(equalTo: trailingAnchor)
        ])
    }
}
