//
//  MediaNoteComposerViewController.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import UIKit

/// Slide-up sheet for adding or editing a still's presenter note.
final class MediaNoteComposerViewController: UIViewController {

    private let itemId: String
    private let textView = UITextView()
    private var saveOnDisappear = true

    /// - Parameter itemId: Library still id whose note is edited.
    init(itemId: String) {
        self.itemId = itemId
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// Navigation wrapper presented as a medium/large sheet with grabber.
    static func makeNavigation(itemId: String) -> UINavigationController {
        let composer = MediaNoteComposerViewController(itemId: itemId)
        let nav = UINavigationController(rootViewController: composer)
        if let sheet = nav.sheetPresentationController {
            sheet.detents = [.medium(), .large()]
            sheet.selectedDetentIdentifier = .medium
            sheet.prefersGrabberVisible = true
        }
        return nav
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

    private func setupTextView() {
        textView.font = .preferredFont(forTextStyle: .body)
        textView.adjustsFontForContentSizeCategory = true
        textView.textColor = .label
        textView.backgroundColor = .clear
        textView.textContainerInset = UIEdgeInsets(top: 12, left: 12, bottom: 12, right: 12)
        textView.alwaysBounceVertical = true
        textView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(textView)
        NSLayoutConstraint.activate([
            textView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            textView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            textView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            textView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
        textView.accessibilityLabel = "Note"
    }

    private func commit() {
        MediaNoteStore.setNote(textView.text, forId: itemId)
    }

    @objc private func doneTapped() {
        saveOnDisappear = false
        commit()
        dismiss(animated: true)
    }
}
