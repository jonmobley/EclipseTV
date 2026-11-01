//
//  ExpandableNoteCardView.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import UIKit

/// Scrolls an expanded note. A type of its own so Preview's drag-to-dismiss can
/// tell a drag through the note from a drag on the image.
final class NoteCardScrollView: UIScrollView {}

/// VoiceOver stand-in for the card body, so the card reads as one element and
/// the pencil can still be a separate one beside it.
private final class NoteCardBodyElement: UIAccessibilityElement {

    /// Runs on a VoiceOver double tap.
    var onActivate: (() -> Void)?

    override func accessibilityActivate() -> Bool {
        onActivate?()
        return true
    }
}

/// Presenter note that reads first and edits only on purpose.
///
/// A tap sends `.touchUpInside`, and the host decides what it means. The pencil
/// calls `onEdit`. Height belongs to the host, which pins what `height(forWidth:maxHeight:)`
/// returns; whatever doesn't fit in the pinned height scrolls inside the card.
class ExpandableNoteCardView: UIControl {

    /// Height and chrome change together over this long when a card toggles.
    static let toggleDuration: TimeInterval = 0.25

    private static let pencilHitSide: CGFloat = 44
    private static let pencilVisibleSide: CGFloat = 28
    /// Text column room for the pencil: its margin in the corner plus a small gap.
    private static let pencilReservedWidth: CGFloat = 40

    /// Asks the host to open the editor.
    var onEdit: (() -> Void)?

    /// Asks the host to relayout after a change the card can't see it needs,
    /// such as a new Dynamic Type size.
    var onMetricsChanged: (() -> Void)?

    /// Whether the whole note is showing rather than the collapsed lines.
    private(set) var isExpanded = false

    /// Lines shown while collapsed. Subclasses set their own.
    var collapsedLineCount: Int { 3 }

    /// Where a popover editor should point: the pencil, or the card when it has none.
    var editAnchor: UIView { pencilButton.isHidden ? self : pencilButton }

    /// False for the empty placeholder, which has nothing to expand.
    var hasNote: Bool { note != nil }

    let pencilButton = UIButton(type: .system)

    private let horizontalInset: CGFloat
    private let verticalInset: CGFloat
    private let scrollView = NoteCardScrollView()
    private let bodyLabel = UILabel()
    private lazy var bodyElement = NoteCardBodyElement(accessibilityContainer: self)
    private var note: String?
    private var displayText = ""
    private var displayColor = UIColor.label

