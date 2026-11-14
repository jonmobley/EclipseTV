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
    let speedSlider = ScrollSpeedSlider()
    let sizeDownButton = UIButton(configuration: .plain())
    let sizeUpButton = UIButton(configuration: .plain())
    let liveButton = UIButton(configuration: .tinted())
    let emptyLabel = UILabel()
    let emptyEditButton = UIButton(configuration: .filled())

    private let controller: PrompterController
    private let transport = UIVisualEffectView(effect: UIBlurEffect(style: .systemThickMaterialDark))
    private var observers: [NSObjectProtocol] = []
    private var panStartOffset: CGFloat = 0
    private var transportRows: UIStackView?
    private var verticalRowConstraints: [NSLayoutConstraint] = []

    /// Landscape / Vertical switch for the Prompter's own shape. Hidden while Display
    /// Mode is Vertical, which already makes it 9:16.
    let shapeItem = UIBarButtonItem()

    /// Card inset from the screen edges.
    static let cardInset: CGFloat = 12

    /// True once this screen covers the grid and holds the phone to the Display Mode
    /// orientation (the browser does the same): a 16:9 card on a turned phone, not a
    /// strip across a portrait one. iPad keeps whatever orientation it is in.
    var holdsDisplayModeOrientation = false
    private var isLeaving = false

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
        navigationItem.rightBarButtonItems = [edit, shapeItem]

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
        // Turn only now that this screen covers the grid.
        holdsDisplayModeOrientation = true
        requestPrompterSceneGeometry()
    }

    /// Orientations that match the Prompter's shape (Vertical or Landscape).
    private var prompterOrientationMask: UIInterfaceOrientationMask {
        controller.isVertical ? .portrait : .landscape
    }

    /// Turns the phone to the Prompter's shape, like `requestDisplayModeSceneGeometry`.
    private func requestPrompterSceneGeometry() {
        setNeedsUpdateOfSupportedInterfaceOrientations()
        guard traitCollection.userInterfaceIdiom == .phone, let scene = view.window?.windowScene else { return }
        scene.requestGeometryUpdate(.iOS(interfaceOrientations: prompterOrientationMask)) { _ in }
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        UIApplication.shared.isIdleTimerDisabled = false
        if isBeingDismissed || isMovingFromParent { isLeaving = true }
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        guard isLeaving else { return }
        restoreUprightSceneGeometry()
    }

    override func viewWillLayoutSubviews() {
        super.viewWillLayoutSubviews()
        // One row when the phone is on its side, so the card keeps its height.
        let compact = traitCollection.verticalSizeClass == .compact
        if let rows = transportRows, rows.axis != (compact ? .horizontal : .vertical) {
            rows.axis = compact ? .horizontal : .vertical
            rows.spacing = compact ? 24 : 8
            verticalRowConstraints.forEach { $0.isActive = !compact }
        }
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        layoutStageCard()
    }

    /// The show-format card (16:9, or 9:16 in Vertical mode) between the bar and the
    /// transport, centred. What the display shows, at the card's size.
    private func layoutStageCard() {
        let top = view.safeAreaInsets.top
        let bottom = transport.frame.minY > 0 ? transport.frame.minY : view.bounds.maxY
        let available = CGRect(
            x: view.safeAreaInsets.left,
            y: top,
            width: view.bounds.width - view.safeAreaInsets.left - view.safeAreaInsets.right,
            height: bottom - top
        ).insetBy(dx: Self.cardInset, dy: Self.cardInset)
        guard available.width > 1, available.height > 1 else { return }
        stage.frame = ExternalOutputSettings.panelRect(in: available, aspect: controller.canvasAspectRatio)
        stage.layer.cornerRadius = 24
        // A faint edge so the show's frame reads on the black background.
        stage.layer.borderWidth = 1
        stage.layer.borderColor = UIColor.white.withAlphaComponent(0.22).cgColor
        // Hidden until a phone has turned to the Display Mode orientation, so a 16:9
        // card never flashes as a strip across a portrait screen.
        let fits = BrowserOrientationFit.matches(
            bounds: view.bounds.size,
            isVertical: controller.isVertical,
            idiom: traitCollection.userInterfaceIdiom
        )
        stage.alpha = fits ? 1 : 0
        emptyStack?.alpha = fits ? 1 : 0
    }

    override var supportedInterfaceOrientations: UIInterfaceOrientationMask {
        holdsDisplayModeOrientation ? prompterOrientationMask : .allButUpsideDown
    }

    override var preferredInterfaceOrientationForPresentation: UIInterfaceOrientation {
        guard !holdsDisplayModeOrientation else { return controller.isVertical ? .portrait : .landscapeRight }
        let current = view.phoneInterfaceOrientation
        return current == .portraitUpsideDown ? .portrait : current
    }

    override var shouldAutorotate: Bool { true }

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
        stage.translatesAutoresizingMaskIntoConstraints = true
        stage.setCanvasFontSize(controller.fontSize, isVertical: controller.isVertical)
        stage.onMetricsChange = { [weak self] size in
            self?.controller.updateStage(width: size.width, viewportHeight: size.height)
        }
        view.addSubview(stage)
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
        // Keep "Go Live" on one line in the upright bar, where the row is narrow.
        liveButton.setContentCompressionResistancePriority(.required, for: .horizontal)

        speedSlider.translatesAutoresizingMaskIntoConstraints = false
        speedSlider.onSpeedChange = { [weak self] speed in self?.controller.setSpeed(speed) }

        configure(sizeDownButton, symbol: "textformat.size.smaller", label: "Smaller Text", action: #selector(sizeDown))
        configure(sizeUpButton, symbol: "textformat.size.larger", label: "Larger Text", action: #selector(sizeUp))

        let sizeGroup = UIStackView(arrangedSubviews: [sizeDownButton, sizeUpButton])
        sizeGroup.spacing = 2
        let topRow = UIStackView(arrangedSubviews: [resetButton, playButton, liveButton])
        topRow.spacing = 20
        topRow.alignment = .center
        // Even gaps, not even centres: centring Play squeezed "Go Live" into a
        // column of letters on an upright phone.
        topRow.distribution = .equalSpacing
        let bottomRow = UIStackView(arrangedSubviews: [speedSlider, sizeGroup])
        bottomRow.spacing = 16
        bottomRow.alignment = .center
        bottomRow.distribution = .equalCentering

        let rows = UIStackView(arrangedSubviews: [topRow, bottomRow])
        rows.axis = .vertical
        rows.spacing = 8
        rows.alignment = .center
        rows.translatesAutoresizingMaskIntoConstraints = false
        transport.contentView.addSubview(rows)
        transportRows = rows
        verticalRowConstraints = [
            topRow.widthAnchor.constraint(equalTo: rows.widthAnchor),
            bottomRow.widthAnchor.constraint(equalTo: rows.widthAnchor)
        ]
        NSLayoutConstraint.activate(verticalRowConstraints)

        NSLayoutConstraint.activate([
            transport.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            transport.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            transport.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            rows.topAnchor.constraint(equalTo: transport.contentView.topAnchor, constant: 10),
            rows.centerXAnchor.constraint(equalTo: transport.contentView.centerXAnchor),
            rows.leadingAnchor.constraint(greaterThanOrEqualTo: transport.contentView.safeAreaLayoutGuide.leadingAnchor, constant: 16),
            rows.trailingAnchor.constraint(lessThanOrEqualTo: transport.contentView.safeAreaLayoutGuide.trailingAnchor, constant: -16),
            rows.bottomAnchor.constraint(equalTo: transport.contentView.safeAreaLayoutGuide.bottomAnchor, constant: -10),
            speedSlider.widthAnchor.constraint(greaterThanOrEqualToConstant: 200),
            speedSlider.widthAnchor.constraint(lessThanOrEqualToConstant: ScrollSpeedSlider.maximumWidth)
        ])
        // As wide as the website's bar when the screen allows; narrower phones
        // squeeze it toward the minimum through the row's edge constraints.
        let preferred = speedSlider.widthAnchor.constraint(equalToConstant: ScrollSpeedSlider.maximumWidth)
        preferred.priority = .defaultLow
        preferred.isActive = true
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
        stage.setCanvasFontSize(controller.fontSize, isVertical: controller.isVertical)
        let empty = !controller.canPlay
        emptyStack?.isHidden = !empty
        stage.showsReadingGuide = !empty
        playButton.isEnabled = !empty
        resetButton.isEnabled = !empty
        playButton.configuration?.image = UIImage(systemName: controller.isPlaying ? "pause.fill" : "play.fill")
        playButton.accessibilityLabel = controller.isPlaying ? "Pause" : "Play"
        speedSlider.apply(speed: controller.speedMultiplier)
        sizeDownButton.isEnabled = controller.fontSize > PrompterStageMetrics.canvasFontRange.lowerBound
        sizeUpButton.isEnabled = controller.fontSize < PrompterStageMetrics.canvasFontRange.upperBound
        refreshLiveButton()
        refreshShapeItem()
        applyAnchor()
    }

    private var lastShapeIsVertical: Bool?

    private func refreshShapeItem() {
        let vertical = controller.isVertical
        shapeItem.isHidden = ExternalOutputSettings.isVerticalMode
        shapeItem.image = UIImage(systemName: vertical ? "rectangle.portrait" : "rectangle")
        shapeItem.accessibilityLabel = "Prompter Shape"
        shapeItem.accessibilityValue = vertical ? "Vertical" : "Landscape"
        shapeItem.menu = UIMenu(title: "Prompter Shape", options: .singleSelection, children: [
            UIAction(
                title: "Landscape", image: UIImage(systemName: "rectangle"),
                state: vertical ? .off : .on
            ) { [weak self] _ in self?.controller.setPrefersVertical(false) },
            UIAction(
                title: "Vertical", image: UIImage(systemName: "rectangle.portrait"),
                state: vertical ? .on : .off
            ) { [weak self] _ in self?.controller.setPrefersVertical(true) }
        ])
        // On a change, turn the phone and re-fit the card to the new shape.
        defer { lastShapeIsVertical = vertical }
        guard let last = lastShapeIsVertical, last != vertical else { return }
        view.setNeedsLayout()
        if holdsDisplayModeOrientation { requestPrompterSceneGeometry() }
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

    @objc private func sizeDown() {
        controller.setFontSize(controller.fontSize - PrompterStageMetrics.canvasFontStep)
    }

    @objc private func sizeUp() {
        controller.setFontSize(controller.fontSize + PrompterStageMetrics.canvasFontStep)
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
            // Card points → canonical layout points (both are the same canvas).
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
