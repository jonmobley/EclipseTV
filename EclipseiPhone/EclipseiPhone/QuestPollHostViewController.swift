//
//  QuestPollHostViewController.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import LivePollKit
import SafariServices
import UIKit

/// Native host CONTROLS sheet for the Live Poll room.
final class QuestPollHostViewController: UIViewController {

    /// One-step advance / QR / extend / skip command.
    var onAdvance: ((LivePollHostCommand) -> Void)?
    /// Ends the room after the host confirms.
    var onEnd: (() -> Void)?

    private let scroll = UIScrollView()
    private let stack = UIStackView()
    private let responsesValue = UILabel()
    private let countdownLabel = UILabel()
    private let progressLabel = UILabel()
    private let resultsStack = UIStackView()
    private let primaryButton = UIButton(type: .system)
    private let extendButton = UIButton(type: .system)
    private let skipButton = UIButton(type: .system)
    private let projectorQRButton = UIButton(type: .system)
    private let joinQRButton = UIButton(type: .system)
    private let projectorButton = UIButton(type: .system)
    private let endButton = UIButton(type: .system)
    private let copyLinkButton = UIButton(type: .system)
    private var storeObserver: NSObjectProtocol?

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Controls"
        view.backgroundColor = .black
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            systemItem: .close,
            primaryAction: UIAction { [weak self] _ in
                self?.dismiss(animated: true)
            }
        )
        buildLayout()
        refresh()
        storeObserver = NotificationCenter.default.addObserver(
            forName: QuestPollSessionStore.didChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.refresh()
        }
    }

    deinit {
        if let storeObserver {
            NotificationCenter.default.removeObserver(storeObserver)
        }
    }

    // MARK: - Layout

    private func buildLayout() {
        scroll.translatesAutoresizingMaskIntoConstraints = false
        scroll.alwaysBounceVertical = true
        view.addSubview(scroll)

        stack.axis = .vertical
        stack.spacing = 16
        stack.alignment = .fill
        stack.translatesAutoresizingMaskIntoConstraints = false
        scroll.addSubview(stack)

        let heading = UILabel()
        heading.text = "CONTROLS"
        heading.font = .systemFont(ofSize: 12, weight: .semibold)
        heading.textColor = UIColor.white.withAlphaComponent(0.45)
        heading.textAlignment = .left

        stack.addArrangedSubview(heading)
        stack.addArrangedSubview(makeResponsesCard())

        countdownLabel.font = .monospacedDigitSystemFont(ofSize: 15, weight: .semibold)
        countdownLabel.textColor = UIColor.white.withAlphaComponent(0.7)
        countdownLabel.textAlignment = .center
        countdownLabel.isHidden = true
        stack.addArrangedSubview(countdownLabel)

        progressLabel.font = .systemFont(ofSize: 14, weight: .medium)
        progressLabel.textColor = UIColor.white.withAlphaComponent(0.55)
        progressLabel.textAlignment = .center
        stack.addArrangedSubview(progressLabel)

        resultsStack.axis = .vertical
        resultsStack.spacing = 8
        resultsStack.isHidden = true
        stack.addArrangedSubview(resultsStack)

        stylePrimary(primaryButton)
        primaryButton.addAction(UIAction { [weak self] _ in
            self?.handleAdvance()
        }, for: .touchUpInside)
        stack.addArrangedSubview(primaryButton)

        let row = UIStackView(arrangedSubviews: [extendButton, skipButton])
        row.axis = .horizontal
        row.spacing = 10
        row.distribution = .fillEqually
        styleSecondary(extendButton, title: "Extend +15s", systemImage: "plus.circle")
        extendButton.addAction(UIAction { [weak self] _ in
            self?.onAdvance?(.extend)
        }, for: .touchUpInside)
        styleSecondary(skipButton, title: "Skip", systemImage: "forward.end")
        skipButton.addAction(UIAction { [weak self] _ in
            self?.onAdvance?(.skip)
        }, for: .touchUpInside)
        stack.addArrangedSubview(row)

        styleSecondary(
            projectorQRButton, title: "Show QR", systemImage: "qrcode.viewfinder"
        )
        projectorQRButton.addAction(UIAction { [weak self] _ in
            self?.handleProjectorQR()
        }, for: .touchUpInside)
        stack.addArrangedSubview(projectorQRButton)

        styleSecondary(joinQRButton, title: "Join QR", systemImage: "qrcode")
        joinQRButton.addAction(UIAction { [weak self] _ in
            self?.presentJoinQR()
        }, for: .touchUpInside)
        stack.addArrangedSubview(joinQRButton)

        styleSecondary(projectorButton, title: "Projector", systemImage: "display")
        projectorButton.addAction(UIAction { [weak self] _ in
            self?.openProjector()
        }, for: .touchUpInside)
        stack.addArrangedSubview(projectorButton)

        styleTextLink(endButton, title: "End")
        endButton.addAction(UIAction { [weak self] _ in
            self?.onEnd?()
        }, for: .touchUpInside)
        stack.addArrangedSubview(endButton)

        styleTextLink(copyLinkButton, title: "Copy join link", systemImage: "link")
        copyLinkButton.addAction(UIAction { [weak self] _ in
            self?.copyJoinLink()
        }, for: .touchUpInside)
        stack.addArrangedSubview(copyLinkButton)

        let guide = scroll.contentLayoutGuide
        let frame = scroll.frameLayoutGuide
        NSLayoutConstraint.activate([
            scroll.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            scroll.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scroll.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            stack.topAnchor.constraint(equalTo: guide.topAnchor, constant: 20),
            stack.leadingAnchor.constraint(equalTo: guide.leadingAnchor, constant: 20),
            stack.trailingAnchor.constraint(equalTo: guide.trailingAnchor, constant: -20),
            stack.bottomAnchor.constraint(equalTo: guide.bottomAnchor, constant: -28),
            stack.widthAnchor.constraint(equalTo: frame.widthAnchor, constant: -40),
            primaryButton.heightAnchor.constraint(equalToConstant: 52),
            extendButton.heightAnchor.constraint(equalToConstant: 48),
            skipButton.heightAnchor.constraint(equalToConstant: 48),
            projectorQRButton.heightAnchor.constraint(equalToConstant: 48),
            joinQRButton.heightAnchor.constraint(equalToConstant: 48),
            projectorButton.heightAnchor.constraint(equalToConstant: 48)
        ])
    }

    private func makeResponsesCard() -> UIView {
        let card = UIView()
        card.backgroundColor = UIColor(white: 0.14, alpha: 1)
        card.layer.cornerRadius = 16
        card.layer.masksToBounds = true

        let caption = UILabel()
        caption.text = "Responses"
        caption.font = .systemFont(ofSize: 14, weight: .medium)
        caption.textColor = UIColor.white.withAlphaComponent(0.55)
        caption.translatesAutoresizingMaskIntoConstraints = false

        responsesValue.font = UIFontMetrics(forTextStyle: .largeTitle).scaledFont(
            for: .systemFont(ofSize: 56, weight: .bold)
        )
        responsesValue.adjustsFontForContentSizeCategory = true
        responsesValue.textColor = .white
        responsesValue.textAlignment = .center
        responsesValue.translatesAutoresizingMaskIntoConstraints = false
        responsesValue.text = "0"

        card.addSubview(caption)
        card.addSubview(responsesValue)
        NSLayoutConstraint.activate([
            caption.topAnchor.constraint(equalTo: card.topAnchor, constant: 16),
            caption.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 16),
            responsesValue.topAnchor.constraint(equalTo: caption.bottomAnchor, constant: 4),
            responsesValue.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 16),
            responsesValue.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -16),
            responsesValue.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -18)
        ])
        return card
    }

    private func stylePrimary(_ button: UIButton) {
        var config = UIButton.Configuration.filled()
        config.baseBackgroundColor = .systemBlue
        config.baseForegroundColor = .white
        config.cornerStyle = .large
        config.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer {
            var attrs = $0
            attrs.font = .systemFont(ofSize: 17, weight: .semibold)
            return attrs
        }
        button.configuration = config
    }

    private func styleSecondary(_ button: UIButton, title: String, systemImage: String) {
        var config = UIButton.Configuration.plain()
        config.title = title
        config.image = UIImage(systemName: systemImage)
        config.imagePadding = 10
        config.baseForegroundColor = .white
        config.background.backgroundColor = UIColor(white: 0.14, alpha: 1)
        config.background.strokeColor = UIColor.white.withAlphaComponent(0.18)
        config.background.strokeWidth = 1
        config.background.cornerRadius = 14
        config.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer {
            var attrs = $0
            attrs.font = .systemFont(ofSize: 16, weight: .semibold)
            return attrs
        }
        button.configuration = config
    }

    private func styleTextLink(
        _ button: UIButton,
        title: String,
        systemImage: String? = nil
    ) {
        var config = UIButton.Configuration.plain()
        config.title = title
        if let systemImage {
            config.image = UIImage(systemName: systemImage)
            config.imagePadding = 6
        }
        config.baseForegroundColor = UIColor.white.withAlphaComponent(0.55)
        config.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer {
            var attrs = $0
            attrs.font = .systemFont(ofSize: 16, weight: .medium)
            return attrs
        }
        button.configuration = config
    }

    // MARK: - Bind

    private func refresh() {
        let store = QuestPollSessionStore.shared
        guard let session = store.session else {
            dismiss(animated: true)
            return
        }
        responsesValue.text = "\(session.answeredCount)"
        progressLabel.text = LivePollAdvance.progressLabel(
            questionIndex: session.questionIndex,
            questionCount: store.questionCount
        )
        let mode = session.mode ?? .quiz
        let advance = LivePollAdvance.primary(
            phase: session.phase,
            questionIndex: session.questionIndex,
            questionCount: store.questionCount,
            mode: mode
        )
        primaryButton.isHidden = advance == nil
        if var config = primaryButton.configuration {
            config.title = advance?.title ?? ""
            primaryButton.configuration = config
        }
        let showTimerControls = session.phase == .questionOpen
            || session.phase == .locked
        extendButton.superview?.isHidden = !showTimerControls
        refreshCountdown(session)
        refreshResults(session)
        let qrToggle = LivePollAdvance.joinQRToggle(
            phase: session.phase,
            isVisible: session.showsJoinQR
        )
        projectorQRButton.isHidden = qrToggle == nil
        if var config = projectorQRButton.configuration {
            config.title = qrToggle?.title ?? "Show QR"
            config.image = UIImage(
                systemName: session.showsJoinQR ? "eye.slash" : "qrcode.viewfinder"
            )
            projectorQRButton.configuration = config
        }
        let busy = store.isControlInFlight
        primaryButton.isEnabled = !busy && advance != nil
        extendButton.isEnabled = !busy && showTimerControls
        skipButton.isEnabled = !busy && showTimerControls
        projectorQRButton.isEnabled = !busy && qrToggle != nil
        endButton.isEnabled = !busy
    }

    private func refreshCountdown(_ session: LivePollSession) {
        guard session.phase == .questionOpen || session.phase == .locked,
              let remaining = session.remainingMs, remaining > 0
        else {
            countdownLabel.isHidden = true
            return
        }
        let seconds = Int(ceil(remaining / 1000))
        countdownLabel.text = "\(seconds)s remaining"
        countdownLabel.isHidden = false
    }

    private func refreshResults(_ session: LivePollSession) {
        resultsStack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        guard let results = session.results, !results.options.isEmpty else {
            resultsStack.isHidden = true
            return
        }
        resultsStack.isHidden = false
        let heading = UILabel()
        heading.text = "Results · \(results.total) total"
        heading.font = .systemFont(ofSize: 13, weight: .semibold)
        heading.textColor = UIColor.white.withAlphaComponent(0.55)
        resultsStack.addArrangedSubview(heading)
        for option in results.options {
            let row = UILabel()
            row.text = "\(option.text)  \(option.percent)% · \(option.count)"
            row.font = .systemFont(ofSize: 15, weight: .medium)
            row.textColor = .white
            row.numberOfLines = 0
            resultsStack.addArrangedSubview(row)
        }
    }

    // MARK: - Actions

    private func handleAdvance() {
        let store = QuestPollSessionStore.shared
        guard let session = store.session,
              let advance = LivePollAdvance.primary(
                phase: session.phase,
                questionIndex: session.questionIndex,
                questionCount: store.questionCount,
                mode: session.mode ?? .quiz
              )
        else { return }
        onAdvance?(advance.command)
    }

    private func handleProjectorQR() {
        guard let session = QuestPollSessionStore.shared.session,
              let toggle = LivePollAdvance.joinQRToggle(
                phase: session.phase,
                isVisible: session.showsJoinQR
              )
        else { return }
        onAdvance?(toggle.command)
    }

    private func presentJoinQR() {
        guard let code = QuestPollSessionStore.shared.session?.code else { return }
        let url = QuestPollConfig.joinURL(code: code)
        let sheet = QuestPollJoinQRViewController(code: code, joinURL: url)
        let nav = UINavigationController(rootViewController: sheet)
        nav.modalPresentationStyle = .formSheet
        present(nav, animated: true)
    }

    private func openProjector() {
        let url: URL
        if let code = QuestPollSessionStore.shared.session?.code, !code.isEmpty {
            url = QuestPollConfig.presentURL(code: code)
        } else {
            url = QuestPollConfig.presentURL
        }
        present(SFSafariViewController(url: url), animated: true)
    }

    private func copyJoinLink() {
        guard let code = QuestPollSessionStore.shared.session?.code else { return }
        UIPasteboard.general.string = QuestPollConfig.joinURL(code: code).absoluteString
        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(.success)
        var config = copyLinkButton.configuration
        config?.title = "Copied"
        copyLinkButton.configuration = config
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [weak self] in
            var restored = self?.copyLinkButton.configuration
            restored?.title = "Copy join link"
            self?.copyLinkButton.configuration = restored
        }
    }
}
