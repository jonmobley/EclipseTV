//
//  MediaNoteComposerViewController.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import UIKit

extension UITraitCollection {

    /// True on iPad-sized panes. Plus/Max landscape is `.regular` width too, but
    /// it's still a phone with the keyboard taking half the screen.
    var prefersRegularNoteLayout: Bool {
        horizontalSizeClass == .regular && verticalSizeClass != .compact
    }
}

/// Sheet (popover on iPad) for adding or editing a still's presenter note.
final class MediaNoteComposerViewController: UIViewController {

    private let itemId: String
    private let textView = UITextView()
    private var saveOnDisappear = true

    private static let popoverSize = CGSize(width: 420, height: 320)

    /// - Parameter itemId: Library still id whose note is edited.
    init(itemId: String) {
        self.itemId = itemId
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// Navigation wrapper: a full-height sheet with grabber on a phone, and on
    /// iPad a popover, because a sheet there is a form sheet over the preview.
    ///
    /// - Parameters:
    ///   - traits: The presenter's traits, which pick the style.
    ///   - anchor: What the popover points at.
    ///   - arrows: Sides the popover may point from; empty centers it on `anchor`.
    static func makeNavigation(
        itemId: String,
        traits: UITraitCollection,
        anchor: UIView,
        arrows: UIPopoverArrowDirection
    ) -> UINavigationController {
        let composer = MediaNoteComposerViewController(itemId: itemId)
        let nav = UINavigationController(rootViewController: composer)
        guard traits.prefersRegularNoteLayout else {
            if let sheet = nav.sheetPresentationController {
                configure(sheet)
            }
            return nav
        }
        nav.modalPresentationStyle = .popover
        composer.preferredContentSize = popoverSize
        if let popover = nav.popoverPresentationController {
            popover.delegate = composer
            popover.sourceView = anchor
            popover.sourceRect = anchor.bounds
            popover.permittedArrowDirections = arrows
            configure(popover.adaptiveSheetPresentationController)
        }
        return nav
    }

    override var keyCommands: [UIKeyCommand]? {
        let done = UIKeyCommand(
            title: "Done",
            action: #selector(doneTapped),
            input: "\r",
            modifierFlags: .command
        )
        let close = UIKeyCommand(
            title: "Close",
            action: #selector(closeTapped),
            input: UIKeyCommand.inputEscape
        )
        done.wantsPriorityOverSystemBehavior = true
        close.wantsPriorityOverSystemBehavior = true
        return [done, close]
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        title = MediaNoteStore.hasNote(forId: itemId) ? "Edit Note" : "Add Note"
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            barButtonSystemItem: .done,
            target: self,
            action: #selector(doneTapped)
        )
        setupTextView()
        textView.text = MediaNoteStore.note(forId: itemId) ?? ""
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        textView.becomeFirstResponder()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        guard saveOnDisappear else { return }
        commit()
    }

    // MARK: - Private

    private static func configure(_ sheet: UISheetPresentationController) {
        // Full height from the start: the keyboard forces a medium sheet to
        // large, which reads as the sheet stalling halfway up.
        sheet.detents = [.large()]
        sheet.prefersGrabberVisible = true
    }

    private func setupTextView() {
        textView.font = .preferredFont(forTextStyle: .body)
        textView.adjustsFontForContentSizeCategory = true
        textView.textColor = .label
        textView.backgroundColor = .clear
        textView.textContainerInset = UIEdgeInsets(top: 12, left: 12, bottom: 12, right: 12)
        textView.alwaysBounceVertical = true
        textView.keyboardDismissMode = .interactive
        textView.delegate = self
        textView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(textView)
        view.keyboardLayoutGuide.usesBottomSafeArea = false
        NSLayoutConstraint.activate([
            textView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            textView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            textView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            textView.bottomAnchor.constraint(equalTo: view.keyboardLayoutGuide.topAnchor)
        ])
        textView.accessibilityLabel = "Note"
    }

    /// Done closes the editor, so reading a long note needs its own way to
    /// lower the keyboard. Tapping the text brings it back.
    private func makeHideKeyboardButton() -> UIBarButtonItem {
        let item = UIBarButtonItem(
            image: UIImage(systemName: "keyboard.chevron.compact.down"),
            style: .plain,
            target: self,
            action: #selector(hideKeyboardTapped)
        )
        item.accessibilityLabel = "Hide Keyboard"
        return item
    }

    private func commit() {
        let before = MediaNoteStore.note(forId: itemId)
        MediaNoteStore.setNote(textView.text, forId: itemId)
        guard MediaNoteStore.note(forId: itemId) != before else { return }
        EclipseSyncController.shared.backend.scheduleMediaPrefsSave(libraryId: itemId)
    }

    @objc private func doneTapped() {
        saveOnDisappear = false
        commit()
        dismiss(animated: true)
    }

    @objc private func hideKeyboardTapped() {
        textView.resignFirstResponder()
    }

    /// Esc closes the editor. `viewWillDisappear` saves, same as a swipe down.
    @objc private func closeTapped() {
        dismiss(animated: true)
    }
}

// MARK: - UITextViewDelegate

extension MediaNoteComposerViewController: UITextViewDelegate {

    func textViewDidBeginEditing(_ textView: UITextView) {
        navigationItem.leftBarButtonItem = makeHideKeyboardButton()
    }

    func textViewDidEndEditing(_ textView: UITextView) {
        navigationItem.leftBarButtonItem = nil
    }
}

// MARK: - UIPopoverPresentationControllerDelegate

extension MediaNoteComposerViewController: UIPopoverPresentationControllerDelegate {

    /// Follows the pane: a Split View resize to compact width turns it into the sheet.
    func adaptivePresentationStyle(
        for controller: UIPresentationController,
        traitCollection: UITraitCollection
    ) -> UIModalPresentationStyle {
        traitCollection.prefersRegularNoteLayout ? .none : .pageSheet
    }
}
