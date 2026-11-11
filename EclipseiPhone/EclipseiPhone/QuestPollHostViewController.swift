//
//  QuestPollHostViewController.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import LivePollKit
import UIKit

/// Native host CONTROLS sheet for the Live Poll room.
final class QuestPollHostViewController: UIViewController {

    /// Widest the content column grows (landscape phone, iPad).
    private static let maxContentWidth: CGFloat = 560

    /// One-step advance / QR / extend / skip command.
    var onAdvance: ((LivePollHostCommand) -> Void)?
    /// Ends the room after the host confirms.
    var onEnd: (() -> Void)?

    private let scroll = UIScrollView()
    private let stack = UIStackView()
    private let progressLabel = UILabel()
    private let joinedTile = StatTile(caption: "Joined")
    private let responsesTile = StatTile(caption: "Responses")
    private let timeTile = StatTile(caption: "Time left")
    private let resultsStack = UIStackView()
    private let primaryButton = UIButton(type: .system)
    private let extendButton = UIButton(type: .system)
    private let projectorQRButton = UIButton(type: .system)
    private let joinQRButton = UIButton(type: .system)
    private let moreButton = UIButton(type: .system)
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

    /// Compact, so most of it fits the half-height sheet:
    /// question N of M · counts row · [+15s] [Next] · results · QR / Join / ⋯.
    /// Skip and End live in ⋯; they are rarely needed and easy to mis-tap mid-show.
    private func buildLayout() {
        scroll.translatesAutoresizingMaskIntoConstraints = false
        scroll.alwaysBounceVertical = true
        view.addSubview(scroll)

        stack.axis = .vertical
        stack.spacing = 12
        stack.alignment = .fill
        stack.translatesAutoresizingMaskIntoConstraints = false
        scroll.addSubview(stack)

        progressLabel.font = .scaled(13, weight: .semibold, relativeTo: .footnote)
        progressLabel.adjustsFontForContentSizeCategory = true
        progressLabel.textColor = UIColor.white.withAlphaComponent(0.55)
        stack.addArrangedSubview(progressLabel)

        let counts = UIStackView(arrangedSubviews: [joinedTile, responsesTile, timeTile])
        counts.axis = .horizontal
        counts.spacing = 8
        counts.distribution = .fillEqually
        stack.addArrangedSubview(counts)

        stylePrimary(primaryButton)
        primaryButton.addAction(UIAction { [weak self] _ in
            self?.handleAdvance()
        }, for: .touchUpInside)
        styleExtend(extendButton)
        extendButton.addAction(UIAction { [weak self] _ in
            self?.onAdvance?(.extend)
        }, for: .touchUpInside)
        let actions = UIStackView(arrangedSubviews: [extendButton, primaryButton])
        actions.axis = .horizontal
        actions.spacing = 10
        stack.addArrangedSubview(actions)

        resultsStack.axis = .vertical
        resultsStack.spacing = 6
        resultsStack.isHidden = true
        stack.addArrangedSubview(resultsStack)

        styleChip(projectorQRButton, title: "Show QR", systemImage: "qrcode.viewfinder")
        projectorQRButton.addAction(UIAction { [weak self] _ in
            self?.handleProjectorQR()
        }, for: .touchUpInside)
        // One place for the code, QR, and link (with Share for Copy / AirDrop).
        styleChip(joinQRButton, title: "Join Code", systemImage: "qrcode")
        joinQRButton.addAction(UIAction { [weak self] _ in
            self?.presentJoinQR()
        }, for: .touchUpInside)
        styleChip(moreButton, title: nil, systemImage: "ellipsis")
        moreButton.accessibilityLabel = "More"
        moreButton.showsMenuAsPrimaryAction = true
        let chips = UIStackView(arrangedSubviews: [projectorQRButton, joinQRButton, moreButton])
        chips.axis = .horizontal
        chips.spacing = 8
        stack.addArrangedSubview(chips)

        let guide = scroll.contentLayoutGuide
        let frame = scroll.frameLayoutGuide
        let fillWidth = stack.widthAnchor.constraint(
            equalTo: frame.widthAnchor, constant: -32
        )
        fillWidth.priority = .defaultHigh
        // +15s is the action people reach for mid-question: big, but Next is wider.
        // Not required, so the stack can collapse it while no question is timing.
        let extendWidth = extendButton.widthAnchor.constraint(
            equalTo: primaryButton.widthAnchor, multiplier: 0.5
        )
        extendWidth.priority = .defaultHigh
        NSLayoutConstraint.activate([
            scroll.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            // Safe area: in landscape the view runs under the notch.
            scroll.leadingAnchor.constraint(
                equalTo: view.safeAreaLayoutGuide.leadingAnchor
            ),
            scroll.trailingAnchor.constraint(
                equalTo: view.safeAreaLayoutGuide.trailingAnchor
            ),
            scroll.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            stack.topAnchor.constraint(equalTo: guide.topAnchor, constant: 12),
            // Centered column, capped so landscape and iPad don't stretch the
            // form and its buttons across the whole screen.
            guide.widthAnchor.constraint(equalTo: frame.widthAnchor),
            stack.centerXAnchor.constraint(equalTo: guide.centerXAnchor),
            stack.leadingAnchor.constraint(
                greaterThanOrEqualTo: guide.leadingAnchor, constant: 16
            ),
            stack.widthAnchor.constraint(lessThanOrEqualToConstant: Self.maxContentWidth),
            stack.bottomAnchor.constraint(equalTo: guide.bottomAnchor, constant: -24),
            fillWidth,
            primaryButton.heightAnchor.constraint(equalToConstant: 64),
            extendButton.heightAnchor.constraint(equalTo: primaryButton.heightAnchor),
            extendWidth,
            projectorQRButton.heightAnchor.constraint(equalToConstant: 40),
            joinQRButton.heightAnchor.constraint(equalTo: projectorQRButton.heightAnchor),
            moreButton.heightAnchor.constraint(equalTo: projectorQRButton.heightAnchor),
            moreButton.widthAnchor.constraint(equalToConstant: 48)
        ])
    }

