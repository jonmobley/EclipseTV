//
//  LivePollSignInViewController.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import LivePollKit
import SafariServices
import UIKit

/// Form-sheet email sign-in: the relay emails a 6-digit code that the user
/// types (or AutoFills) here. A relay that predates emailed codes answers with
/// a code to show instead, and the sheet falls back to the emailed-link flow.
final class LivePollSignInViewController: UIViewController {

    /// Called after an account token is stored in the Keychain.
    var onSignedIn: (() -> Void)?

    private let client: LivePollClient
    private let showsMigrationMessage: Bool
    private var isBusy = false
    private var pollTask: Task<Void, Never>?
    /// Set once a code has been emailed; the sheet then asks for it.
    private var pendingPollToken: String?

    private let messageLabel = UILabel()
    private let emailField = UITextField()
    private let errorLabel = UILabel()
    private let sendButton = UIButton(type: .system)
    /// Where the emailed code is typed.
    private let codeField = UITextField()
    private let changeEmailButton = UIButton(type: .system)
    private let statusLabel = UILabel()
    /// Older relays only: code to type on the emailed link's confirmation page.
    private let codeLabel = UILabel()

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

        messageLabel.text = showsMigrationMessage
            ? "Host PIN sign-in has been replaced. Sign in with the email for your QuestPoll account."
            : "Sign in with the email you use on questpoll.com."
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

        codeField.placeholder = "6-digit code"
        codeField.keyboardType = .numberPad
        codeField.textContentType = .oneTimeCode
        codeField.borderStyle = .roundedRect
        codeField.textAlignment = .center
        codeField.font = .monospacedSystemFont(ofSize: 24, weight: .semibold)
        codeField.accessibilityIdentifier = "livepoll.signin.codeField"
        codeField.isHidden = true
        codeField.addAction(UIAction { [weak self] _ in
            self?.codeChanged()
        }, for: .editingChanged)

        var changeConfig = UIButton.Configuration.plain()
        changeConfig.title = "Use a Different Email"
        changeEmailButton.configuration = changeConfig
        changeEmailButton.isHidden = true
        changeEmailButton.addAction(UIAction { [weak self] _ in
            self?.changeEmailTapped()
        }, for: .touchUpInside)

        codeLabel.font = .monospacedSystemFont(ofSize: 34, weight: .bold)
        codeLabel.textAlignment = .center
        codeLabel.accessibilityIdentifier = "livepoll.signin.code"
        codeLabel.isHidden = true

        var config = UIButton.Configuration.filled()
        config.title = "Email Me a Code"
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

        var privacyConfig = UIButton.Configuration.plain()
        privacyConfig.title = "Privacy Policy"
        privacyConfig.titleTextAttributesTransformer =
            UIConfigurationTextAttributesTransformer { incoming in
                var attrs = incoming
                attrs.font = .preferredFont(forTextStyle: .footnote)
                return attrs
            }
        let privacyButton = UIButton(configuration: privacyConfig)
        privacyButton.addAction(UIAction { [weak self] _ in
            self?.present(
                SFSafariViewController(url: SettingsViewController.privacyPolicyURL),
                animated: true
            )
        }, for: .touchUpInside)

        let stack = UIStackView(arrangedSubviews: [
            messageLabel, emailField, statusLabel, codeField, errorLabel, sendButton,
            changeEmailButton, codeLabel, privacyButton
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
            codeField.heightAnchor.constraint(equalToConstant: 52),
            sendButton.heightAnchor.constraint(equalToConstant: 52)
        ])
    }

    // MARK: - Actions

    @objc private func closeTapped() {
        pollTask?.cancel()
        dismiss(animated: true)
    }

    private func sendTapped() {
        if pendingPollToken != nil {
            verifyCode()
            return
        }
        let email = (emailField.text ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !email.isEmpty, !isBusy else { return }
        setBusy(true)
        errorLabel.text = nil
        statusLabel.text = "Sending…"
        statusLabel.isHidden = false
        showCode(nil)
        pollTask?.cancel()
        pollTask = Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                let signIn = try await self.client.requestDeviceSignIn(
                    email: email,
                    emailCode: true
                )
                guard let code = signIn.userCode else {
                    self.showCodeEntry(pollToken: signIn.pollToken, email: email)
                    return
                }
                // Older relay: the emailed link only completes sign-in with this code.
                self.statusLabel.text =
                    "Open the link we emailed you and enter this code on that page."
                self.showCode(code)
                await self.waitForAccountToken(signIn.pollToken)
            } catch {
                self.errorLabel.text = (error as? LivePollError)?.userMessage
                    ?? "Could not send the sign-in email."
                self.setBusy(false)
            }
        }
    }

    private func showCodeEntry(pollToken: String, email: String) {
        pendingPollToken = pollToken
        statusLabel.text = "We emailed a 6-digit code to \(email). Enter it below."
        statusLabel.isHidden = false
        emailField.isHidden = true
        codeField.text = nil
        codeField.isHidden = false
        changeEmailButton.isHidden = false
        setBusy(false)
        codeField.becomeFirstResponder()
    }

    private func changeEmailTapped() {
        guard !isBusy else { return }
        pendingPollToken = nil
        codeField.text = nil
        codeField.isHidden = true
        codeField.resignFirstResponder()
        changeEmailButton.isHidden = true
        emailField.isHidden = false
        statusLabel.isHidden = true
        errorLabel.text = nil
        refresh()
    }

    /// Keeps digits only (max 6) and signs in once all six are there, so a
    /// code AutoFilled from Mail finishes without another tap.
    private func codeChanged() {
        let digits = String((codeField.text ?? "").filter(\.isNumber).prefix(6))
        if codeField.text != digits { codeField.text = digits }
        if digits.count == 6 { errorLabel.text = nil }
        refresh()
        if digits.count == 6 { verifyCode() }
    }

    private func verifyCode() {
        let code = codeField.text ?? ""
        guard let pollToken = pendingPollToken, code.count == 6, !isBusy else { return }
        setBusy(true)
        errorLabel.text = nil
        pollTask = Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                let token = try await self.client.verifyEmailedCode(
                    pollToken: pollToken,
                    code: code
                )
                LivePollAccountStore.shared.signIn(token: token)
                self.onSignedIn?()
            } catch {
                self.errorLabel.text = (error as? LivePollError)?.userMessage
                    ?? "Could not finish sign-in."
                self.codeField.text = nil
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

    /// Shows "482 913", or hides the code when `code` is nil.
    private func showCode(_ code: String?) {
        guard let code else {
            codeLabel.text = nil
            codeLabel.isHidden = true
            return
        }
        let spaced = code.count == 6
            ? code.prefix(3) + " " + code.suffix(3)
            : Substring(code)
        codeLabel.text = String(spaced)
        codeLabel.accessibilityLabel = "Sign-in code \(code.map(String.init).joined(separator: " "))"
        codeLabel.isHidden = false
    }

    private func setBusy(_ busy: Bool) {
        isBusy = busy
        if !busy { showCode(nil) }
        emailField.isEnabled = !busy
        codeField.isEnabled = !busy
        refresh()
    }

    private func refresh() {
        let email = (emailField.text ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let entersCode = pendingPollToken != nil
        sendButton.isEnabled = !isBusy && (entersCode
            ? (codeField.text ?? "").count == 6
            : !email.isEmpty)
        errorLabel.isHidden = (errorLabel.text ?? "").isEmpty
        if var config = sendButton.configuration {
            config.title = isBusy
                ? (entersCode ? "Checking…" : "Waiting…")
                : (entersCode ? "Sign In" : "Email Me a Code")
            sendButton.configuration = config
        }
    }
}
