//
//  PrompterScriptEditorViewController.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import UIKit

/// Sheet (popover on iPad) for writing a Show's Prompter script.
///
/// A sibling of `MediaNoteComposerViewController` with the same shape: full-height
/// sheet with a grabber on a phone, a popover on iPad, text pinned above the keyboard,
/// Done closes and saves, swiping down saves too.
final class PrompterScriptEditorViewController: UIViewController {

    /// Script being edited (`PrompterScriptStore` key).
    private let scriptId: UUID
    private let textView = UITextView()
    private var saveOnDisappear = true

    private static let popoverSize = CGSize(width: 520, height: 600)

    init(scriptId: UUID) {
        self.scriptId = scriptId
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// Navigation wrapper picked by the presenter's traits.
    static func makeNavigation(
        scriptId: UUID,
        traits: UITraitCollection,
        anchor: UIView?,
        arrows: UIPopoverArrowDirection
    ) -> UINavigationController {
        let editor = PrompterScriptEditorViewController(scriptId: scriptId)
        let nav = UINavigationController(rootViewController: editor)
        guard traits.prefersRegularNoteLayout, let anchor else {
            if let sheet = nav.sheetPresentationController {
                configure(sheet)
            }
            return nav
        }
        nav.modalPresentationStyle = .popover
        editor.preferredContentSize = popoverSize
        if let popover = nav.popoverPresentationController {
            popover.delegate = editor
            popover.sourceView = anchor
            popover.sourceRect = anchor.bounds
            popover.permittedArrowDirections = arrows
            configure(popover.adaptiveSheetPresentationController)
        }
        return nav
    }

    override var keyCommands: [UIKeyCommand]? {
        let done = UIKeyCommand(
            title: "Done", action: #selector(doneTapped), input: "\r", modifierFlags: .command
        )
        let close = UIKeyCommand(
            title: "Close", action: #selector(closeTapped), input: UIKeyCommand.inputEscape
        )
        done.wantsPriorityOverSystemBehavior = true
        close.wantsPriorityOverSystemBehavior = true
        return [done, close]
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        title = PrompterScriptStore.shared.hasScript(forShowId: scriptId) ? "Edit Script" : "Write Script"
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            barButtonSystemItem: .done, target: self, action: #selector(doneTapped)
        )
        setupTextView()
        textView.text = PrompterScriptStore.shared.script(forShowId: scriptId)
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
        // Full height from the start: the keyboard pushes a medium sheet to large,
        // which reads as the sheet stalling halfway up.
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
        textView.autocorrectionType = .yes
        textView.delegate = self
        textView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(textView)
        view.keyboardLayoutGuide.usesBottomSafeArea = false
        NSLayoutConstraint.activate([
            textView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            textView.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor),
            textView.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor),
            textView.bottomAnchor.constraint(equalTo: view.keyboardLayoutGuide.topAnchor)
        ])
        textView.accessibilityLabel = "Script"
    }

    private func makeHideKeyboardButton() -> UIBarButtonItem {
        let item = UIBarButtonItem(
            image: UIImage(systemName: "keyboard.chevron.compact.down"),
            style: .plain, target: self, action: #selector(hideKeyboardTapped)
        )
        item.accessibilityLabel = "Hide Keyboard"
        return item
    }

    private func commit() {
        PrompterScriptStore.shared.setScript(textView.text ?? "", forShowId: scriptId)
    }

    @objc private func doneTapped() {
        saveOnDisappear = false
        commit()
        dismiss(animated: true)
    }

    @objc private func hideKeyboardTapped() {
        textView.resignFirstResponder()
    }

    @objc private func closeTapped() {
        dismiss(animated: true)
    }
}

// MARK: - UITextViewDelegate

extension PrompterScriptEditorViewController: UITextViewDelegate {

    func textViewDidBeginEditing(_ textView: UITextView) {
        navigationItem.leftBarButtonItem = makeHideKeyboardButton()
    }

    func textViewDidEndEditing(_ textView: UITextView) {
        navigationItem.leftBarButtonItem = nil
    }
}

// MARK: - UIPopoverPresentationControllerDelegate

extension PrompterScriptEditorViewController: UIPopoverPresentationControllerDelegate {

    func adaptivePresentationStyle(
        for controller: UIPresentationController,
        traitCollection: UITraitCollection
    ) -> UIModalPresentationStyle {
        traitCollection.prefersRegularNoteLayout ? .none : .pageSheet
    }
}
