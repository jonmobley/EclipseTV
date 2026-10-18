//
//  QuestPollQAViewController.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import LivePollKit
import UIKit

/// Question list for a live Audience Q&A room (the Q&A version of Controls).
///
/// Same steps as the Mac's Q&A sidebar: tap a question to put it on screen,
/// Done takes it down (back to the join code), swipe to Hide, and shown
/// questions can go up again. A dot marks questions new since the list was
/// last open.
final class QuestPollQAViewController: UITableViewController {

    /// Host command to send (`qaFeature`, `qaDone`, `qaHide`, `qaRestore`).
    var onCommand: ((LivePollHostCommand) -> Void)?
    /// Ends the room after the host confirms.
    var onEnd: (() -> Void)?

    private enum Section: Int, CaseIterable {
        case onScreen, new, shown, hidden

        var title: String? {
            switch self {
            case .onScreen: return "On Screen"
            case .new: return "New"
            case .shown: return "Shown"
            case .hidden: return "Hidden"
            }
        }
    }

    private var featured: LivePollQAFeatured?
    private var rows: [Section: [LivePollQAQuestion]] = [:]
    private var newSinceLastLook: Set<String> = []
    private var storeObserver: NSObjectProtocol?

    init() {
        super.init(style: .insetGrouped)
    }

