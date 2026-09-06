//
//  LivePollSignInViewController.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import LivePollKit
import UIKit

/// Form-sheet email sign-in using the Live Poll device-flow magic link.
final class LivePollSignInViewController: UIViewController {

    /// Called after an account token is stored in the Keychain.
    var onSignedIn: (() -> Void)?

    private let client: LivePollClient
    private let showsMigrationMessage: Bool
    private var isBusy = false
    private var pollTask: Task<Void, Never>?

    private let messageLabel = UILabel()
    private let emailField = UITextField()
    private let errorLabel = UILabel()
    private let sendButton = UIButton(type: .system)
    private let statusLabel = UILabel()

    /// Compact card matching the old PIN sheet footprint.
    static let sheetSize = CGSize(width: 420, height: 420)

    /// - Parameters:
    ///   - client: Injected for tests; production talks to quest.eclipseapp.com.
    ///   - showsMigrationMessage: True when a leftover host PIN was cleared.
    init(
        client: LivePollClient = LivePollAccountStore.client(),
        showsMigrationMessage: Bool = false
    ) {
        self.client = client
        self.showsMigrationMessage = showsMigrationMessage
        super.init(nibName: nil, bundle: nil)
        preferredContentSize = Self.sheetSize
    }

    required init?(coder: NSCoder) { nil }

    deinit {
        pollTask?.cancel()
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Live Poll"
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

        messageLabel.text = showsMigrationMessage
            ? "Host PIN sign-in has been replaced. Sign in with the email for your Live Poll account."
            : "Sign in with the email you use on the Live Poll web editor."
        messageLabel.font = .systemFont(ofSize: 15)
        messageLabel.textColor = .secondaryLabel
        messageLabel.numberOfLines = 0

        emailField.placeholder = "you@example.com"
        emailField.keyboardType = .emailAddress
        emailField.textContentType = .emailAddress
        emailField.autocapitalizationType = .none
        emailField.autocorrectionType = .no
        emailField.borderStyle = .roundedRect
        emailField.font = .systemFont(ofSize: 17)
        emailField.accessibilityIdentifier = "livepoll.signin.email"
        emailField.addAction(UIAction { [weak self] _ in
            self?.refresh()
        }, for: .editingChanged)

        errorLabel.font = .systemFont(ofSize: 14, weight: .medium)
        errorLabel.textColor = .systemRed
        errorLabel.numberOfLines = 0
        errorLabel.textAlignment = .center
        errorLabel.isHidden = true

        statusLabel.font = .systemFont(ofSize: 14)
        statusLabel.textColor = .secondaryLabel
        statusLabel.numberOfLines = 0
        statusLabel.textAlignment = .center
        statusLabel.isHidden = true

        var config = UIButton.Configuration.filled()
        config.title = "Email me a link"
        config.cornerStyle = .large
        config.titleTextAttributesTransformer =
            UIConfigurationTextAttributesTransformer { incoming in
                var attrs = incoming
                attrs.font = .systemFont(ofSize: 17, weight: .semibold)
                return attrs
            }
        sendButton.configuration = config
        sendButton.addAction(UIAction { [weak self] _ in
            self?.sendTapped()
        }, for: .touchUpInside)

        let stack = UIStackView(arrangedSubviews: [
            messageLabel, emailField, errorLabel, sendButton, statusLabel
        ])
        stack.axis = .vertical
        stack.spacing = 16
        stack.translatesAutoresizingMaskIntoConstraints = false
        scroll.addSubview(stack)

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
            emailField.heightAnchor.constraint(equalToConstant: 44),
            sendButton.heightAnchor.constraint(equalToConstant: 52)
        ])
    }

    // MARK: - Actions

    @objc private func closeTapped() {
        pollTask?.cancel()
        dismiss(animated: true)
    }

    private func sendTapped() {
        let email = (emailField.text ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !email.isEmpty, !isBusy else { return }
        setBusy(true)
        errorLabel.text = nil
        statusLabel.text = "Check your email, then return here."
        statusLabel.isHidden = false
        pollTask?.cancel()
        pollTask = Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                let pollToken = try await self.client.requestMagicLink(email: email)
                await self.waitForAccountToken(pollToken)
            } catch {
                self.errorLabel.text = (error as? LivePollError)?.userMessage
                    ?? "Could not send the sign-in email."
                self.setBusy(false)
            }
        }
    }

    private func waitForAccountToken(_ pollToken: String) async {
        for _ in 0..<90 {
            if Task.isCancelled { return }
            do {
                if let token = try await client.pollDeviceLogin(pollToken: pollToken) {
                    LivePollAccountStore.shared.signIn(token: token)
                    onSignedIn?()
                    return
                }
            } catch {
                errorLabel.text = (error as? LivePollError)?.userMessage
                    ?? "Could not finish sign-in."
                setBusy(false)
                return
            }
            try? await Task.sleep(nanoseconds: 2_000_000_000)
        }
        errorLabel.text = "Timed out waiting for the email link."
        setBusy(false)
    }

    private func setBusy(_ busy: Bool) {
        isBusy = busy
        emailField.isEnabled = !busy
        refresh()
    }

    private func refresh() {
        let email = (emailField.text ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        sendButton.isEnabled = !email.isEmpty && !isBusy
        errorLabel.isHidden = (errorLabel.text ?? "").isEmpty
        if var config = sendButton.configuration {
            config.title = isBusy ? "Waiting…" : "Email me a link"
            sendButton.configuration = config
        }
    }
}