    /// "Next", with what it will do underneath ("Show results", "Next question"…).
    private func stylePrimary(_ button: UIButton) {
        var config = UIButton.Configuration.filled()
        config.title = "Next"
        config.image = UIImage(systemName: "forward.fill")
        config.imagePlacement = .trailing
        config.imagePadding = 8
        config.titleAlignment = .center
        config.baseBackgroundColor = .accent
        config.baseForegroundColor = .white
        config.cornerStyle = .large
        config.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer {
            var attrs = $0
            attrs.font = .scaled(18, weight: .bold, maximumPointSize: Self.buttonFontCap)
            return attrs
        }
        config.subtitleTextAttributesTransformer = UIConfigurationTextAttributesTransformer {
            var attrs = $0
            attrs.font = .scaled(13, weight: .medium, maximumPointSize: 18)
            attrs.foregroundColor = UIColor.white.withAlphaComponent(0.8)
            return attrs
        }
        button.configuration = config
    }

    private func styleExtend(_ button: UIButton) {
        var config = UIButton.Configuration.filled()
        config.title = "+15s"
        config.baseBackgroundColor = UIColor(white: 0.2, alpha: 1)
        config.baseForegroundColor = .white
        config.cornerStyle = .large
        config.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer {
            var attrs = $0
            attrs.font = .scaledMonospacedDigit(20, weight: .bold, relativeTo: .title3)
            return attrs
        }
        button.configuration = config
        button.accessibilityLabel = "Add 15 seconds"
    }

    private func styleChip(_ button: UIButton, title: String?, systemImage: String) {
        var config = UIButton.Configuration.plain()
        config.title = title
        config.image = UIImage(systemName: systemImage)
        config.imagePadding = 6
        config.baseForegroundColor = .white
        config.background.backgroundColor = UIColor(white: 0.14, alpha: 1)
        config.background.cornerRadius = 12
        config.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer {
            var attrs = $0
            attrs.font = .scaled(14, weight: .semibold, maximumPointSize: 20)
            return attrs
        }
        button.configuration = config
    }

    /// Buttons here have fixed heights, so their titles grow only up to this.
    private static let buttonFontCap: CGFloat = 24

    // MARK: - Bind

