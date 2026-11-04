//
//  PrompterViewController.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import UIKit

/// Full-screen operator view for a Show's Prompter: the scrolling script with
/// Play/Pause, Reset, speed, text size, Edit and Go Live.
///
/// The controller keeps running when this view closes, so the output display keeps
/// scrolling and reopening the view resumes where it was.
final class PrompterViewController: UIViewController {

    /// How Go Live / Stop Live reach the display. `nil` hides the button (for
    /// example on a Show Live operator device, which drives nothing itself).
    struct LiveActions {
        /// Tries to put the prompter on the display; returns whether it did.
        var goLive: () -> Bool
        var stopLive: () -> Void
    }

    static let emptyStateText = "Write your script to begin."

    let showId: UUID
    var liveActions: LiveActions?

    let stage = PrompterStageView()
    let playButton = UIButton(configuration: .filled())
    let resetButton = UIButton(configuration: .plain())
    let speedDownButton = UIButton(configuration: .plain())
    let speedUpButton = UIButton(configuration: .plain())
    let speedLabel = UILabel()
    let sizeDownButton = UIButton(configuration: .plain())
    let sizeUpButton = UIButton(configuration: .plain())
    let liveButton = UIButton(configuration: .tinted())
    let emptyLabel = UILabel()
    let emptyEditButton = UIButton(configuration: .filled())

    private let controller: PrompterController
    private let transport = UIVisualEffectView(effect: UIBlurEffect(style: .systemThickMaterialDark))
    private var observers: [NSObjectProtocol] = []
    private var panStartOffset: CGFloat = 0

    init(showId: UUID, controller: PrompterController? = nil) {
        self.showId = showId
        self.controller = controller ?? .shared
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        observers.forEach(NotificationCenter.default.removeObserver)
    }

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        overrideUserInterfaceStyle = .dark
        title = "Prompter"
        navigationItem.leftBarButtonItem = UIBarButtonItem(
            barButtonSystemItem: .done, target: self, action: #selector(doneTapped)
        )
        let edit = UIBarButtonItem(
            image: UIImage(systemName: "pencil"), style: .plain,
            target: self, action: #selector(editTapped)
        )
        edit.accessibilityLabel = "Edit Script"
        navigationItem.rightBarButtonItem = edit

