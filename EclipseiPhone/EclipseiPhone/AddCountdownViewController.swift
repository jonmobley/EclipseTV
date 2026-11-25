//
//  AddCountdownViewController.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import UIKit

/// Configure-first Countdown add: name, mode (Countdown / Count Up / To Time) with
/// its length or target time, caption, size & position, background, plate, ending.
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
    /// Sections in display order; they follow the chosen mode.
    var sections: [Section] {
        Self.sections(hasShowMedia: !showMedia.isEmpty, mode: draft.clock.mode)
    }
    let nameField = UITextField()
    let captionField = UITextField()
    /// To Time rows (time, date, zone); writes the target back into the draft.
    private(set) lazy var targetRows: CountdownTargetRows = makeTargetRows()

    /// Keys the layout editor's live preview; not the id the store assigns on Add.
    private let previewId = UUID()
    private var addButton: UIBarButtonItem!
    private var thumbnailObserver: NSObjectProtocol?

    /// Table sections. Order is fixed by `sections(hasShowMedia:mode:)`.
    enum Section: Equatable {
        case name
        case mode
        case duration
        case target
        case caption
        case layout
        case background
        case showMedia
        case plate
        case ending
    }

    // MARK: - Lifecycle

    /// - Parameters:
    ///   - draft: Starting values.
    ///   - showMedia: Show members offered under "From This Show".
    init(draft: CountdownDraft, showMedia: [CountdownBackgroundOption]) {
        self.draft = draft
        self.showMedia = showMedia
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

    /// Section order for a Show with or without local media, in `mode`.
    ///
    /// Duration rows only for Countdown, target rows only for To Time, and no
    /// When It Ends for Count Up, which never ends on its own.
    static func sections(hasShowMedia: Bool, mode: CountdownMode = .countdown) -> [Section] {
        var sections: [Section] = [.name, .mode]
        switch mode {
        case .countdown: sections.append(.duration)
        case .timeOfDay: sections.append(.target)
        case .countUp: break
        }
        sections += [.caption, .layout, .background]
        if hasShowMedia { sections.append(.showMedia) }
        sections.append(.plate)
        if mode.expires { sections.append(.ending) }
        return sections
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "New Countdown"
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "field")
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "row")
        tableView.register(
            UITableViewCell.self, forCellReuseIdentifier: CountdownTargetRows.reuseId
        )
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
        configureCaptionField()
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

    @objc private func captionChanged() {
        draft.clock.caption = CountdownClockSettings.clampedCaption(captionField.text ?? "")
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

    /// Applies a Mode row; the sections around it change with the mode.
    func select(_ mode: CountdownMode) {
        guard draft.clock.mode != mode else { return }
        draft.clock.mode = mode
        if mode == .timeOfDay {
            draft.clock.takeTarget(from: targetRows.settings)
        }
        tableView.reloadData()
    }

    /// Flips "Card behind numbers".
    @objc func plateSwitchChanged(_ sender: UISwitch) {
        draft.clock.style = sender.isOn ? .card : .simple
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

    private func configureCaptionField() {
        captionField.text = draft.clock.caption
        captionField.placeholder = "None (e.g. Doors open in)"
        captionField.accessibilityLabel = "Caption"
        captionField.clearButtonMode = .whileEditing
        captionField.autocapitalizationType = .sentences
        captionField.returnKeyType = .done
        captionField.delegate = self
        captionField.addTarget(self, action: #selector(captionChanged), for: .editingChanged)
        UserDisplayName.configureTextField(captionField)
    }

    private func makeTargetRows() -> CountdownTargetRows {
        let rows = CountdownTargetRows(settings: draft.clock)
        rows.onChange = { [weak self] settings, rowsChanged in
            self?.draft.clock.takeTarget(from: settings)
            guard rowsChanged, let self,
                  let index = self.sections.firstIndex(of: .target) else { return }
            self.targetRows.syncRows(in: self.tableView, section: index)
        }
        return rows
    }

    /// Show thumbnails land from disk after the sheet paints; repaint just that row.
    private func observeThumbnails() {
        let thumbnailIdKey = TVLibraryStore.thumbnailIdKey
        thumbnailObserver = NotificationCenter.default.addObserver(
            forName: TVLibraryStore.thumbnailDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] note in
            guard let self,
                  let id = note.userInfo?[thumbnailIdKey] as? String,
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

    func reload(_ section: Section) {
        guard let index = sections.firstIndex(of: section) else { return }
        tableView.reloadSections(IndexSet(integer: index), with: .none)
    }
}