    private func refresh() {
        let store = QuestPollSessionStore.shared
        guard let session = store.session else {
            dismiss(animated: true)
            return
        }
        progressLabel.text = LivePollAdvance.progressLabel(
            questionIndex: session.questionIndex,
            questionCount: store.questionCount
        ).uppercased()
        joinedTile.value = Self.joinedValue(
            joined: session.players.count,
            limit: session.playerLimit
        )
        joinedTile.accessibilityValue = Self.joinedText(
            joined: session.players.count,
            limit: session.playerLimit
        )
        responsesTile.value = "\(session.answeredCount)"

        let mode = session.mode ?? .quiz
        let advance = LivePollAdvance.primary(
            phase: session.phase,
            questionIndex: session.questionIndex,
            questionCount: store.questionCount,
            mode: mode
        )
        primaryButton.isHidden = advance == nil
        if var config = primaryButton.configuration {
            config.subtitle = advance?.title
            primaryButton.configuration = config
        }
        primaryButton.accessibilityLabel = advance.map { "Next: \($0.title)" } ?? "Next"

        let timerRunning = session.phase == .questionOpen || session.phase == .locked
        extendButton.isHidden = !timerRunning
        timeTile.value = Self.timeLeftText(timerRunning ? session.remainingMs : nil)
        refreshResults(session)

        let qrToggle = LivePollAdvance.joinQRToggle(
            phase: session.phase,
            isVisible: session.showsJoinQR
        )
        projectorQRButton.isHidden = qrToggle == nil
        if var config = projectorQRButton.configuration {
            config.title = session.showsJoinQR ? "Hide QR" : "Show QR"
            config.image = UIImage(
                systemName: session.showsJoinQR ? "eye.slash" : "qrcode.viewfinder"
            )
            projectorQRButton.configuration = config
        }
        projectorQRButton.accessibilityHint = "Shows or hides the join QR on the screen."

        let busy = store.isControlInFlight
        primaryButton.isEnabled = !busy && advance != nil
        extendButton.isEnabled = !busy && timerRunning
        projectorQRButton.isEnabled = !busy && qrToggle != nil
        moreButton.isEnabled = !busy
        moreButton.menu = makeMoreMenu(
            canSkip: timerRunning && !busy,
            display: session.effectiveDisplay,
            canChangeDisplay: !busy && session.phase != .ended
        )
    }

    /// Screen options, Skip (rarely wanted, and it shows no results), and End Poll.
    private func makeMoreMenu(
        canSkip: Bool,
        display: LivePollDisplay,
        canChangeDisplay: Bool
    ) -> UIMenu {
        let skip = UIAction(
            title: "Skip Question",
            subtitle: "Moves on without showing results",
            image: UIImage(systemName: "forward.end"),
            attributes: canSkip ? [] : .disabled
        ) { [weak self] _ in
            self?.onAdvance?(.skip)
        }
        let end = UIAction(
            title: "End Poll",
            image: UIImage(systemName: "stop.circle"),
            attributes: .destructive
        ) { [weak self] _ in
            self?.onEnd?()
        }
        return UIMenu(children: [
            makeScreenMenu(display: display, enabled: canChangeDisplay),
            skip,
            UIMenu(options: .displayInline, children: [end])
        ])
    }

    /// What the big screen shows: the timer, a join QR kept in the corner, and
    /// how long each question stays open.
    private func makeScreenMenu(display: LivePollDisplay, enabled: Bool) -> UIMenu {
        let attributes: UIMenuElement.Attributes = enabled ? [] : .disabled
        let timer = UIAction(
            title: "Show Timer",
            image: UIImage(systemName: "timer"),
            attributes: attributes,
            state: display.showTimer ? .on : .off
        ) { [weak self] _ in
            self?.onAdvance?(.setDisplay(.init(showTimer: !display.showTimer)))
        }
        let qr = UIAction(
            title: "Keep Join QR Up",
            subtitle: "Small QR in the corner during the poll",
            image: UIImage(systemName: "qrcode"),
            attributes: attributes,
            state: display.keepJoinQR ? .on : .off
        ) { [weak self] _ in
            self?.onAdvance?(.setDisplay(.init(keepJoinQR: !display.keepJoinQR)))
        }
        let times: [Int?] = [nil] + Self.timePerQuestionChoices
        let timeActions = times.map { seconds in
            UIAction(
                title: seconds.map { "\($0) seconds" } ?? "Each Question's Own",
                attributes: attributes,
                state: display.voteSeconds == seconds ? .on : .off
            ) { [weak self] _ in
                self?.onAdvance?(.setDisplay(.init(voteSeconds: .some(seconds))))
            }
        }
        let time = UIMenu(
            title: "Time per Question",
            subtitle: display.voteSeconds.map { "\($0) s, from the next question" }
                ?? "Each question's own",
            image: UIImage(systemName: "hourglass"),
            children: timeActions
        )
        return UIMenu(
            title: "Screen",
            options: .displayInline,
            children: [timer, qr, time]
        )
    }