    required init?(coder: NSCoder) { nil }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Questions"
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "q")
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            systemItem: .close,
            primaryAction: UIAction { [weak self] _ in self?.dismiss(animated: true) }
        )
        navigationItem.leftBarButtonItem = UIBarButtonItem(
            title: "End",
            primaryAction: UIAction { [weak self] _ in self?.onEnd?() }
        )
        navigationItem.leftBarButtonItem?.tintColor = .systemRed
        toolbarItems = [
            UIBarButtonItem(systemItem: .flexibleSpace),
            UIBarButtonItem(
                title: "Join Code & Link",
                image: UIImage(systemName: "qrcode"),
                primaryAction: UIAction { [weak self] _ in self?.presentJoinQR() }
            ),
            UIBarButtonItem(systemItem: .flexibleSpace)
        ]
        refresh()
        storeObserver = NotificationCenter.default.addObserver(
            forName: QuestPollSessionStore.didChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.refresh()
        }
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        navigationController?.setToolbarHidden(false, animated: false)
    }

    deinit {
        if let storeObserver {
            NotificationCenter.default.removeObserver(storeObserver)
        }
    }

    // MARK: - Data

    private func refresh() {
        let store = QuestPollSessionStore.shared
        guard let session = store.session, session.mode == .qa else {
            dismiss(animated: true)
            return
        }
        let questions = session.qa?.questions ?? []
        featured = session.qa?.featured
        rows = [
            .new: questions.filter { $0.status == .new },
            .shown: questions.filter { $0.status == .answered },
            .hidden: questions.filter { $0.status == .hidden }
        ]
        newSinceLastLook.formUnion(
            questions
                .filter { $0.status == .new && !store.seenQAQuestionIds.contains($0.id) }
                .map(\.id)
        )
        store.markQAQuestionsSeen()
        let count = session.qa?.count ?? questions.count
        navigationItem.prompt = "Code \(session.code) · \(count) question\(count == 1 ? "" : "s")"
        tableView.reloadData()
    }

    private func questions(in section: Section) -> [LivePollQAQuestion] {
        rows[section] ?? []
    }

    // MARK: - Table

    override func numberOfSections(in tableView: UITableView) -> Int {
        Section.allCases.count
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        guard let kind = Section(rawValue: section) else { return 0 }
        switch kind {
        case .onScreen: return 1
        case .new: return max(questions(in: .new).count, 1)
        case .shown, .hidden: return questions(in: kind).count
        }
    }

    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        guard let kind = Section(rawValue: section) else { return nil }
        if kind == .shown || kind == .hidden, questions(in: kind).isEmpty { return nil }
        return kind.title
    }

    override func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? {
        guard Section(rawValue: section) == .new, !questions(in: .new).isEmpty else { return nil }
        return "Tap a question to put it on screen. Swipe to hide it."
    }

    override func tableView(
        _ tableView: UITableView, cellForRowAt indexPath: IndexPath
    ) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "q", for: indexPath)
        var config = cell.defaultContentConfiguration()
        config.textProperties.numberOfLines = 0
        cell.accessoryView = nil
        cell.accessoryType = .none
        cell.selectionStyle = .default
        let kind = Section(rawValue: indexPath.section) ?? .new
        switch kind {
        case .onScreen:
            if let featured {
                config.text = featured.text
                config.secondaryText = featured.from ?? "Anonymous"
                cell.accessoryView = doneButton()
                cell.selectionStyle = .none
            } else {
                config.text = "Join code and QR"
                config.secondaryText = "Tap a question below to show it instead."
                config.image = UIImage(systemName: "qrcode")
                cell.selectionStyle = .none
            }
        case .new where questions(in: .new).isEmpty:
            config.text = "No new questions yet"
            config.secondaryText = "People join with the code on screen and type a question."
            config.textProperties.color = .secondaryLabel
            cell.selectionStyle = .none
        case .new, .shown, .hidden:
            let question = questions(in: kind)[indexPath.row]
            config.text = question.text
            config.secondaryText = question.from ?? "Anonymous"
            if kind == .new, newSinceLastLook.contains(question.id) {
                config.image = UIImage(systemName: "circle.fill")
                config.imageProperties.tintColor = .tintColor
                config.imageProperties.maximumSize = CGSize(width: 8, height: 8)
            }
            if kind != .new {
                config.textProperties.color = .secondaryLabel
            }
        }
        cell.contentConfiguration = config
        return cell
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        guard let kind = Section(rawValue: indexPath.section),
              kind != .onScreen,
              questions(in: kind).indices.contains(indexPath.row) else { return }
        let question = questions(in: kind)[indexPath.row]
        if kind == .hidden {
            onCommand?(.qaRestore(id: question.id))
        } else {
            onCommand?(.qaFeature(id: question.id))
            Haptics.impactLight()
        }
    }

    override func tableView(
        _ tableView: UITableView,
        trailingSwipeActionsConfigurationForRowAt indexPath: IndexPath
    ) -> UISwipeActionsConfiguration? {
        guard let kind = Section(rawValue: indexPath.section),
              kind == .new || kind == .shown,
              questions(in: kind).indices.contains(indexPath.row) else { return nil }
        let question = questions(in: kind)[indexPath.row]
        let hide = UIContextualAction(style: .destructive, title: "Hide") { [weak self] _, _, done in
            self?.onCommand?(.qaHide(id: question.id))
            done(true)
        }
        return UISwipeActionsConfiguration(actions: [hide])
    }

    // MARK: - Actions

    private func doneButton() -> UIButton {
        var config = UIButton.Configuration.filled()
        config.title = "Done"
        config.cornerStyle = .capsule
        config.buttonSize = .small
        let button = UIButton(configuration: config, primaryAction: UIAction { [weak self] _ in
            self?.onCommand?(.qaDone)
        })
        button.accessibilityHint = "Takes the question off screen and shows the join code"
        button.sizeToFit()
        return button
    }

    private func presentJoinQR() {
        guard let code = QuestPollSessionStore.shared.session?.code else { return }
        let sheet = QuestPollJoinQRViewController(code: code, joinURL: QuestPollConfig.joinURL(code: code))
        let nav = UINavigationController(rootViewController: sheet)
        nav.modalPresentationStyle = .formSheet
        present(nav, animated: true)
    }

    // MARK: - Presentation

    /// Half-height sheet that leaves the live preview visible, like Controls.
    static func makeNavigation(
        onCommand: ((LivePollHostCommand) -> Void)?,
        onEnd: (() -> Void)?
    ) -> UINavigationController {
        let list = QuestPollQAViewController()
        list.onCommand = onCommand
        let nav = UINavigationController(rootViewController: list)
        list.onEnd = { [weak nav] in
            nav?.dismiss(animated: true, completion: onEnd)
        }
        nav.modalPresentationStyle = .pageSheet
        if let sheet = nav.sheetPresentationController {
            sheet.detents = [.medium(), .large()]
            sheet.selectedDetentIdentifier = .medium
            sheet.largestUndimmedDetentIdentifier = .medium
            sheet.prefersGrabberVisible = true
            sheet.prefersEdgeAttachedInCompactHeight = true
        }
        return nav
    }
}
