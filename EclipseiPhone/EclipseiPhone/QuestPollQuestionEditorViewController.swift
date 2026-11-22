//
//  QuestPollQuestionEditorViewController.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import UIKit

/// One question of a poll: its text, two to five answers, and how long people
/// get. In a quiz each answer has a round mark for choosing the right one.
///
/// Every change is handed straight back through `onChange`; the poll editor
/// behind this screen owns the draft and does the saving.
final class QuestPollQuestionEditorViewController: UITableViewController, UITextFieldDelegate {

    var onChange: ((QuestPollDraft.Question) -> Void)?
    var onDelete: (() -> Void)?
    /// Puts the cursor in the question text when the screen opens (new question).
    var focusesPromptOnAppear = false

    private(set) var question: QuestPollDraft.Question
    private let isQuiz: Bool
    private let canDelete: Bool

    private enum Section { case prompt, answers, time, delete }

    private var sections: [Section] {
        canDelete ? [.prompt, .answers, .time, .delete] : [.prompt, .answers, .time]
    }

    private var answersSection: Int { sections.firstIndex(of: .answers) ?? 1 }
    private var canAddAnswer: Bool { question.options.count < QuestPollDraft.maxOptions }
    private var canRemoveAnswer: Bool { question.options.count > QuestPollDraft.minOptions }

    init(question: QuestPollDraft.Question, number: Int, isQuiz: Bool, canDelete: Bool) {
        var padded = question
        // Always at least two answer rows to type into.
        while padded.options.count < QuestPollDraft.minOptions { padded.options.append("") }
        self.question = padded
        self.isQuiz = isQuiz
        self.canDelete = canDelete
        super.init(style: .insetGrouped)
        title = "Question \(number)"
    }

    required init?(coder: NSCoder) { nil }

