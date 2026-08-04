//
//  AddWebsiteViewController.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import UIKit

/// Compose-first Website add: URL + Title, with History suggestions as you type.
final class AddWebsiteViewController: UITableViewController, UITextFieldDelegate {

    /// When set, Add / a suggestion joins this Show as a card.
    private let targetShowId: UUID?

    private let urlField = UITextField()
    private let titleField = UITextField()
    private var suggestions: [WebPage] = []
    private var addButton: UIBarButtonItem!

    private enum Section: Int, CaseIterable {
        case fields
        case suggestions
    }

    private enum FieldRow: Int, CaseIterable {
        case url
        case title
    }

    // MARK: - Lifecycle

    /// - Parameter targetShowId: Show that receives the card, or `nil` for History only.
    init(targetShowId: UUID? = nil) {
        self.targetShowId = targetShowId
        super.init(style: .insetGrouped)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Add Website"
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "field")
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "suggestion")
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
        // Trailing-most first: Add, then History.
        navigationItem.rightBarButtonItems = [
            addButton,
            UIBarButtonItem(
                title: "History",
                style: .plain,
                target: self,
                action: #selector(historyTapped)
            )
        ]

        configure(urlField, placeholder: "example.com", url: true)
        configure(titleField, placeholder: "Title (optional)", url: false)
        urlField.becomeFirstResponder()
        refreshSuggestions()
        updateAddEnabled()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        if !urlField.isFirstResponder {
            urlField.becomeFirstResponder()
        }
    }

    // MARK: - Actions

    @objc private func addTapped() {
        commit(title: titleField.text ?? "", urlString: urlField.text ?? "")
    }

    @objc private func historyTapped() {
        if let nav = navigationController,
           let existing = nav.viewControllers
            .compactMap({ $0 as? WebPagesViewController }).last {
            nav.popToViewController(existing, animated: true)
            return
        }
        let history = WebPagesViewController(targetShowId: targetShowId)
        navigationController?.pushViewController(history, animated: true)
    }

    @objc private func fieldEditingChanged() {
        refreshSuggestions()
        updateAddEnabled()
    }

    private func commit(title: String, urlString: String) {
        do {
            let page = try WebPageStore.shared.addOrReuse(
                title: title,
                urlString: urlString
            )
            if let showId = targetShowId {
                LocalAlbumStore.shared.add(
                    itemId: page.id.uuidString,
                    toAlbumId: showId
                )
            }
            dismiss(animated: true)
        } catch {
            let alert = UIAlertController(
                title: "Couldn't Add Website",
                message: error.localizedDescription,
                preferredStyle: .alert
            )
            alert.addAction(UIAlertAction(title: "OK", style: .default))
            present(alert, animated: true)
        }
    }

    private func selectSuggestion(_ page: WebPage) {
        WebPageStore.shared.touch(page.id)
        if let showId = targetShowId {
            LocalAlbumStore.shared.add(
                itemId: page.id.uuidString,
                toAlbumId: showId
            )
        }
        dismiss(animated: true)
    }

    // MARK: - Table

    override func numberOfSections(in tableView: UITableView) -> Int {
        Section.allCases.count
    }

    override func tableView(
        _ tableView: UITableView,
        numberOfRowsInSection section: Int
    ) -> Int {
        switch Section(rawValue: section) {
        case .fields: return FieldRow.allCases.count
        case .suggestions: return suggestions.count
        case .none: return 0
        }
    }

    override func tableView(
        _ tableView: UITableView,
        titleForHeaderInSection section: Int
    ) -> String? {
        Section(rawValue: section) == .suggestions && !suggestions.isEmpty
            ? "History"
            : nil
    }

    override func tableView(
        _ tableView: UITableView,
        titleForFooterInSection section: Int
    ) -> String? {
        guard Section(rawValue: section) == .fields else { return nil }
        return targetShowId == nil
            ? "Saved sites show up here as you type."
            : "Adds a website card to this Show. Matching History fills in as you type."
    }

    override func tableView(
        _ tableView: UITableView,
        cellForRowAt indexPath: IndexPath
    ) -> UITableViewCell {
        switch Section(rawValue: indexPath.section) {
        case .fields:
            let cell = tableView.dequeueReusableCell(
                withIdentifier: "field", for: indexPath
            )
            cell.selectionStyle = .none
            let field = FieldRow(rawValue: indexPath.row) == .url ? urlField : titleField
            install(field, in: cell)
            return cell
        case .suggestions:
            let cell = tableView.dequeueReusableCell(
                withIdentifier: "suggestion", for: indexPath
            )
            let page = suggestions[indexPath.row]
            var config = cell.defaultContentConfiguration()
            config.text = page.title
            config.secondaryText = page.url.host ?? page.url.absoluteString
            config.image = UIImage(systemName: "clock.arrow.circlepath")
            cell.contentConfiguration = config
            cell.accessoryType = .disclosureIndicator
            cell.selectionStyle = .default
            return cell
        case .none:
            return UITableViewCell()
        }
    }

    override func tableView(
        _ tableView: UITableView,
        didSelectRowAt indexPath: IndexPath
    ) {
        tableView.deselectRow(at: indexPath, animated: true)
        guard Section(rawValue: indexPath.section) == .suggestions,
              suggestions.indices.contains(indexPath.row) else { return }
        selectSuggestion(suggestions[indexPath.row])
    }

    // MARK: - UITextFieldDelegate

    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        if textField === urlField {
            titleField.becomeFirstResponder()
        } else if addButton.isEnabled {
            addTapped()
        }
        return true
    }

    // MARK: - Private

    private func configure(_ field: UITextField, placeholder: String, url: Bool) {
        field.placeholder = placeholder
        field.clearButtonMode = .whileEditing
        field.autocapitalizationType = url ? .none : .words
        field.autocorrectionType = url ? .no : .default
        field.keyboardType = url ? .URL : .default
        field.textContentType = url ? .URL : .none
        field.returnKeyType = url ? .next : .done
        field.delegate = self
        field.addTarget(
            self,
            action: #selector(fieldEditingChanged),
            for: .editingChanged
        )
        if !url {
            UserDisplayName.configureTextField(field)
        }
    }

    private func install(_ field: UITextField, in cell: UITableViewCell) {
        field.removeFromSuperview()
        field.translatesAutoresizingMaskIntoConstraints = false
        cell.contentView.addSubview(field)
        NSLayoutConstraint.activate([
            field.leadingAnchor.constraint(
                equalTo: cell.contentView.layoutMarginsGuide.leadingAnchor
            ),
            field.trailingAnchor.constraint(
                equalTo: cell.contentView.layoutMarginsGuide.trailingAnchor
            ),
            field.topAnchor.constraint(
                equalTo: cell.contentView.topAnchor, constant: 12
            ),
            field.bottomAnchor.constraint(
                equalTo: cell.contentView.bottomAnchor, constant: -12
            )
        ])
    }

    private func refreshSuggestions() {
        let query = urlField.text ?? ""
        let titleQuery = titleField.text ?? ""
        let needle = query.isEmpty ? titleQuery : query
        let next = WebPageStore.shared.suggestions(
            matching: needle,
            excludingShowId: targetShowId
        )
        guard next != suggestions else { return }
        suggestions = next
        tableView.reloadSections(IndexSet(integer: Section.suggestions.rawValue), with: .fade)
    }

    private func updateAddEnabled() {
        let raw = urlField.text ?? ""
        addButton.isEnabled = !raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}