    /// - Parameters:
    ///   - horizontalInset: Text inset from the card's sides.
    ///   - verticalInset: Text inset from the card's top and bottom.
    init(horizontalInset: CGFloat, verticalInset: CGFloat) {
        self.horizontalInset = horizontalInset
        self.verticalInset = verticalInset
        super.init(frame: .zero)
        setup()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// Shows `note`, or `placeholder` in `placeholderColor` with no pencil when nil.
    func fill(
        note: String?,
        textColor: UIColor,
        placeholder: String = "",
        placeholderColor: UIColor = .tertiaryLabel
    ) {
        self.note = note
        displayText = note ?? placeholder
        displayColor = note == nil ? placeholderColor : textColor
        pencilButton.isHidden = note == nil
        applyText()
        setNeedsLayout()
    }

    /// Sets the expanded state. The host resizes the card to match.
    func setExpanded(_ expanded: Bool) {
        guard expanded != isExpanded else { return }
        isExpanded = expanded
        scrollView.contentOffset = .zero
        setNeedsLayout()
        refreshAccessibility()
    }

    /// True when the note doesn't fit in the collapsed lines at `width`.
    func isTruncated(forWidth width: CGFloat) -> Bool {
        let textWidth = textWidth(forWidth: width)
        guard textWidth > 0, hasNote, let text = bodyLabel.attributedText else {
            return false
        }
        return MediaNoteText.isTruncated(text, width: textWidth, lines: collapsedLineCount)
    }

    /// True when a tap has something to do at the current size. An expanded
    /// card can always go back, even if a rotation made the note fit.
    var isToggleable: Bool {
        isExpanded || isTruncated(forWidth: bounds.width)
    }

    /// Collapsed height at `width`, whatever the card's state.
    func collapsedHeight(forWidth width: CGFloat) -> CGFloat {
        height(forWidth: width, lines: collapsedLineCount)
    }

    /// Height needed at `width`. Expanded, that's the whole note up to `maxHeight`,
    /// and never less than the collapsed card.
    func height(forWidth width: CGFloat, maxHeight: CGFloat = .greatestFiniteMagnitude) -> CGFloat {
        let collapsed = collapsedHeight(forWidth: width)
        guard isExpanded else { return collapsed }
        return max(collapsed, min(height(forWidth: width, lines: 0), maxHeight))
    }

    /// Hints that an over-tall note can be scrolled.
    func flashScrollIndicators() {
        guard scrollView.isScrollEnabled else { return }
        scrollView.flashScrollIndicators()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        scrollView.frame = bounds
        pencilButton.frame = CGRect(
            x: bounds.width - Self.pencilHitSide,
            y: 0,
            width: Self.pencilHitSide,
            height: Self.pencilHitSide
        )

        let width = textWidth(forWidth: bounds.width)
        let room = max(0, bounds.height - verticalInset * 2)
        let lines = isExpanded ? 0 : collapsedLineCount
        let needed = bodyLabel.attributedText.map {
            ceil(MediaNoteText.height(of: $0, width: width, lines: lines))
        } ?? 0
        bodyLabel.numberOfLines = lines
        // A label shorter than its lines truncates to what fits, so a collapsed
        // card squeezed by a short screen ends on "…" rather than a cut-off line.
        bodyLabel.frame = CGRect(
            x: horizontalInset,
            y: verticalInset,
            width: max(0, width),
            height: isExpanded ? needed : min(needed, room)
        )
        scrollView.contentSize = CGSize(
            width: bounds.width,
            height: bodyLabel.frame.height + verticalInset * 2
        )
        scrollView.isScrollEnabled = isExpanded && needed > room + 0.5

        bodyElement.accessibilityFrameInContainerSpace = bounds
        refreshAccessibility()
    }

    override var canBecomeFocused: Bool { !isHidden }

    /// An external keyboard's select key does what a tap does.
    override func pressesEnded(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        guard presses.contains(where: { $0.type == .select }) else {
            super.pressesEnded(presses, with: event)
            return
        }
        sendActions(for: .touchUpInside)
    }

    // MARK: - Private

    private func setup() {
        clipsToBounds = true

        scrollView.showsHorizontalScrollIndicator = false
        scrollView.isScrollEnabled = false
        addSubview(scrollView)

        // The label is display only, so touches land on the scroll view: a UIControl
        // would stop Preview's pager from taking a slow swipe that starts on the card.
        bodyLabel.isUserInteractionEnabled = false
        bodyLabel.lineBreakMode = .byTruncatingTail
        scrollView.addSubview(bodyLabel)
        scrollView.addGestureRecognizer(
            UITapGestureRecognizer(target: self, action: #selector(bodyTapped))
        )

        setupPencil()
        setupAccessibility()
        addInteraction(UIPointerInteraction(delegate: self))
        applyText()

        registerForTraitChanges([
            UITraitPreferredContentSizeCategory.self,
            UITraitHorizontalSizeClass.self,
            UITraitVerticalSizeClass.self
        ]) { (card: ExpandableNoteCardView, _: UITraitCollection) in
            card.applyText()
            card.setNeedsLayout()
            card.onMetricsChanged?()
        }
    }

    private func setupPencil() {
        var config = UIButton.Configuration.plain()
        config.image = UIImage(
            systemName: "square.and.pencil",
            withConfiguration: UIImage.SymbolConfiguration(pointSize: 14, weight: .medium)
        )
        config.baseForegroundColor = .secondaryLabel
        config.contentInsets = .zero
        pencilButton.configuration = config
        pencilButton.isPointerInteractionEnabled = true
        pencilButton.accessibilityLabel = "Edit note"
        pencilButton.addTarget(self, action: #selector(pencilTapped), for: .touchUpInside)

        let side = Self.pencilVisibleSide
        let inset = (Self.pencilHitSide - side) / 2
        let disc = UIView(frame: CGRect(x: inset, y: inset, width: side, height: side))
        disc.backgroundColor = .tertiarySystemFill
        disc.layer.cornerRadius = side / 2
        disc.isUserInteractionEnabled = false
        pencilButton.insertSubview(disc, at: 0)
        addSubview(pencilButton)
    }

    private func setupAccessibility() {
        isAccessibilityElement = false
        bodyElement.accessibilityTraits = .button
        bodyElement.onActivate = { [weak self] in
            self?.sendActions(for: .touchUpInside)
        }
    }

    /// Text column width: the card minus its insets and the pencil's corner.
    private func textWidth(forWidth width: CGFloat) -> CGFloat {
        let trailing = pencilButton.isHidden ? horizontalInset : Self.pencilReservedWidth
        return width - horizontalInset - trailing
    }

    private func height(forWidth width: CGFloat, lines: Int) -> CGFloat {
        let textWidth = textWidth(forWidth: width)
        guard textWidth > 0, let text = bodyLabel.attributedText else { return 0 }
        let height = MediaNoteText.height(of: text, width: textWidth, lines: lines)
        return (height + verticalInset * 2).rounded(.up)
    }

    /// Rebuilds the text. It's attributed for the list indents, so its font has
    /// to be re-resolved by hand when the Dynamic Type size changes.
    private func applyText() {
        bodyLabel.attributedText = MediaNoteText.attributed(
            displayText,
            font: .preferredFont(forTextStyle: .subheadline, compatibleWith: traitCollection),
            color: displayColor
        )
        refreshAccessibility()
    }

    private func refreshAccessibility() {
        bodyElement.accessibilityLabel = "Note. \(displayText)"
        bodyElement.accessibilityValue = isTruncated(forWidth: bounds.width)
            ? (isExpanded ? "Expanded" : "Collapsed")
            : nil
        bodyElement.accessibilityCustomActions = hasNote
            ? [UIAccessibilityCustomAction(name: "Edit note") { [weak self] _ in
                self?.onEdit?()
                return true
            }]
            : nil
        accessibilityElements = hasNote ? [bodyElement, pencilButton] : [bodyElement]
    }

    @objc private func bodyTapped() {
        sendActions(for: .touchUpInside)
    }

    @objc private func pencilTapped() {
        onEdit?()
    }
}

// MARK: - UIPointerInteractionDelegate

extension ExpandableNoteCardView: UIPointerInteractionDelegate {

    /// Highlights the card only when a click would do something.
    func pointerInteraction(
        _ interaction: UIPointerInteraction,
        regionFor request: UIPointerRegionRequest,
        defaultRegion: UIPointerRegion
    ) -> UIPointerRegion? {
        (!hasNote || isToggleable) ? defaultRegion : nil
    }

    func pointerInteraction(
        _ interaction: UIPointerInteraction,
        styleFor region: UIPointerRegion
    ) -> UIPointerStyle? {
        UIPointerStyle(effect: .highlight(UITargetedPreview(view: self)))
    }
}