        controller.bind(showId: showId)
        setupStage()
        setupTransport()
        setupEmptyState()
        setupGestures()
        observe()
        refreshFromController()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        // A prompter must not dim or lock mid-speech.
        UIApplication.shared.isIdleTimerDisabled = true
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        UIApplication.shared.isIdleTimerDisabled = false
    }

    override var prefersStatusBarHidden: Bool { false }

    override var keyCommands: [UIKeyCommand]? {
        let toggle = UIKeyCommand(title: "Play/Pause", action: #selector(togglePlay), input: " ")
        toggle.wantsPriorityOverSystemBehavior = true
        let up = UIKeyCommand(title: "Previous Line", action: #selector(lineUp), input: UIKeyCommand.inputUpArrow)
        let down = UIKeyCommand(title: "Next Line", action: #selector(lineDown), input: UIKeyCommand.inputDownArrow)
        up.wantsPriorityOverSystemBehavior = true
        down.wantsPriorityOverSystemBehavior = true
        let reset = UIKeyCommand(title: "Reset", action: #selector(resetTapped), input: "r", modifierFlags: .command)
        let edit = UIKeyCommand(title: "Edit Script", action: #selector(editTapped), input: "e", modifierFlags: .command)
        let live = UIKeyCommand(title: "Go Live", action: #selector(liveTapped), input: "l", modifierFlags: .command)
        let close = UIKeyCommand(title: "Close", action: #selector(doneTapped), input: UIKeyCommand.inputEscape)
        return [toggle, up, down, reset, edit, live, close]
    }

    // MARK: - Setup

    private func setupStage() {
        stage.translatesAutoresizingMaskIntoConstraints = false
        stage.maximumTextWidth = PrompterStageMetrics.maximumOperatorTextWidth
        stage.horizontalInset = 24
        stage.setFont(PrompterStageMetrics.font(ofSize: controller.fontSize))
        stage.onMetricsChange = { [weak self] size in
            self?.controller.updateStage(width: size.width, viewportHeight: size.height)
        }
        view.addSubview(stage)
        NSLayoutConstraint.activate([
            stage.topAnchor.constraint(equalTo: view.topAnchor),
            stage.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            stage.trailingAnchor.constraint(equalTo: view.trailingAnchor)
        ])
    }

    private func setupTransport() {
        transport.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(transport)

        configure(resetButton, symbol: "backward.end.fill", label: "Reset to Top", action: #selector(resetTapped))
        configure(playButton, symbol: "play.fill", label: "Play", action: #selector(togglePlay))
        playButton.configuration?.cornerStyle = .capsule
        playButton.configuration?.contentInsets = NSDirectionalEdgeInsets(top: 14, leading: 28, bottom: 14, trailing: 28)
        configure(liveButton, symbol: "antenna.radiowaves.left.and.right", label: "Go Live", action: #selector(liveTapped))
        liveButton.configuration?.title = "Go Live"
        liveButton.configuration?.imagePadding = 6

        configure(speedDownButton, symbol: "minus", label: "Slower", action: #selector(speedDown))
        configure(speedUpButton, symbol: "plus", label: "Faster", action: #selector(speedUp))
        speedLabel.font = .monospacedDigitSystemFont(ofSize: 15, weight: .semibold)
        speedLabel.textColor = .white
        speedLabel.textAlignment = .center
        speedLabel.setContentHuggingPriority(.required, for: .horizontal)
        speedLabel.accessibilityLabel = "Speed"

        configure(sizeDownButton, symbol: "textformat.size.smaller", label: "Smaller Text", action: #selector(sizeDown))
        configure(sizeUpButton, symbol: "textformat.size.larger", label: "Larger Text", action: #selector(sizeUp))

        let speedGroup = UIStackView(arrangedSubviews: [speedDownButton, speedLabel, speedUpButton])
        speedGroup.spacing = 2
        speedGroup.alignment = .center
        let sizeGroup = UIStackView(arrangedSubviews: [sizeDownButton, sizeUpButton])
        sizeGroup.spacing = 2
        let topRow = UIStackView(arrangedSubviews: [resetButton, playButton, liveButton])
        topRow.spacing = 20
        topRow.alignment = .center
        topRow.distribution = .equalCentering
        let bottomRow = UIStackView(arrangedSubviews: [speedGroup, sizeGroup])
        bottomRow.spacing = 24
        bottomRow.alignment = .center
        bottomRow.distribution = .equalCentering

        let rows = UIStackView(arrangedSubviews: [topRow, bottomRow])
        rows.axis = .vertical
        rows.spacing = 8
        rows.alignment = .center
        rows.translatesAutoresizingMaskIntoConstraints = false
        transport.contentView.addSubview(rows)

        NSLayoutConstraint.activate([
            transport.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            transport.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            transport.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            stage.bottomAnchor.constraint(equalTo: transport.topAnchor),
            rows.topAnchor.constraint(equalTo: transport.contentView.topAnchor, constant: 10),
            rows.centerXAnchor.constraint(equalTo: transport.contentView.centerXAnchor),
            rows.leadingAnchor.constraint(greaterThanOrEqualTo: transport.contentView.safeAreaLayoutGuide.leadingAnchor, constant: 16),
            rows.trailingAnchor.constraint(lessThanOrEqualTo: transport.contentView.safeAreaLayoutGuide.trailingAnchor, constant: -16),
            rows.bottomAnchor.constraint(equalTo: transport.contentView.safeAreaLayoutGuide.bottomAnchor, constant: -10),
            topRow.widthAnchor.constraint(equalTo: rows.widthAnchor),
            bottomRow.widthAnchor.constraint(equalTo: rows.widthAnchor)
        ])
    }

    private func configure(_ button: UIButton, symbol: String, label: String, action: Selector) {
        button.configuration?.image = UIImage(systemName: symbol)
        button.configuration?.preferredSymbolConfigurationForImage = UIImage.SymbolConfiguration(pointSize: 20, weight: .semibold)
        button.accessibilityLabel = label
        button.addTarget(self, action: action, for: .touchUpInside)
    }

    private func setupEmptyState() {
        emptyLabel.text = Self.emptyStateText
        emptyLabel.textColor = .secondaryLabel
        emptyLabel.font = .preferredFont(forTextStyle: .title3)
        emptyLabel.adjustsFontForContentSizeCategory = true
        emptyLabel.textAlignment = .center
        emptyLabel.numberOfLines = 0
        emptyEditButton.configuration?.title = "Edit Script"
        emptyEditButton.configuration?.image = UIImage(systemName: "pencil")
        emptyEditButton.configuration?.imagePadding = 6
        emptyEditButton.addTarget(self, action: #selector(editTapped), for: .touchUpInside)
        let stack = UIStackView(arrangedSubviews: [emptyLabel, emptyEditButton])
        stack.axis = .vertical
        stack.spacing = 16
        stack.alignment = .center
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.centerXAnchor.constraint(equalTo: stage.centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: stage.centerYAnchor),
            stack.leadingAnchor.constraint(greaterThanOrEqualTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 32),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -32)
        ])
        emptyStack = stack
    }

    private var emptyStack: UIStackView?

    private func setupGestures() {
        let pan = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
        pan.maximumNumberOfTouches = 1
        stage.addGestureRecognizer(pan)
        let tap = UITapGestureRecognizer(target: self, action: #selector(togglePlay))
        tap.require(toFail: pan)
        stage.addGestureRecognizer(tap)
    }

    private func observe() {
        let center = NotificationCenter.default
        observers.append(center.addObserver(
            forName: PrompterController.didChangeNotification, object: controller, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.refreshFromController() }
        })
        observers.append(center.addObserver(
            forName: PrompterController.offsetDidChangeNotification, object: controller, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.applyAnchor() }
        })
    }

    // MARK: - State

    private var lastScript: String?

    func refreshFromController() {
        if lastScript != controller.script {
            lastScript = controller.script
            stage.setScript(controller.script, anchor: controller.readingAnchor)
        }
        stage.setFont(PrompterStageMetrics.font(ofSize: controller.fontSize))
        let empty = !controller.canPlay
        emptyStack?.isHidden = !empty
        stage.showsReadingGuide = !empty
        playButton.isEnabled = !empty
        resetButton.isEnabled = !empty
        playButton.configuration?.image = UIImage(systemName: controller.isPlaying ? "pause.fill" : "play.fill")
        playButton.accessibilityLabel = controller.isPlaying ? "Pause" : "Play"
        speedLabel.text = Self.speedText(controller.speedMultiplier)
        speedDownButton.isEnabled = controller.speedMultiplier > PrompterScrollEngine.minimumSpeed
        speedUpButton.isEnabled = controller.speedMultiplier < PrompterScrollEngine.maximumSpeed
        sizeDownButton.isEnabled = controller.fontSize > PrompterStageMetrics.operatorFontRange.lowerBound
        sizeUpButton.isEnabled = controller.fontSize < PrompterStageMetrics.operatorFontRange.upperBound
        refreshLiveButton()
        applyAnchor()
    }

    private func refreshLiveButton() {
        liveButton.isHidden = liveActions == nil
        liveButton.isEnabled = controller.canPlay || controller.isLive
        if controller.isLive {
            liveButton.configuration = .filled()
            liveButton.configuration?.baseBackgroundColor = .systemRed
            liveButton.configuration?.baseForegroundColor = .white
            liveButton.configuration?.image = UIImage(systemName: "stop.fill")
            liveButton.configuration?.title = "Stop Live"
            liveButton.accessibilityLabel = "Stop Live"
        } else {
            liveButton.configuration = .tinted()
            liveButton.configuration?.image = UIImage(systemName: "antenna.radiowaves.left.and.right")
            liveButton.configuration?.title = "Go Live"
            liveButton.accessibilityLabel = "Go Live"
        }
        liveButton.configuration?.imagePadding = 6
    }

    static func speedText(_ multiplier: Double) -> String {
        multiplier == multiplier.rounded()
            ? String(format: "%.0f×", multiplier)
            : String(format: "%.2f×", multiplier).replacingOccurrences(of: "0×", with: "×")
    }

    private func applyAnchor() {
        stage.apply(anchor: controller.readingAnchor)
    }

    // MARK: - Actions

    @objc private func doneTapped() {
        dismiss(animated: true)
    }

    @objc func editTapped() {
        let nav = PrompterScriptEditorViewController.makeNavigation(
            showId: showId,
            traits: traitCollection,
            anchor: navigationItem.rightBarButtonItem?.value(forKey: "view") as? UIView,
            arrows: [.up]
        )
        present(nav, animated: true)
    }

    @objc func togglePlay() {
        controller.toggleRunning()
    }

    @objc private func resetTapped() {
        controller.reset()
    }

    @objc private func lineUp() { controller.nudge(lines: -1) }
    @objc private func lineDown() { controller.nudge(lines: 1) }

    @objc private func speedDown() {
        controller.setSpeed(controller.speedMultiplier - PrompterStageMetrics.speedStep)
    }

    @objc private func speedUp() {
        controller.setSpeed(controller.speedMultiplier + PrompterStageMetrics.speedStep)
    }

    @objc private func sizeDown() {
        controller.setFontSize(controller.fontSize - PrompterStageMetrics.operatorFontStep)
    }

    @objc private func sizeUp() {
        controller.setFontSize(controller.fontSize + PrompterStageMetrics.operatorFontStep)
    }

    @objc func liveTapped() {
        guard let liveActions else { return }
        if controller.isLive {
            liveActions.stopLive()
        } else {
            _ = liveActions.goLive()
        }
        refreshLiveButton()
    }

    @objc private func handlePan(_ pan: UIPanGestureRecognizer) {
        guard controller.canPlay else { return }
        switch pan.state {
        case .began:
            controller.beginScrub()
            panStartOffset = 0
        case .changed:
            let translation = pan.translation(in: stage).y
            // The engine wants the delta since the last event, in stage points
            // scaled into the canonical layout's line height.
            let scale = controller.lineHeight / max(1, PrompterStageMetrics.lineHeight(for: stage.font))
            controller.scrub(by: (translation - panStartOffset) * scale)
            panStartOffset = translation
        case .ended, .cancelled, .failed:
            let scale = controller.lineHeight / max(1, PrompterStageMetrics.lineHeight(for: stage.font))
            controller.endScrub(velocity: pan.velocity(in: stage).y * scale)
        default:
            break
        }
    }
}
