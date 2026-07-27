//
//  WebRemoteViewController.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import UIKit

/// Phone-side remote for a page presented on the AirPlay display.
///
/// Scroll pad pans forward scroll deltas; Top / Reload / Text Size / orientation
/// controls mirror to the external `WKWebView`. No on-phone page preview.
final class WebRemoteViewController: UIViewController {

    // MARK: - Properties

    private let page: WebPage
    private var lastPanTranslation: CGPoint = .zero

    // MARK: - Subviews

    private let titleLabel: UILabel = {
        let label = UILabel()
        label.font = .systemFont(ofSize: 22, weight: .bold)
        label.textAlignment = .center
        label.numberOfLines = 2
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    private let urlLabel: UILabel = {
        let label = UILabel()
        label.font = .systemFont(ofSize: 14, weight: .regular)
        label.textColor = .secondaryLabel
        label.textAlignment = .center
        label.numberOfLines = 2
        label.lineBreakMode = .byTruncatingMiddle
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    private let airPlayBanner: UILabel = {
        let label = UILabel()
        label.text = "Connect AirPlay to show on TV"
        label.textColor = .white
        label.font = .systemFont(ofSize: 14, weight: .semibold)
        label.textAlignment = .center
        label.backgroundColor = UIColor.black.withAlphaComponent(0.55)
        label.layer.cornerRadius = 10
        label.layer.masksToBounds = true
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    private let scrollPad: UIView = {
        let view = UIView()
        view.backgroundColor = UIColor.secondarySystemFill
        view.layer.cornerRadius = 16
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    private let scrollHint: UILabel = {
        let label = UILabel()
        label.text = "Swipe to scroll"
        label.font = .systemFont(ofSize: 16, weight: .medium)
        label.textColor = .secondaryLabel
        label.textAlignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    private let topButton = WebRemoteViewController.makeSecondaryButton(title: "Top")
    private let reloadButton = WebRemoteViewController.makeSecondaryButton(title: "Reload")

    private let textSizeControl: UISegmentedControl = {
        let control = UISegmentedControl(items: WebTextSize.allCases.map(\.rawValue))
        control.selectedSegmentIndex = WebTextSize.allCases
            .firstIndex(of: ExternalOutputSettings.webTextSize) ?? 1
        control.translatesAutoresizingMaskIntoConstraints = false
        return control
    }()

    private let orientationControl: UISegmentedControl = {
        let control = UISegmentedControl(items: ExternalOutputOrientation.allCases.map(\.rawValue))
        control.selectedSegmentIndex = ExternalOutputOrientation.allCases
            .firstIndex(of: ExternalOutputSettings.orientation) ?? 0
        control.translatesAutoresizingMaskIntoConstraints = false
        return control
    }()

    private let rotationControl: UISegmentedControl = {
        let control = UISegmentedControl(
            items: ExternalRotationDirection.allCases.map(\.rawValue))
        control.selectedSegmentIndex = ExternalRotationDirection.allCases
            .firstIndex(of: ExternalOutputSettings.rotationDirection) ?? 0
        control.translatesAutoresizingMaskIntoConstraints = false
        return control
    }()

    private let stopButton: UIButton = {
        var config = UIButton.Configuration.filled()
        config.title = "Stop"
        config.baseBackgroundColor = .systemRed
        config.baseForegroundColor = .white
        config.cornerStyle = .large
        config.contentInsets = NSDirectionalEdgeInsets(
            top: 14, leading: 24, bottom: 14, trailing: 24)
        let button = UIButton(configuration: config)
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }()

    private let controlsStack: UIStackView = {
        let stack = UIStackView()
        stack.axis = .vertical
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false
        return stack
    }()

    // MARK: - Init

    /// Creates a remote for the given saved page.
    init(page: WebPage) {
        self.page = page
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        title = "Remote"
        navigationItem.largeTitleDisplayMode = .never

        titleLabel.text = page.title
        urlLabel.text = page.url.absoluteString

        let actionRow = UIStackView(arrangedSubviews: [topButton, reloadButton])
        actionRow.axis = .horizontal
        actionRow.spacing = 12
        actionRow.distribution = .fillEqually

        scrollPad.addSubview(scrollHint)
        view.addSubview(titleLabel)
        view.addSubview(urlLabel)
        view.addSubview(airPlayBanner)
        view.addSubview(scrollPad)
        view.addSubview(controlsStack)

        controlsStack.addArrangedSubview(actionRow)
        controlsStack.addArrangedSubview(textSizeControl)
        controlsStack.addArrangedSubview(orientationControl)
        controlsStack.addArrangedSubview(rotationControl)
        controlsStack.addArrangedSubview(stopButton)

        NSLayoutConstraint.activate([
            titleLabel.topAnchor.constraint(
                equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 12),
            titleLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 24),
            titleLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -24),

            urlLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 4),
            urlLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 24),
            urlLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -24),

            airPlayBanner.topAnchor.constraint(equalTo: urlLabel.bottomAnchor, constant: 12),
            airPlayBanner.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            airPlayBanner.leadingAnchor.constraint(
                greaterThanOrEqualTo: view.leadingAnchor, constant: 24),
            airPlayBanner.trailingAnchor.constraint(
                lessThanOrEqualTo: view.trailingAnchor, constant: -24),
            airPlayBanner.heightAnchor.constraint(equalToConstant: 36),
            airPlayBanner.widthAnchor.constraint(greaterThanOrEqualToConstant: 240),

            scrollPad.topAnchor.constraint(equalTo: airPlayBanner.bottomAnchor, constant: 16),
            scrollPad.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 24),
            scrollPad.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -24),
            scrollPad.bottomAnchor.constraint(
                equalTo: controlsStack.topAnchor, constant: -16),

            scrollHint.centerXAnchor.constraint(equalTo: scrollPad.centerXAnchor),
            scrollHint.centerYAnchor.constraint(equalTo: scrollPad.centerYAnchor),

            controlsStack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 24),
            controlsStack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -24),
            controlsStack.bottomAnchor.constraint(
                equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -16)
        ])

        let pan = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
        scrollPad.addGestureRecognizer(pan)

        topButton.addTarget(self, action: #selector(topTapped), for: .touchUpInside)
        reloadButton.addTarget(self, action: #selector(reloadTapped), for: .touchUpInside)
        textSizeControl.addTarget(self, action: #selector(textSizeChanged), for: .valueChanged)
        orientationControl.addTarget(
            self, action: #selector(orientationChanged), for: .valueChanged)
        rotationControl.addTarget(self, action: #selector(rotationChanged), for: .valueChanged)
        stopButton.addTarget(self, action: #selector(stopTapped), for: .touchUpInside)

        updateRotationVisibility()
        updateAirPlayBanner()

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(externalDisplayChanged),
            name: ExternalDisplayManager.didChangeNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(webEndedExternally),
            name: ExternalDisplayManager.webDidEndNotification,
            object: nil
        )
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        if isMovingFromParent || isBeingDismissed,
           ExternalDisplayManager.shared.isWebLive {
            ExternalDisplayManager.shared.stopWebAndRestoreLibrary()
        }
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    // MARK: - Actions

    @objc private func handlePan(_ gesture: UIPanGestureRecognizer) {
        switch gesture.state {
        case .began:
            lastPanTranslation = .zero
        case .changed:
            let translation = gesture.translation(in: scrollPad)
            let deltaY = translation.y - lastPanTranslation.y
            lastPanTranslation = translation
            // Invert so dragging up scrolls the page down (natural feel).
            ExternalDisplayManager.shared.scrollWeb(by: CGPoint(x: 0, y: -deltaY))
        default:
            break
        }
    }

    @objc private func topTapped() {
        ExternalDisplayManager.shared.scrollWebToTop()
    }

    @objc private func reloadTapped() {
        ExternalDisplayManager.shared.reloadWeb()
    }

    @objc private func textSizeChanged() {
        let index = textSizeControl.selectedSegmentIndex
        guard WebTextSize.allCases.indices.contains(index) else { return }
        ExternalOutputSettings.webTextSize = WebTextSize.allCases[index]
    }

    @objc private func orientationChanged() {
        let index = orientationControl.selectedSegmentIndex
        guard ExternalOutputOrientation.allCases.indices.contains(index) else { return }
        ExternalOutputSettings.orientation = ExternalOutputOrientation.allCases[index]
        updateRotationVisibility()
    }

    @objc private func rotationChanged() {
        let index = rotationControl.selectedSegmentIndex
        guard ExternalRotationDirection.allCases.indices.contains(index) else { return }
        ExternalOutputSettings.rotationDirection = ExternalRotationDirection.allCases[index]
    }

    @objc private func stopTapped() {
        ExternalDisplayManager.shared.stopWebAndRestoreLibrary()
        navigationController?.popViewController(animated: true)
    }

    @objc private func externalDisplayChanged() {
        updateAirPlayBanner()
    }

    @objc private func webEndedExternally() {
        navigationController?.popViewController(animated: true)
    }

    // MARK: - UI State

    private func updateRotationVisibility() {
        rotationControl.isHidden = ExternalOutputSettings.orientation != .portrait
    }

    private func updateAirPlayBanner() {
        airPlayBanner.isHidden = ExternalDisplayManager.shared.isConnected
    }

    // MARK: - Helpers

    private static func makeSecondaryButton(title: String) -> UIButton {
        var config = UIButton.Configuration.gray()
        config.title = title
        config.cornerStyle = .large
        config.contentInsets = NSDirectionalEdgeInsets(
            top: 12, leading: 16, bottom: 12, trailing: 16)
        let button = UIButton(configuration: config)
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }
}
