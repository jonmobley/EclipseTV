//
//  QuestPollPINViewController.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import UIKit

/// Form-sheet host PIN with an in-sheet pad (iPad's system number pad floats).
final class QuestPollPINViewController: UIViewController {

    /// Called after a verified PIN is stored in the Keychain.
    var onLinked: (() -> Void)?

    private let client: QuestPollClient
    private var pin = ""
    private var isBusy = false

    private let pinLabel = UILabel()
    private let errorLabel = UILabel()
    private let linkButton = UIButton(type: .system)
    private let pad = UIStackView()

    /// Compact card so the pad stays with the sheet on large iPads.
    static let sheetSize = CGSize(width: 420, height: 560)

    /// - Parameter client: Injected for tests; production talks to questpoll.live.
    init(client: QuestPollClient = QuestPollClient()) {
        self.client = client
        super.init(nibName: nil, bundle: nil)
        preferredContentSize = Self.sheetSize
    }

    required init?(coder: NSCoder) { nil }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "QuestPoll"
        view.backgroundColor = .systemGroupedBackground
        navigationItem.leftBarButtonItem = UIBarButtonItem(
            barButtonSystemItem: .close,
            target: self,
            action: #selector(closeTapped)
        )
        buildLayout()
        refresh()
    }

    // MARK: - Layout

    private func buildLayout() {
        let scroll = UIScrollView()
        scroll.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(scroll)

        let stack = UIStackView(arrangedSubviews: [
            makeMessageLabel(), pinLabel, errorLabel, makePad(), linkButton
        ])
        stack.axis = .vertical
        stack.spacing = 16
        stack.translatesAutoresizingMaskIntoConstraints = false
        scroll.addSubview(stack)

        stylePinLabel()
        styleErrorLabel()
        styleLinkButton()
        let guide = scroll.contentLayoutGuide
        let frame = scroll.frameLayoutGuide
        NSLayoutConstraint.activate([
            scroll.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            scroll.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scroll.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            stack.topAnchor.constraint(equalTo: guide.topAnchor, constant: 12),
            stack.leadingAnchor.constraint(equalTo: guide.leadingAnchor, constant: 20),
            stack.trailingAnchor.constraint(equalTo: guide.trailingAnchor, constant: -20),
            stack.bottomAnchor.constraint(equalTo: guide.bottomAnchor, constant: -24),
            stack.widthAnchor.constraint(equalTo: frame.widthAnchor, constant: -40),
            pinLabel.heightAnchor.constraint(equalToConstant: 52),
            linkButton.heightAnchor.constraint(equalToConstant: 52)
        ])
    }

    private func makeMessageLabel() -> UILabel {
        let label = UILabel()
        label.text = "Enter the host PIN so Eclipse can run your live polls."
        label.font = .systemFont(ofSize: 15)
        label.textColor = .secondaryLabel
        label.numberOfLines = 0
        return label
    }

    private func stylePinLabel() {
        pinLabel.font = .monospacedDigitSystemFont(ofSize: 28, weight: .semibold)
        pinLabel.textAlignment = .center
        pinLabel.backgroundColor = .secondarySystemGroupedBackground
        pinLabel.layer.cornerRadius = 12
        pinLabel.layer.masksToBounds = true
        pinLabel.accessibilityIdentifier = "questpoll.pin.display"
    }

    private func styleErrorLabel() {
        errorLabel.font = .systemFont(ofSize: 14, weight: .medium)
        errorLabel.textColor = .systemRed
        errorLabel.numberOfLines = 0
        errorLabel.textAlignment = .center
        errorLabel.isHidden = true
    }

    private func styleLinkButton() {
        var config = UIButton.Configuration.filled()
        config.title = "Link"
        config.cornerStyle = .large
        config.titleTextAttributesTransformer =
            UIConfigurationTextAttributesTransformer { incoming in
                var attrs = incoming
                attrs.font = .systemFont(ofSize: 17, weight: .semibold)
                return attrs
            }
        linkButton.configuration = config
        linkButton.addAction(UIAction { [weak self] _ in
            self?.linkTapped()
        }, for: .touchUpInside)
    }

    private func makePad() -> UIView {
        pad.axis = .vertical
        pad.spacing = 10
        pad.accessibilityIdentifier = "questpoll.pin.pad"
        let rows: [[String]] = [
            ["1", "2", "3"],
            ["4", "5", "6"],
            ["7", "8", "9"],
            ["", "0", "delete"]
        ]
        for keys in rows {
            pad.addArrangedSubview(makePadRow(keys))
        }
        return pad
    }

    private func makePadRow(_ keys: [String]) -> UIStackView {
        let row = UIStackView()
        row.axis = .horizontal
        row.spacing = 10
        row.distribution = .fillEqually
        for key in keys {
            row.addArrangedSubview(makePadKey(key))
        }
        return row
    }

    private func makePadKey(_ key: String) -> UIView {
        if key.isEmpty {
            let spacer = UIView()
            spacer.isAccessibilityElement = false
            return spacer
        }
        var config = UIButton.Configuration.gray()
        config.cornerStyle = .large
        if key == "delete" {
            config.image = UIImage(systemName: "delete.backward")
        } else {
            config.title = key
            config.titleTextAttributesTransformer =
                UIConfigurationTextAttributesTransformer { incoming in
                    var attrs = incoming
                    attrs.font = .systemFont(ofSize: 22, weight: .semibold)
                    return attrs
                }
        }
        let button = UIButton(type: .system)
        button.configuration = config
        button.accessibilityIdentifier = "questpoll.pin.key.\(key)"
        if key == "delete" { button.accessibilityLabel = "Delete" }
        button.addAction(UIAction { [weak self] _ in
            self?.handleKey(key)
        }, for: .touchUpInside)
        button.heightAnchor.constraint(equalToConstant: 56).isActive = true
        return button
    }

    // MARK: - Actions

    @objc private func closeTapped() {
        dismiss(animated: true)
    }

    private func handleKey(_ key: String) {
        guard !isBusy else { return }
        errorLabel.text = nil
        if key == "delete" {
            if !pin.isEmpty { pin.removeLast() }
        } else if key.count == 1, key.first?.isNumber == true, pin.count < 12 {
            pin.append(key)
        }
        refresh()
    }

    private func linkTapped() {
        let trimmed = pin.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !isBusy else { return }
        setBusy(true)
        Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                try await self.client.verifyPIN(trimmed)
                QuestPollAccount.shared.link(pin: trimmed)
                self.onLinked?()
            } catch {
                self.errorLabel.text = (error as? QuestPollError)?.userMessage
                    ?? "Could not verify the PIN."
                self.setBusy(false)
            }
        }
    }

    private func setBusy(_ busy: Bool) {
        isBusy = busy
        pad.isUserInteractionEnabled = !busy
        refresh()
    }

    private func refresh() {
        let empty = pin.isEmpty
        pinLabel.text = empty ? "Host PIN" : String(repeating: "•", count: pin.count)
        pinLabel.textColor = empty ? .placeholderText : .label
        linkButton.isEnabled = !empty && !isBusy
        errorLabel.isHidden = (errorLabel.text ?? "").isEmpty
        if var config = linkButton.configuration {
            config.title = isBusy ? "Linking…" : "Link"
            linkButton.configuration = config
        }
    }
}
