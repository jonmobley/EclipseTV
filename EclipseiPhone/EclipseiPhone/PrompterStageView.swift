//
//  PrompterStageView.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import UIKit

/// The scrolling script on black, with a reading guide at the centre and fades top
/// and bottom. Used by the operator view and the output display alike; each sets its
/// own font and inset and follows the controller's reading anchor.
final class PrompterStageView: UIView {

    /// Called when the text area changes size (width, height of the text column).
    var onMetricsChange: ((CGSize) -> Void)?

    /// Side inset of the text column.
    var horizontalInset: CGFloat = 24 {
        didSet { if horizontalInset != oldValue { setNeedsLayout() } }
    }

    /// Widest the text column runs; `nil` for the full width.
    var maximumTextWidth: CGFloat?

    var showsReadingGuide = true {
        didSet { guideTop.isHidden = !showsReadingGuide; guideBottom.isHidden = !showsReadingGuide }
    }

    private(set) var font = PrompterStageMetrics.font(ofSize: 32)
    private(set) var script = ""
    private(set) var layout: PrompterTextLayout?
    private var lastAnchor: PrompterReadingAnchor = .start
    private var lastMetrics: CGSize = .zero

    let textView: UITextView = {
        let view = UITextView(usingTextLayoutManager: false)
        view.isEditable = false
        view.isSelectable = false
        view.isScrollEnabled = true
        view.isUserInteractionEnabled = false
        view.showsVerticalScrollIndicator = false
        view.showsHorizontalScrollIndicator = false
        view.contentInsetAdjustmentBehavior = .never
        view.backgroundColor = .black
        view.textContainer.lineFragmentPadding = 0
        view.layoutManager.allowsNonContiguousLayout = true
        view.isAccessibilityElement = true
        view.accessibilityTraits = .staticText
        return view
    }()

    private let topFade = CAGradientLayer()
    private let bottomFade = CAGradientLayer()
    private let guideTop = UIView()
    private let guideBottom = UIView()

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .black
        clipsToBounds = true
        addSubview(textView)
        for fade in [topFade, bottomFade] {
            fade.colors = [UIColor.black.cgColor, UIColor.black.withAlphaComponent(0).cgColor]
            layer.addSublayer(fade)
        }
        bottomFade.startPoint = CGPoint(x: 0.5, y: 1)
        bottomFade.endPoint = CGPoint(x: 0.5, y: 0)
        for guide in [guideTop, guideBottom] {
            guide.backgroundColor = UIColor.liveStroke.withAlphaComponent(0.4)
            guide.isUserInteractionEnabled = false
            addSubview(guide)
        }
        accessibilityLabel = "Prompter script"
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// Replaces the script text and re-centres on `anchor`.
    func setScript(_ script: String, anchor: PrompterReadingAnchor) {
        self.script = script
        rebuildText()
        apply(anchor: anchor)
    }

    /// Changes the text size and re-centres on the last anchor.
    func setFont(_ font: UIFont) {
        guard font != self.font else { return }
        self.font = font
        rebuildText()
        apply(anchor: lastAnchor)
    }

    /// Scrolls so the character at `anchor` sits on the reading guide.
    func apply(anchor: PrompterReadingAnchor) {
        lastAnchor = anchor
        guard let layout, bounds.height > 0 else { return }
        let y = layout.textY(for: anchor) - layout.lineHeight / 2
        let next = CGPoint(x: 0, y: y)
        if abs(textView.contentOffset.y - next.y) >= 0.25 {
            textView.contentOffset = next
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let lineHeight = PrompterStageMetrics.lineHeight(for: font)
        let topInset = PrompterStageMetrics.topInset(viewportHeight: bounds.height, lineHeight: lineHeight)
        let width = min(bounds.width - 2 * horizontalInset, maximumTextWidth ?? .greatestFiniteMagnitude)
        let side = max(horizontalInset, (bounds.width - max(1, width)) / 2)
        textView.frame = bounds
        textView.textContainerInset = UIEdgeInsets(top: topInset, left: side, bottom: topInset, right: side)

        let fadeHeight = bounds.height * PrompterStageMetrics.fadeFraction
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        topFade.frame = CGRect(x: 0, y: 0, width: bounds.width, height: fadeHeight)
        bottomFade.frame = CGRect(x: 0, y: bounds.height - fadeHeight, width: bounds.width, height: fadeHeight)
        CATransaction.commit()

        let guideY = bounds.midY
        guideTop.frame = CGRect(x: 0, y: guideY - lineHeight / 2 - 1, width: bounds.width, height: 2)
        guideBottom.frame = CGRect(x: 0, y: guideY + lineHeight / 2 - 1, width: bounds.width, height: 2)

        let metrics = CGSize(width: max(1, width), height: bounds.height)
        if metrics != lastMetrics {
            lastMetrics = metrics
            rebuildText()
            onMetricsChange?(metrics)
        }
        apply(anchor: lastAnchor)
    }

    private func rebuildText() {
        textView.attributedText = PrompterStageMetrics.attributedScript(script, font: font, color: .white)
        textView.layoutManager.ensureLayout(for: textView.textContainer)
        layout = PrompterTextLayout(
            storage: textView.textStorage,
            layoutManager: textView.layoutManager,
            container: textView.textContainer,
            font: font
        )
        textView.accessibilityValue = script
    }
}
