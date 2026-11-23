//
//  QuestPollEditorCells.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import UIKit

/// One-line text field row for the poll editor (poll name, an answer).
///
/// In a quiz an answer row also shows a round mark on the left: filled for the
/// right answer, tapped to choose it.
final class QuestPollTextFieldCell: UITableViewCell {

    static let reuseIdentifier = "questpoll.editor.field"

    let textField = UITextField()
    private let markButton = UIButton(type: .system)
    private var textLeadingToMargin: NSLayoutConstraint!
    private var textLeadingToMark: NSLayoutConstraint!

    var onTextChange: ((String) -> Void)?
    var onMarkTapped: (() -> Void)?

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        selectionStyle = .none

        markButton.translatesAutoresizingMaskIntoConstraints = false
        markButton.addAction(UIAction { [weak self] _ in self?.onMarkTapped?() }, for: .touchUpInside)
        contentView.addSubview(markButton)

        textField.translatesAutoresizingMaskIntoConstraints = false
        textField.font = .preferredFont(forTextStyle: .body)
        textField.adjustsFontForContentSizeCategory = true
        textField.clearButtonMode = .whileEditing
        textField.autocapitalizationType = .sentences
        textField.addAction(UIAction { [weak self] _ in
            self?.onTextChange?(self?.textField.text ?? "")
        }, for: .editingChanged)
        contentView.addSubview(textField)

        let margins = contentView.layoutMarginsGuide
        textLeadingToMargin = textField.leadingAnchor.constraint(equalTo: margins.leadingAnchor)
        textLeadingToMark = textField.leadingAnchor.constraint(
            equalTo: markButton.trailingAnchor, constant: 4
        )
        NSLayoutConstraint.activate([
            markButton.leadingAnchor.constraint(equalTo: margins.leadingAnchor, constant: -8),
            markButton.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            markButton.widthAnchor.constraint(equalToConstant: 44),
            markButton.heightAnchor.constraint(equalToConstant: 44),
            textField.trailingAnchor.constraint(equalTo: margins.trailingAnchor),
            textField.topAnchor.constraint(equalTo: contentView.topAnchor),
            textField.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
            textField.heightAnchor.constraint(greaterThanOrEqualToConstant: 44),
            textLeadingToMargin
        ])
        setMark(nil)
    }

    required init?(coder: NSCoder) { nil }

    override func prepareForReuse() {
        super.prepareForReuse()
        onTextChange = nil
        onMarkTapped = nil
        textField.delegate = nil
        textField.text = nil
        textField.returnKeyType = .default
        textField.accessibilityIdentifier = nil
        setMark(nil)
    }

    /// Shows the right-answer mark (`true` filled, `false` empty) or hides it (`nil`).
    func setMark(_ isRightAnswer: Bool?) {
        guard let isRightAnswer else {
            markButton.isHidden = true
            textLeadingToMark.isActive = false
            textLeadingToMargin.isActive = true
            return
        }
        markButton.isHidden = false
        textLeadingToMargin.isActive = false
        textLeadingToMark.isActive = true
        let name = isRightAnswer ? "checkmark.circle.fill" : "circle"
        markButton.setImage(UIImage(systemName: name), for: .normal)
        markButton.tintColor = isRightAnswer ? .systemGreen : .tertiaryLabel
        markButton.accessibilityLabel = isRightAnswer ? "Right answer" : "Mark as right answer"
    }
}

/// Growing multi-line text row with a placeholder (the question itself).
final class QuestPollTextViewCell: UITableViewCell, UITextViewDelegate {

    static let reuseIdentifier = "questpoll.editor.text"

    let textView = UITextView()
    private let placeholderLabel = UILabel()

    var maxCharacters = Int.max
    var onTextChange: ((String) -> Void)?

    var placeholder: String? {
        get { placeholderLabel.text }
        set { placeholderLabel.text = newValue }
    }

