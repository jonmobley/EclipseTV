//
//  QuestPollEditorViewController.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import LivePollKit
import UIKit

/// Creates or changes one of the account's polls, in the app.
///
/// Name, Poll / Quiz, time per question and the question list live here; each
/// question opens `QuestPollQuestionEditorViewController`. Nothing reaches
/// QuestPoll until Save, and a room that is already running keeps the copy it
/// started with, so editing never changes what the audience sees right now.
final class QuestPollEditorViewController: UITableViewController,
    UITextFieldDelegate, UIAdaptivePresentationControllerDelegate {

    enum Target: Equatable {
        case new
        case existing(pollId: String)
    }

    /// The poll as QuestPoll stored it, after a successful Save.
    var onSaved: ((LivePollDeck) -> Void)?
    /// The id of a poll that was deleted here.
    var onDeleted: ((String) -> Void)?

    private let target: Target
    private let client: LivePollClient

    /// The poll being edited; nil while an existing one is still loading.
    private(set) var draft: QuestPollDraft?
    private var original: QuestPollDraft?
    private var loadError: String?
    private var isWorking = false

    private enum Section { case details, questions, delete }
    private enum DetailRow: Int, CaseIterable { case name, type, time, showQuestion }

    private var sections: [Section] {
        guard let draft else { return [] }
        return draft.id == nil ? [.details, .questions] : [.details, .questions, .delete]
    }

    /// Wraps the editor in its own sheet.
    static func makeNavigation(
        target: Target,
        client: LivePollClient = LivePollAccountStore.client(),
        onSaved: ((LivePollDeck) -> Void)? = nil,
        onDeleted: ((String) -> Void)? = nil
    ) -> UINavigationController {
        let editor = QuestPollEditorViewController(target: target, client: client)
        editor.onSaved = onSaved
        editor.onDeleted = onDeleted
        let nav = UINavigationController(rootViewController: editor)
        nav.modalPresentationStyle = .formSheet
        nav.presentationController?.delegate = editor
        return nav
    }

    init(target: Target, client: LivePollClient = LivePollAccountStore.client()) {
        self.target = target
        self.client = client
        super.init(style: .insetGrouped)
        if target == .new {
            let blank = QuestPollDraft()
            draft = blank
            original = blank
        }
    }

    required init?(coder: NSCoder) { nil }

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        title = target == .new ? "New Poll" : "Edit Poll"
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "cell")
        tableView.register(
            QuestPollTextFieldCell.self,
            forCellReuseIdentifier: QuestPollTextFieldCell.reuseIdentifier
        )
        // Always in list-editing mode: questions show delete and reorder
        // handles without a separate Edit step.
        tableView.isEditing = true
        tableView.allowsSelectionDuringEditing = true
        tableView.keyboardDismissMode = .interactive
        navigationItem.leftBarButtonItem = UIBarButtonItem(
            barButtonSystemItem: .cancel, target: self, action: #selector(cancelTapped)
        )
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            barButtonSystemItem: .save, target: self, action: #selector(saveTapped)
        )
        navigationItem.rightBarButtonItem?.accessibilityIdentifier = "questpoll.editor.save"
        updateChrome()
        if case .existing(let pollId) = target { load(pollId: pollId) }
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        // Back from a question: its row text and the save state may have changed.
        if draft != nil, let index = sections.firstIndex(of: .questions) {
            tableView.reloadSections(IndexSet(integer: index), with: .none)
        }
        updateChrome()
    }

    // MARK: - Loading

    private func load(pollId: String) {
        loadError = nil
        updateChrome()
        Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                var loaded = QuestPollDraft(deck: try await self.client.deck(id: pollId))
                loaded.id = pollId
                self.draft = loaded
                self.original = loaded
            } catch {
                self.loadError = Self.message(for: error, fallback: "Could not load this poll.")
            }
            self.tableView.reloadData()
            self.updateChrome()
        }
    }

    // MARK: - State

    var isDirty: Bool { draft != original }

    /// Why Save is unavailable, or a note about a running room; nil when
    /// there is nothing to say.
    var statusText: String? {
        guard let draft else { return nil }
        if let problem = draft.problem { return problem }
        if let id = draft.id, Self.isLive(pollId: id) {
            return "This \(draft.noun) is live now. Changes show the next time you start it."
        }
        return nil
    }

    private static func isLive(pollId: String) -> Bool {
        let room = QuestPollSessionStore.shared
        guard room.session != nil, let membershipId = room.membershipId else { return false }
        return LivePollStore.shared.poll(id: membershipId)?.pollId == pollId
    }

    private func updateChrome() {
        let ready = draft?.problem == nil && draft != nil
        navigationItem.rightBarButtonItem?.isEnabled = ready && isDirty && !isWorking
        navigationItem.leftBarButtonItem?.isEnabled = !isWorking
        isModalInPresentation = isDirty || isWorking
        tableView.isUserInteractionEnabled = !isWorking

        if draft != nil {
            contentUnavailableConfiguration = nil
        } else if let loadError {
            var configuration = UIContentUnavailableConfiguration.empty()
            configuration.image = UIImage(systemName: "exclamationmark.triangle")
            configuration.text = loadError
            configuration.button = .borderedTinted()
            configuration.button.title = "Try Again"
            configuration.buttonProperties.primaryAction = UIAction { [weak self] _ in
                guard let self, case .existing(let pollId) = self.target else { return }
                self.load(pollId: pollId)
            }
            contentUnavailableConfiguration = configuration
        } else {
            contentUnavailableConfiguration = UIContentUnavailableConfiguration.loading()
        }
        updateStatusFooter()
    }

    /// Rewrites the questions footer in place; reloading the table would put
    /// the keyboard away mid-word.
    private func updateStatusFooter() {
        guard let index = sections.firstIndex(of: .questions),
              let footer = tableView.footerView(forSection: index) else { return }
        var content = footer.defaultContentConfiguration()
        content.text = statusText
        guard (footer.contentConfiguration as? UIListContentConfiguration)?.text != content.text
        else { return }
        footer.contentConfiguration = content
        UIView.performWithoutAnimation {
            tableView.beginUpdates()
            tableView.endUpdates()
        }
    }

    private func mutate(_ change: (inout QuestPollDraft) -> Void) {
        guard var current = draft else { return }
        change(&current)
        draft = current
        updateChrome()
    }

    // MARK: - Table

    override func numberOfSections(in tableView: UITableView) -> Int {
        sections.count
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        guard let draft else { return 0 }
        switch sections[section] {
        case .details: return DetailRow.allCases.count
        case .questions: return draft.questions.count + (draft.canAddQuestion ? 1 : 0)
        case .delete: return 1
        }
    }

    override func tableView(
        _ tableView: UITableView, titleForHeaderInSection section: Int
    ) -> String? {
        sections[section] == .questions ? "Questions" : nil
    }

    override func tableView(
        _ tableView: UITableView, titleForFooterInSection section: Int
    ) -> String? {
        switch sections[section] {
        case .details:
            return "A poll collects opinions. A quiz has right answers, keeps score "
                + "and shows a leaderboard."
        case .questions:
            return statusText
        case .delete:
            return nil
        }
    }

    override func tableView(
        _ tableView: UITableView, cellForRowAt indexPath: IndexPath
    ) -> UITableViewCell {
        guard let draft else { return UITableViewCell() }
        switch sections[indexPath.section] {
        case .details:
            return detailCell(DetailRow(rawValue: indexPath.row) ?? .name, draft: draft, at: indexPath)
        case .questions:
            return questionCell(draft: draft, at: indexPath)
        case .delete:
            let cell = plainCell(at: indexPath)
            var content = cell.defaultContentConfiguration()
            content.text = draft.mode == .quiz ? "Delete Quiz" : "Delete Poll"
            content.textProperties.color = .systemRed
            content.textProperties.alignment = .center
            cell.contentConfiguration = content
            cell.accessibilityIdentifier = "questpoll.editor.delete"
            return cell
        }
    }

    private func plainCell(at indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "cell", for: indexPath)
        cell.editingAccessoryView = nil
        cell.editingAccessoryType = .none
        cell.selectionStyle = .default
        cell.accessibilityIdentifier = nil
        return cell
    }

    private func detailCell(
        _ row: DetailRow, draft: QuestPollDraft, at indexPath: IndexPath
    ) -> UITableViewCell {
        if row == .name {
            let cell = tableView.dequeueReusableCell(
                withIdentifier: QuestPollTextFieldCell.reuseIdentifier, for: indexPath
            ) as? QuestPollTextFieldCell ?? QuestPollTextFieldCell()
            cell.textField.placeholder = "Name"
            cell.textField.text = draft.title
            cell.textField.returnKeyType = .done
            cell.textField.delegate = self
            cell.textField.accessibilityIdentifier = "questpoll.editor.name"
            cell.onTextChange = { [weak self] text in
                self?.mutate { $0.title = text }
            }
            return cell
        }
        let cell = plainCell(at: indexPath)
        cell.selectionStyle = .none
        var content = cell.defaultContentConfiguration()
        switch row {
        case .name:
            break
        case .type:
            content.text = "Type"
            let control = UISegmentedControl(items: ["Poll", "Quiz"])
            control.selectedSegmentIndex = draft.mode == .quiz ? 1 : 0
            control.addAction(UIAction { [weak self, weak control] _ in
                let isQuiz = control?.selectedSegmentIndex == 1
                self?.mutate { $0.mode = isQuiz ? .quiz : .poll }
                self?.reloadDeleteRow()
            }, for: .valueChanged)
            control.sizeToFit()
            cell.editingAccessoryView = control
        case .time:
            content.text = "Time per Question"
            let shared = draft.hasMixedTimers ? nil : draft.commonSeconds
            let menu = QuestPollEditorControls.timeMenu(
                current: shared, including: draft.commonSeconds
            ) { [weak self] seconds in
                self?.mutate { $0.setAllSeconds(seconds) }
                self?.reloadVisibleRows()
            }
            cell.editingAccessoryView = QuestPollEditorControls.menuButton(
                title: shared.map(QuestPollDraft.timeLabel) ?? "Varies", menu: menu
            )
        case .showQuestion:
            content.text = "Show Question on Phones"
            content.secondaryText = "Off shows only the answers there."
            let toggle = UISwitch()
            toggle.isOn = draft.showQuestionOnPhone
            toggle.addAction(UIAction { [weak self, weak toggle] _ in
                let isOn = toggle?.isOn ?? true
                self?.mutate { $0.showQuestionOnPhone = isOn }
            }, for: .valueChanged)
            cell.editingAccessoryView = toggle
        }
        cell.contentConfiguration = content
        return cell
    }

    private func questionCell(draft: QuestPollDraft, at indexPath: IndexPath) -> UITableViewCell {
        let cell = plainCell(at: indexPath)
        var content = cell.defaultContentConfiguration()
        guard draft.questions.indices.contains(indexPath.row) else {
            content.text = "Add Question"
            content.textProperties.color = .tintColor
            cell.contentConfiguration = content
            cell.accessibilityIdentifier = "questpoll.editor.addQuestion"
            return cell
        }
        let question = draft.questions[indexPath.row]
        content.text = Self.questionTitle(question, number: indexPath.row + 1)
        content.textProperties.numberOfLines = 2
        content.secondaryText = Self.questionDetail(
            question, showsTime: draft.hasMixedTimers
        )
        content.secondaryTextProperties.color = .secondaryLabel
        cell.contentConfiguration = content
        cell.editingAccessoryType = .disclosureIndicator
        return cell
    }

    /// "2. Where should we eat?" (or "2. New question" while it is empty).
    static func questionTitle(_ question: QuestPollDraft.Question, number: Int) -> String {
        let prompt = question.prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        return "\(number). \(prompt.isEmpty ? "New question" : prompt)"
    }

    /// "4 answers", with the time when questions differ.
    static func questionDetail(_ question: QuestPollDraft.Question, showsTime: Bool) -> String {
        let count = question.filledOptions.count
        let answers = count == 0 ? "No answers yet" : "\(count) answer\(count == 1 ? "" : "s")"
        return showsTime ? "\(answers) · \(QuestPollDraft.timeLabel(question.seconds))" : answers
    }

    private func reloadVisibleRows() {
        UIView.performWithoutAnimation { tableView.reloadData() }
    }

    private func reloadDeleteRow() {
        guard let index = sections.firstIndex(of: .delete) else { return }
        tableView.reloadSections(IndexSet(integer: index), with: .none)
    }

    // MARK: - Rows: delete, add, reorder

    private func isQuestionRow(_ indexPath: IndexPath) -> Bool {
        sections[indexPath.section] == .questions
            && (draft?.questions.indices.contains(indexPath.row) ?? false)
    }

    override func tableView(
        _ tableView: UITableView, editingStyleForRowAt indexPath: IndexPath
    ) -> UITableViewCell.EditingStyle {
        guard sections[indexPath.section] == .questions, let draft else { return .none }
        if !isQuestionRow(indexPath) { return .insert }
        // A poll always keeps one question.
        return draft.questions.count > 1 ? .delete : .none
    }

    override func tableView(
        _ tableView: UITableView, shouldIndentWhileEditingRowAt indexPath: IndexPath
    ) -> Bool {
        sections[indexPath.section] == .questions
    }

    override func tableView(_ tableView: UITableView, canMoveRowAt indexPath: IndexPath) -> Bool {
        isQuestionRow(indexPath) && (draft?.questions.count ?? 0) > 1
    }

    override func tableView(
        _ tableView: UITableView,
        targetIndexPathForMoveFromRowAt source: IndexPath,
        toProposedIndexPath proposed: IndexPath
    ) -> IndexPath {
        let last = max((draft?.questions.count ?? 1) - 1, 0)
        if proposed.section < source.section { return IndexPath(row: 0, section: source.section) }
        if proposed.section > source.section { return IndexPath(row: last, section: source.section) }
        return IndexPath(row: min(proposed.row, last), section: source.section)
    }

    override func tableView(
        _ tableView: UITableView, moveRowAt source: IndexPath, to destination: IndexPath
    ) {
        mutate { draft in
            let moved = draft.questions.remove(at: source.row)
            draft.questions.insert(moved, at: destination.row)
        }
        // Renumber once the drop animation is done.
        DispatchQueue.main.async { [weak self] in self?.reloadVisibleRows() }
    }

    override func tableView(
        _ tableView: UITableView,
        commit editingStyle: UITableViewCell.EditingStyle,
        forRowAt indexPath: IndexPath
    ) {
        switch editingStyle {
        case .delete:
            guard isQuestionRow(indexPath) else { return }
            mutate { $0.questions.remove(at: indexPath.row) }
            reloadVisibleRows()
        case .insert:
            addQuestion()
        default:
            break
        }
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        switch sections[indexPath.section] {
        case .details:
            break
        case .questions:
            if isQuestionRow(indexPath) {
                openQuestion(at: indexPath.row)
            } else {
                addQuestion()
            }
        case .delete:
            confirmDelete(from: tableView.cellForRow(at: indexPath))
        }
    }

    private func addQuestion() {
        guard let draft, draft.canAddQuestion else { return }
        let seconds = draft.commonSeconds
        mutate { $0.questions.append(QuestPollDraft.blankQuestion(seconds: seconds)) }
        reloadVisibleRows()
        openQuestion(at: draft.questions.count, focusPrompt: true)
    }

    private func openQuestion(at index: Int, focusPrompt: Bool = false) {
        guard let draft, draft.questions.indices.contains(index) else { return }
        view.endEditing(true)
        let editor = QuestPollQuestionEditorViewController(
            question: draft.questions[index],
            number: index + 1,
            isQuiz: draft.mode == .quiz,
            canDelete: draft.questions.count > 1
        )
        editor.focusesPromptOnAppear = focusPrompt
        editor.onChange = { [weak self] question in
            self?.mutate { draft in
                guard draft.questions.indices.contains(index) else { return }
                draft.questions[index] = question
            }
        }
        editor.onDelete = { [weak self] in
            self?.mutate { draft in
                guard draft.questions.indices.contains(index) else { return }
                draft.questions.remove(at: index)
            }
            self?.navigationController?.popViewController(animated: true)
        }
        navigationController?.pushViewController(editor, animated: true)
    }

    // MARK: - Text field

    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        textField.resignFirstResponder()
        return true
    }

    func textField(
        _ textField: UITextField,
        shouldChangeCharactersIn range: NSRange,
        replacementString string: String
    ) -> Bool {
        QuestPollEditorText.allows(
            current: textField.text ?? "", range: range, replacement: string,
            limit: QuestPollDraft.maxTitleCharacters
        )
    }

    // MARK: - Save / cancel / delete

    @objc private func saveTapped() {
        guard let draft, draft.problem == nil, !isWorking else { return }
        view.endEditing(true)
        let deck = draft.deck()
        let client = self.client
        setWorking(true)
        Task { @MainActor [weak self] in
            do {
                let saved = try await client.saveDeck(deck)
                self?.finishSave(saved, fallbackId: deck.id)
            } catch {
                self?.setWorking(false)
                self?.showFailure(
                    title: "Could Not Save",
                    message: Self.message(for: error, fallback: "Could not save this poll.")
                )
            }
        }
    }

    private func finishSave(_ saved: LivePollDeck, fallbackId: String?) {
        var stored = saved
        stored.id = saved.id ?? fallbackId
        if let id = stored.id {
            // Cards for this poll in Shows pick up the new name and length.
            LivePollStore.shared.refresh(from: [LivePollDeckSummary(
                id: id,
                title: stored.title,
                questionCount: stored.questions.count,
                mode: stored.mode
            )])
        }
        original = draft
        isWorking = false
        close { [onSaved] in onSaved?(stored) }
    }

    /// Closes the sheet, then runs `then` (callers may present or dismiss
    /// something themselves, which must wait for this sheet to be gone).
    private func close(then: @escaping () -> Void) {
        guard presentingViewController != nil else {
            then()
            return
        }
        dismiss(animated: true, completion: then)
    }

    private func setWorking(_ working: Bool) {
        isWorking = working
        if working {
            let spinner = UIActivityIndicatorView(style: .medium)
            spinner.startAnimating()
            navigationItem.rightBarButtonItem = UIBarButtonItem(customView: spinner)
        } else {
            navigationItem.rightBarButtonItem = UIBarButtonItem(
                barButtonSystemItem: .save, target: self, action: #selector(saveTapped)
            )
            navigationItem.rightBarButtonItem?.accessibilityIdentifier = "questpoll.editor.save"
        }
        updateChrome()
    }

    @objc private func cancelTapped() {
        guard isDirty else {
            dismiss(animated: true)
            return
        }
        confirmDiscard()
    }

    func presentationControllerDidAttemptToDismiss(_ presentationController: UIPresentationController) {
        guard isDirty, !isWorking else { return }
        confirmDiscard()
    }

    private func confirmDiscard() {
        view.endEditing(true)
        let sheet = UIAlertController(
            title: nil,
            message: "Your changes to this \(draft?.noun ?? "poll") have not been saved.",
            preferredStyle: .actionSheet
        )
        sheet.addAction(UIAlertAction(title: "Discard Changes", style: .destructive) {
            [weak self] _ in
            self?.dismiss(animated: true)
        })
        sheet.addAction(UIAlertAction(title: "Keep Editing", style: .cancel))
        sheet.popoverPresentationController?.barButtonItem = navigationItem.leftBarButtonItem
        present(sheet, animated: true)
    }

    private func confirmDelete(from source: UIView?) {
        guard let draft, let pollId = draft.id else { return }
        let alert = UIAlertController(
            title: draft.mode == .quiz ? "Delete Quiz?" : "Delete Poll?",
            message: Self.deleteMessage(
                title: original?.title ?? draft.title,
                cardsUsingIt: LivePollStore.shared.polls.filter { $0.pollId == pollId }.count
            ),
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(UIAlertAction(title: "Delete", style: .destructive) { [weak self] _ in
            self?.delete(pollId: pollId)
        })
        present(alert, animated: true)
    }

    /// What deleting costs, including the Show cards that point at this poll.
    static func deleteMessage(title: String, cardsUsingIt: Int) -> String {
        let name = title.trimmingCharacters(in: .whitespacesAndNewlines)
        var message = "\(name.isEmpty ? "This poll" : "“\(name)”") is removed from your "
            + "Eclipse Polls account, on every device. This cannot be undone."
        if cardsUsingIt > 0 {
            let cards = cardsUsingIt == 1 ? "1 card" : "\(cardsUsingIt) cards"
            let verb = cardsUsingIt == 1 ? "uses" : "use"
            message += " \(cards) in your Shows \(verb) it and will need another poll chosen."
        }
        return message
    }

    private func delete(pollId: String) {
        let client = self.client
        setWorking(true)
        Task { @MainActor [weak self] in
            do {
                try await client.deleteDeck(id: pollId)
                self?.isWorking = false
                self?.original = self?.draft
                let onDeleted = self?.onDeleted
                self?.close { onDeleted?(pollId) }
            } catch {
                self?.setWorking(false)
                self?.showFailure(
                    title: "Could Not Delete",
                    message: Self.message(for: error, fallback: "Could not delete this poll.")
                )
            }
        }
    }

    private func showFailure(title: String, message: String) {
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        present(alert, animated: true)
    }

    private static func message(for error: Error, fallback: String) -> String {
        (error as? LivePollError)?.userMessage ?? fallback
    }
}
