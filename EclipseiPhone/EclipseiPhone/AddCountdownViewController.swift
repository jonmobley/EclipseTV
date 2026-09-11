//
//  AddCountdownViewController.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import UIKit

/// Configure-first Countdown add: name, duration, size & placement, background, ending.
///
/// Nothing reaches `CountdownStore` until Add, so backing out leaves the Show exactly
/// as it was. Rows are drawn in `AddCountdownViewController+Rows`.
final class AddCountdownViewController: UITableViewController, UITextFieldDelegate {

    /// Fired after Add, once the sheet has dismissed, with the new countdown's id.
    var onAdded: ((UUID) -> Void)?

    /// Values collected so far. Mutated in place by the rows.
    private(set) var draft: CountdownDraft
    /// This Show's media with a local file, in Show order.
    let showMedia: [CountdownBackgroundOption]
    /// Sections in display order; `showMedia` is present only when the Show has media.
    let sections: [Section]
    let nameField = UITextField()

    /// Keys the layout editor's live preview; not the id the store assigns on Add.
    private let previewId = UUID()
    private var addButton: UIBarButtonItem!
    private var thumbnailObserver: NSObjectProtocol?

    /// Table sections. Order is fixed by `sections(hasShowMedia:)`.
    enum Section: Equatable {
        case name
        case duration
        case layout
        case background
        case showMedia
        case ending
    }

    // MARK: - Lifecycle

    /// - Parameters:
    ///   - draft: Starting values.
    ///   - showMedia: Show members offered under "From This Show".
    init(draft: CountdownDraft, showMedia: [CountdownBackgroundOption]) {
        self.draft = draft
        self.showMedia = showMedia
        self.sections = Self.sections(hasShowMedia: !showMedia.isEmpty)
        super.init(style: .insetGrouped)
    }

    /// Fresh draft for a new countdown in `showId`, seeded from the live stores.
    convenience init(showId: UUID) {
        self.init(
            draft: .make(forShowId: showId),
            showMedia: CountdownBackgroundOption.showMedia(inShowId: showId)
        )
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        if let thumbnailObserver {
            NotificationCenter.default.removeObserver(thumbnailObserver)
        }
    }

    /// Section order for a Show with or without local media.
    static func sections(hasShowMedia: Bool) -> [Section] {
        var sections: [Section] = [.name, .duration, .layout, .background]
        if hasShowMedia { sections.append(.showMedia) }
        sections.append(.ending)
        return sections
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "New Countdown"
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "field")
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "row")
        tableView.keyboardDismissMode = .interactive

        navigationItem.leftBarButtonItem = UIBarButtonItem(
            systemItem: .cancel,
            primaryAction: UIAction { [weak self] _ in
                self?.dismiss(animated: true)
            }
        )
        addButton = UIBarButtonItem(
            title: "Add",
            style: .done,
            target: self,
            action: #selector(addTapped)
        )
        navigationItem.rightBarButtonItem = addButton

        configureNameField()
        observeThumbnails()
        updateAddEnabled()
    }

    // MARK: - Actions

    @objc private func addTapped() {
        do {
            let item = try draft.commit()
            let notify = onAdded
            dismiss(animated: true) {
                notify?(item.id)
            }
        } catch {
            let alert = UIAlertController(
                title: "Couldn't Create Countdown",
                message: error.localizedDescription,
                preferredStyle: .alert
            )
            alert.addAction(UIAlertAction(title: "OK", style: .default))
            present(alert, animated: true)
        }
    }

    @objc private func nameChanged() {
        draft.name = nameField.text ?? ""
        updateAddEnabled()
    }

    /// Applies a Duration row: a preset directly, Custom… through the shared prompt.
    func selectDuration(at row: Int) {
        let presets = CountdownController.durationPresets
        if presets.indices.contains(row) {
            draft.duration = presets[row]
            reload(.duration)
            return
        }
        CountdownDurationPrompt.present(from: self, seconds: draft.duration) {
            [weak self] seconds in
            self?.draft.duration = CountdownController.clampedDuration(seconds)
            self?.reload(.duration)
        }
    }

    /// Opens the drag / pinch canvas on the draft; Done writes back into the draft.
    func presentLayoutEditor() {
        let editor = CountdownLayoutEditorViewController(
            item: draft.previewItem(id: previewId)
        ) { [weak self] layout in
            self?.draft.layout = layout
            self?.reload(.layout)
        }
        let nav = UINavigationController(rootViewController: editor)
        nav.modalPresentationStyle = .fullScreen
        present(nav, animated: true)
    }

    /// Applies a Background / From This Show row.
    func select(_ option: CountdownBackgroundOption) {
        draft.background = option.background
        reload(.background)
        reload(.showMedia)
    }

    /// Applies a When It Ends row.
    func select(_ action: CountdownEndAction) {
        draft.endAction = action
        reload(.ending)
    }

    // MARK: - UITextFieldDelegate

    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        textField.resignFirstResponder()
        return true
    }

    // MARK: - Private

    private func configureNameField() {
        nameField.text = draft.name
        nameField.placeholder = "Name"
        nameField.clearButtonMode = .whileEditing
        nameField.autocapitalizationType = .words
        nameField.returnKeyType = .done
        nameField.delegate = self
        nameField.addTarget(self, action: #selector(nameChanged), for: .editingChanged)
        UserDisplayName.configureTextField(nameField)
    }

    /// Show thumbnails land from disk after the sheet paints; repaint just that row.
    private func observeThumbnails() {
        thumbnailObserver = NotificationCenter.default.addObserver(
            forName: TVLibraryStore.thumbnailDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] note in
            guard let self,
                  let id = note.userInfo?[TVLibraryStore.thumbnailIdKey] as? String,
                  let section = self.sections.firstIndex(of: .showMedia),
                  let row = self.showMedia.firstIndex(where: { $0.mediaId == id })
            else { return }
            self.tableView.reloadRows(
                at: [IndexPath(row: row, section: section)], with: .none
            )
        }
    }

    private func updateAddEnabled() {
        addButton.isEnabled = UserDisplayName.normalized(draft.name) != nil
    }

    private func reload(_ section: Section) {
        guard let index = sections.firstIndex(of: section) else { return }
        tableView.reloadSections(IndexSet(integer: index), with: .none)
    }
}