    var text: String {
        get { textView.text ?? "" }
        set {
            textView.text = newValue
            placeholderLabel.isHidden = !newValue.isEmpty
        }
    }

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        selectionStyle = .none

        textView.translatesAutoresizingMaskIntoConstraints = false
        textView.font = .preferredFont(forTextStyle: .body)
        textView.adjustsFontForContentSizeCategory = true
        textView.backgroundColor = .clear
        textView.isScrollEnabled = false
        textView.textContainerInset = UIEdgeInsets(top: 12, left: 0, bottom: 12, right: 0)
        textView.textContainer.lineFragmentPadding = 0
        textView.delegate = self
        contentView.addSubview(textView)

        placeholderLabel.translatesAutoresizingMaskIntoConstraints = false
        placeholderLabel.font = textView.font
        placeholderLabel.adjustsFontForContentSizeCategory = true
        placeholderLabel.textColor = .placeholderText
        contentView.addSubview(placeholderLabel)

        let margins = contentView.layoutMarginsGuide
        NSLayoutConstraint.activate([
            textView.leadingAnchor.constraint(equalTo: margins.leadingAnchor),
            textView.trailingAnchor.constraint(equalTo: margins.trailingAnchor),
            textView.topAnchor.constraint(equalTo: contentView.topAnchor),
            textView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
            textView.heightAnchor.constraint(greaterThanOrEqualToConstant: 44),
            placeholderLabel.leadingAnchor.constraint(equalTo: textView.leadingAnchor),
            placeholderLabel.topAnchor.constraint(equalTo: textView.topAnchor, constant: 12)
        ])
    }

    required init?(coder: NSCoder) { nil }

    func textViewDidChange(_ textView: UITextView) {
        placeholderLabel.isHidden = !textView.text.isEmpty
        onTextChange?(textView.text)
    }

    func textView(
        _ textView: UITextView,
        shouldChangeTextIn range: NSRange,
        replacementText text: String
    ) -> Bool {
        // A question is one paragraph; Return puts the keyboard away.
        if text == "\n" {
            textView.resignFirstResponder()
            return false
        }
        return QuestPollEditorText.allows(
            current: textView.text ?? "", range: range, replacement: text, limit: maxCharacters
        )
    }
}

/// Text rules shared by the poll editor's fields.
enum QuestPollEditorText {

    /// Whether an edit keeps the text within `limit` characters. Deleting is
    /// always allowed, so text already over the limit can be shortened.
    static func allows(
        current: String, range: NSRange, replacement: String, limit: Int
    ) -> Bool {
        guard let swiftRange = Range(range, in: current) else { return true }
        let removed = current[swiftRange].count
        let added = replacement.count
        if added <= removed { return true }
        return current.count - removed + added <= limit
    }
}

/// Small helpers for the editor's menu and switch rows.
enum QuestPollEditorControls {

    /// A value button that opens a menu ("30 seconds ⌄").
    static func menuButton(title: String, menu: UIMenu) -> UIButton {
        var configuration = UIButton.Configuration.plain()
        configuration.title = title
        configuration.image = UIImage(
            systemName: "chevron.up.chevron.down",
            withConfiguration: UIImage.SymbolConfiguration(scale: .small)
        )
        configuration.imagePlacement = .trailing
        configuration.imagePadding = 4
        configuration.contentInsets = NSDirectionalEdgeInsets(top: 8, leading: 8, bottom: 8, trailing: 0)
        let button = UIButton(configuration: configuration)
        button.menu = menu
        button.showsMenuAsPrimaryAction = true
        button.sizeToFit()
        return button
    }

    /// A menu of answer windows with `current` ticked.
    static func timeMenu(current: Int?, including extra: Int, onPick: @escaping (Int) -> Void) -> UIMenu {
        UIMenu(children: QuestPollDraft.timeChoices(including: extra).map { seconds in
            UIAction(
                title: QuestPollDraft.timeLabel(seconds),
                state: seconds == current ? .on : .off
            ) { _ in onPick(seconds) }
        })
    }
}