    override func viewDidLoad() {
        super.viewDidLoad()
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "cell")
        tableView.register(
            QuestPollTextFieldCell.self,
            forCellReuseIdentifier: QuestPollTextFieldCell.reuseIdentifier
        )
        tableView.register(
            QuestPollTextViewCell.self,
            forCellReuseIdentifier: QuestPollTextViewCell.reuseIdentifier
        )
        tableView.isEditing = true
        tableView.allowsSelectionDuringEditing = true
        tableView.keyboardDismissMode = .interactive
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        guard focusesPromptOnAppear else { return }
        focusesPromptOnAppear = false
        let cell = tableView.cellForRow(at: IndexPath(row: 0, section: 0)) as? QuestPollTextViewCell
        cell?.textView.becomeFirstResponder()
    }

    private func changed() {
        onChange?(question)
    }

    // MARK: - Table

    override func numberOfSections(in tableView: UITableView) -> Int {
        sections.count
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        switch sections[section] {
        case .prompt, .time, .delete: return 1
        case .answers: return question.options.count + (canAddAnswer ? 1 : 0)
        }
    }

    override func tableView(
        _ tableView: UITableView, titleForHeaderInSection section: Int
    ) -> String? {
        switch sections[section] {
        case .prompt: return "Question"
        case .answers: return "Answers"
        case .time, .delete: return nil
        }
    }

    override func tableView(
        _ tableView: UITableView, titleForFooterInSection section: Int
    ) -> String? {
        guard sections[section] == .answers else { return nil }
        let range = "Two to five answers."
        return isQuiz ? "\(range) Tap the circle beside the right one." : range
    }

    override func tableView(
        _ tableView: UITableView, cellForRowAt indexPath: IndexPath
    ) -> UITableViewCell {
        switch sections[indexPath.section] {
        case .prompt:
            let cell = tableView.dequeueReusableCell(
                withIdentifier: QuestPollTextViewCell.reuseIdentifier, for: indexPath
            ) as? QuestPollTextViewCell ?? QuestPollTextViewCell()
            cell.placeholder = "What do you want to ask?"
            cell.maxCharacters = QuestPollDraft.maxPromptCharacters
            cell.text = question.prompt
            cell.textView.accessibilityIdentifier = "questpoll.question.prompt"
            cell.onTextChange = { [weak self] text in
                guard let self else { return }
                self.question.prompt = text
                self.changed()
                // Let the row grow with the text.
                UIView.performWithoutAnimation {
                    self.tableView.beginUpdates()
                    self.tableView.endUpdates()
                }
            }
            return cell
        case .answers:
            return answerCell(at: indexPath)
        case .time:
            let cell = plainCell(at: indexPath)
            cell.selectionStyle = .none
            var content = cell.defaultContentConfiguration()
            content.text = "Time to Answer"
            cell.contentConfiguration = content
            let menu = QuestPollEditorControls.timeMenu(
                current: question.seconds, including: question.seconds
            ) { [weak self] seconds in
                guard let self else { return }
                self.question.seconds = seconds
                self.changed()
                self.tableView.reloadRows(at: [indexPath], with: .none)
            }
            cell.editingAccessoryView = QuestPollEditorControls.menuButton(
                title: QuestPollDraft.timeLabel(question.seconds), menu: menu
            )
            return cell
        case .delete:
            let cell = plainCell(at: indexPath)
            var content = cell.defaultContentConfiguration()
            content.text = "Delete Question"
            content.textProperties.color = .systemRed
            content.textProperties.alignment = .center
            cell.contentConfiguration = content
            return cell
        }
    }

    private func plainCell(at indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "cell", for: indexPath)
        cell.editingAccessoryView = nil
        cell.selectionStyle = .default
        cell.accessibilityIdentifier = nil
        return cell
    }

    private func answerCell(at indexPath: IndexPath) -> UITableViewCell {
        guard question.options.indices.contains(indexPath.row) else {
            let cell = plainCell(at: indexPath)
            var content = cell.defaultContentConfiguration()
            content.text = "Add Answer"
            content.textProperties.color = .tintColor
            cell.contentConfiguration = content
            cell.accessibilityIdentifier = "questpoll.question.addAnswer"
            return cell
        }
        let row = indexPath.row
        let cell = tableView.dequeueReusableCell(
            withIdentifier: QuestPollTextFieldCell.reuseIdentifier, for: indexPath
        ) as? QuestPollTextFieldCell ?? QuestPollTextFieldCell()
        cell.textField.placeholder = "Answer \(row + 1)"
        cell.textField.text = question.options[row]
        cell.textField.returnKeyType = .next
        cell.textField.delegate = self
        cell.textField.tag = row
        cell.textField.accessibilityIdentifier = "questpoll.question.answer.\(row + 1)"
        cell.setMark(isQuiz ? question.correctIndex == row : nil)
        cell.onTextChange = { [weak self] text in
            guard let self, self.question.options.indices.contains(row) else { return }
            self.question.options[row] = text
            self.changed()
        }
        cell.onMarkTapped = { [weak self] in
            self?.markRightAnswer(row)
        }
        return cell
    }

    private func markRightAnswer(_ row: Int) {
        question.correctIndex = row
        changed()
        for case let cell as QuestPollTextFieldCell in tableView.visibleCells {
            guard let path = tableView.indexPath(for: cell), path.section == answersSection,
                  question.options.indices.contains(path.row) else { continue }
            cell.setMark(path.row == row)
        }
    }

    private func reloadAnswers() {
        UIView.performWithoutAnimation {
            tableView.reloadSections(IndexSet(integer: answersSection), with: .none)
        }
    }

    // MARK: - Rows: delete, add, reorder

    private func isAnswerRow(_ indexPath: IndexPath) -> Bool {
        sections[indexPath.section] == .answers && question.options.indices.contains(indexPath.row)
    }

    override func tableView(
        _ tableView: UITableView, editingStyleForRowAt indexPath: IndexPath
    ) -> UITableViewCell.EditingStyle {
        guard sections[indexPath.section] == .answers else { return .none }
        if !isAnswerRow(indexPath) { return .insert }
        return canRemoveAnswer ? .delete : .none
    }

    override func tableView(
        _ tableView: UITableView, shouldIndentWhileEditingRowAt indexPath: IndexPath
    ) -> Bool {
        sections[indexPath.section] == .answers
    }

    override func tableView(_ tableView: UITableView, canMoveRowAt indexPath: IndexPath) -> Bool {
        isAnswerRow(indexPath)
    }

    override func tableView(
        _ tableView: UITableView,
        targetIndexPathForMoveFromRowAt source: IndexPath,
        toProposedIndexPath proposed: IndexPath
    ) -> IndexPath {
        let last = question.options.count - 1
        if proposed.section < source.section { return IndexPath(row: 0, section: source.section) }
        if proposed.section > source.section { return IndexPath(row: last, section: source.section) }
        return IndexPath(row: min(proposed.row, last), section: source.section)
    }

    override func tableView(
        _ tableView: UITableView, moveRowAt source: IndexPath, to destination: IndexPath
    ) {
        question = Self.movingAnswer(in: question, from: source.row, to: destination.row)
        changed()
        DispatchQueue.main.async { [weak self] in self?.reloadAnswers() }
    }

    override func tableView(
        _ tableView: UITableView,
        commit editingStyle: UITableViewCell.EditingStyle,
        forRowAt indexPath: IndexPath
    ) {
        switch editingStyle {
        case .delete:
            guard isAnswerRow(indexPath), canRemoveAnswer else { return }
            view.endEditing(true)
            question = Self.removingAnswer(in: question, at: indexPath.row)
            changed()
            reloadAnswers()
        case .insert:
            addAnswer()
        default:
            break
        }
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        switch sections[indexPath.section] {
        case .answers:
            if !isAnswerRow(indexPath) { addAnswer() }
        case .delete:
            onDelete?()
        case .prompt, .time:
            break
        }
    }

    private func addAnswer() {
        guard canAddAnswer else { return }
        question.options.append("")
        changed()
        reloadAnswers()
        focusAnswer(question.options.count - 1)
    }

    private func focusAnswer(_ row: Int) {
        let path = IndexPath(row: row, section: answersSection)
        tableView.scrollToRow(at: path, at: .none, animated: false)
        DispatchQueue.main.async { [weak self] in
            let cell = self?.tableView.cellForRow(at: path) as? QuestPollTextFieldCell
            cell?.textField.becomeFirstResponder()
        }
    }

    // MARK: - Answer list changes (the right-answer mark follows its answer)

    static func movingAnswer(
        in question: QuestPollDraft.Question, from source: Int, to destination: Int
    ) -> QuestPollDraft.Question {
        guard question.options.indices.contains(source),
              question.options.indices.contains(destination) else { return question }
        var result = question
        var marks = question.options.indices.map { $0 == question.correctIndex }
        result.options.insert(result.options.remove(at: source), at: destination)
        marks.insert(marks.remove(at: source), at: destination)
        result.correctIndex = marks.firstIndex(of: true)
        return result
    }

    static func removingAnswer(
        in question: QuestPollDraft.Question, at row: Int
    ) -> QuestPollDraft.Question {
        guard question.options.indices.contains(row) else { return question }
        var result = question
        var marks = question.options.indices.map { $0 == question.correctIndex }
        result.options.remove(at: row)
        marks.remove(at: row)
        result.correctIndex = marks.firstIndex(of: true)
        return result
    }

    // MARK: - Text field

    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        let next = textField.tag + 1
        if question.options.indices.contains(next) {
            focusAnswer(next)
        } else if canAddAnswer,
                  !(textField.text ?? "").trimmingCharacters(in: .whitespaces).isEmpty {
            addAnswer()
        } else {
            textField.resignFirstResponder()
        }
        return false
    }

    func textField(
        _ textField: UITextField,
        shouldChangeCharactersIn range: NSRange,
        replacementString string: String
    ) -> Bool {
        QuestPollEditorText.allows(
            current: textField.text ?? "", range: range, replacement: string,
            limit: QuestPollDraft.maxOptionCharacters
        )
    }
}
