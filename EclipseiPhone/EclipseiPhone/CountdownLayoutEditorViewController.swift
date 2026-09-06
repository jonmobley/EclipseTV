//
//  CountdownLayoutEditorViewController.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import UIKit

/// Drag-and-pinch editor for a countdown clock's size and position on output.
final class CountdownLayoutEditorViewController: UIViewController,
    UIGestureRecognizerDelegate {

    private let item: ShowCountdown
    private var layout: CountdownClockLayout
    private var panStart = CountdownClockLayout.default
    private var pinchStartScale: Double = 1
    private var clockObserver: NSObjectProtocol?

    private let canvas = UIView()
    private let background = CountdownBackgroundView()
    private let clockLabel = UILabel()
    private let instructionLabel = UILabel()
    private let resetButton = UIButton(type: .system)

    /// Opens the editor for `item`.
    init(item: ShowCountdown) {
        self.item = item
        self.layout = item.layout
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        isModalInPresentation = true
        title = item.name
        navigationItem.leftBarButtonItem = UIBarButtonItem(
            barButtonSystemItem: .cancel,
            target: self,
            action: #selector(cancel)
        )
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            barButtonSystemItem: .done,
            target: self,
            action: #selector(save)
        )
        setupViews()
        setupGestures()
        observeClock()
        CountdownClockLayoutPreview.set(layout, for: item.id)
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        // Position is judged against the picture, so the canvas shows it too.
        background.apply(CountdownBackground.resolved(for: item.id).media)
        background.play()
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        background.stop()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        layoutCanvas()
        applyClock()
    }

    deinit {
        if let clockObserver {
            NotificationCenter.default.removeObserver(clockObserver)
        }
    }

    // MARK: - Gestures

    func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldReceive touch: UITouch
    ) -> Bool {
        guard gestureRecognizer is UIPanGestureRecognizer else { return true }
        let point = touch.location(in: canvas)
        return clockLabel.frame.insetBy(dx: -28, dy: -28).contains(point)
    }

    // MARK: - Private

    private func setupViews() {
        canvas.backgroundColor = UIColor(white: 0.06, alpha: 1)
        canvas.clipsToBounds = true
        canvas.layer.borderColor = UIColor.white.withAlphaComponent(0.18).cgColor
        canvas.layer.borderWidth = 1
        view.addSubview(canvas)

        background.translatesAutoresizingMaskIntoConstraints = false
        canvas.addSubview(background)
        NSLayoutConstraint.activate([
            background.topAnchor.constraint(equalTo: canvas.topAnchor),
            background.bottomAnchor.constraint(equalTo: canvas.bottomAnchor),
            background.leadingAnchor.constraint(equalTo: canvas.leadingAnchor),
            background.trailingAnchor.constraint(equalTo: canvas.trailingAnchor)
        ])

        clockLabel.textColor = .white
        clockLabel.textAlignment = .center
        clockLabel.numberOfLines = 1
        canvas.addSubview(clockLabel)

        instructionLabel.text = "Drag to move · Pinch to resize"
        instructionLabel.font = .systemFont(ofSize: 15, weight: .medium)
        instructionLabel.textColor = UIColor.white.withAlphaComponent(0.7)
        instructionLabel.textAlignment = .center
        instructionLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(instructionLabel)

        resetButton.setTitle("Reset Size & Position", for: .normal)
        resetButton.addTarget(self, action: #selector(resetLayout), for: .touchUpInside)
        resetButton.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(resetButton)

        NSLayoutConstraint.activate([
            resetButton.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            resetButton.bottomAnchor.constraint(
                equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -12
            ),
            instructionLabel.leadingAnchor.constraint(
                equalTo: view.leadingAnchor, constant: 20
            ),
            instructionLabel.trailingAnchor.constraint(
                equalTo: view.trailingAnchor, constant: -20
            ),
            instructionLabel.bottomAnchor.constraint(
                equalTo: resetButton.topAnchor, constant: -8
            )
        ])
    }

    private func layoutCanvas() {
        let bottomChrome: CGFloat = 88
        let maxRect = CGRect(
            x: 20,
            y: view.safeAreaInsets.top + 16,
            width: view.bounds.width - 40,
            height: view.bounds.height
                - view.safeAreaInsets.top
                - view.safeAreaInsets.bottom
                - bottomChrome
                - 16
        )
        guard maxRect.width > 1, maxRect.height > 1 else { return }
        let aspect = ExternalOutputSettings.orientation.aspectRatio
        let fitted = Self.aspectFitted(aspect, in: maxRect)
        canvas.frame = fitted
    }

    /// Largest rect of `aspect` (width ÷ height) centered in `bounds`.
    static func aspectFitted(_ aspect: CGFloat, in bounds: CGRect) -> CGRect {
        let boundsAspect = bounds.width / bounds.height
        let size: CGSize
        if boundsAspect > aspect {
            let height = bounds.height
            size = CGSize(width: height * aspect, height: height)
        } else {
            let width = bounds.width
            size = CGSize(width: width, height: width / aspect)
        }
        return CGRect(
            x: bounds.midX - size.width / 2,
            y: bounds.midY - size.height / 2,
            width: size.width,
            height: size.height
        )
    }

    private func setupGestures() {
        let pan = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
        pan.delegate = self
        canvas.addGestureRecognizer(pan)
        let pinch = UIPinchGestureRecognizer(
            target: self, action: #selector(handlePinch(_:))
        )
        pinch.delegate = self
        canvas.addGestureRecognizer(pinch)
    }

    private func observeClock() {
        clockObserver = NotificationCenter.default.addObserver(
            forName: CountdownController.didChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.applyClock()
        }
    }

    private func applyClock() {
        let clock = CountdownController.shared
        let isLive = clock.liveCountdownId == item.id
            && ExternalDisplayManager.shared.isCountdownLive
        let seconds = isLive ? clock.remaining : item.duration
        layout.apply(
            to: clockLabel,
            text: CountdownController.displayString(seconds: seconds),
            isExpired: isLive && seconds == 0,
            in: canvas.bounds
        )
    }

    private func publishPreview() {
        CountdownClockLayoutPreview.set(layout, for: item.id)
    }

    @objc private func handlePan(_ gesture: UIPanGestureRecognizer) {
        let text = clockLabel.text ?? "0:00"
        switch gesture.state {
        case .began:
            panStart = layout
        case .changed, .ended:
            layout = panStart.translating(
                by: gesture.translation(in: canvas),
                text: text,
                in: canvas.bounds
            )
            applyClock()
            publishPreview()
        default:
            break
        }
    }

    @objc private func handlePinch(_ gesture: UIPinchGestureRecognizer) {
        let text = clockLabel.text ?? "0:00"
        switch gesture.state {
        case .began:
            pinchStartScale = layout.scale
        case .changed, .ended:
            layout = layout.scaling(
                to: pinchStartScale * Double(gesture.scale),
                text: text,
                in: canvas.bounds
            )
            applyClock()
            publishPreview()
        default:
            break
        }
    }

    @objc private func resetLayout() {
        layout = .default
        applyClock()
        publishPreview()
    }

    @objc private func cancel() {
        CountdownClockLayoutPreview.set(nil, for: item.id)
        dismiss(animated: true)
    }

    @objc private func save() {
        CountdownStore.shared.setLayout(id: item.id, layout: layout)
        CountdownClockLayoutPreview.set(nil, for: item.id)
        dismiss(animated: true)
    }
}