    /// Times offered for every question, in seconds.
    static let timePerQuestionChoices: [Int] = [15, 30, 45, 60, 90]

    /// "0:12", or "—" when no question is timing.
    static func timeLeftText(_ remainingMs: Double?) -> String {
        guard let remainingMs, remainingMs > 0 else { return "—" }
        let seconds = Int(ceil(remainingMs / 1000))
        return String(format: "%d:%02d", seconds / 60, seconds % 60)
    }

    /// "12", or "12/50" for a capped room.
    static func joinedValue(joined: Int, limit: Int?) -> String {
        guard let limit, limit < 300 else { return "\(joined)" }
        return "\(joined)/\(limit)"
    }

    private func refreshResults(_ session: LivePollSession) {
        resultsStack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        guard let results = session.results, !results.options.isEmpty else {
            resultsStack.isHidden = true
            return
        }
        resultsStack.isHidden = false
        let heading = UILabel()
        heading.text = "RESULTS · \(results.total) TOTAL"
        heading.font = .scaled(13, weight: .semibold, relativeTo: .footnote)
        heading.adjustsFontForContentSizeCategory = true
        heading.textColor = UIColor.white.withAlphaComponent(0.55)
        resultsStack.addArrangedSubview(heading)
        for option in results.options {
            let row = UILabel()
            row.text = "\(option.text)  \(option.percent)% · \(option.count)"
            row.font = .scaled(15, weight: .medium, relativeTo: .subheadline)
            row.adjustsFontForContentSizeCategory = true
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

    /// "12 joined", or "50 of 50 joined · free plan limit" when a capped
    /// room is full (same wording as the web host page).
    static func joinedText(joined: Int, limit: Int?) -> String {
        guard let limit, limit < 300 else { return "\(joined) joined" }
        let full = joined >= limit ? " · free plan limit" : ""
        return "\(joined) of \(limit) joined\(full)"
    }
}

/// A small count tile: big number, caption underneath.
private final class StatTile: UIView {
    private let valueLabel = UILabel()
    private let captionLabel = UILabel()

    var value: String {
        get { valueLabel.text ?? "" }
        set {
            valueLabel.text = newValue
            accessibilityValue = newValue
        }
    }

    init(caption: String) {
        super.init(frame: .zero)
        backgroundColor = UIColor(white: 0.14, alpha: 1)
        layer.cornerRadius = 14
        isAccessibilityElement = true
        accessibilityLabel = caption

        valueLabel.font = .scaledMonospacedDigit(26, weight: .bold, relativeTo: .title2)
        valueLabel.adjustsFontForContentSizeCategory = true
        valueLabel.textColor = .white
        valueLabel.textAlignment = .center
        valueLabel.adjustsFontSizeToFitWidth = true
        valueLabel.minimumScaleFactor = 0.6
        valueLabel.text = "0"

        captionLabel.text = caption
        captionLabel.font = .scaled(12, weight: .medium, relativeTo: .caption1)
        captionLabel.adjustsFontForContentSizeCategory = true
        captionLabel.textColor = UIColor.white.withAlphaComponent(0.55)
        captionLabel.textAlignment = .center

        let column = UIStackView(arrangedSubviews: [valueLabel, captionLabel])
        column.axis = .vertical
        column.spacing = 2
        column.translatesAutoresizingMaskIntoConstraints = false
        addSubview(column)
        NSLayoutConstraint.activate([
            column.topAnchor.constraint(equalTo: topAnchor, constant: 10),
            column.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -10),
            column.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 6),
            column.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -6)
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}
