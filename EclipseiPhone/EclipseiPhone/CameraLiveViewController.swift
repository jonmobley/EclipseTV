//
//  CameraLiveViewController.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import UIKit
import AVFoundation

/// Phone-side control surface for AirPlay camera presentation.
///
/// Shows a live preview, output orientation controls, and Stop. The external
/// display receives a chrome-free feed via `ExternalDisplayManager`.
final class CameraLiveViewController: UIViewController {

    // MARK: - Subviews

    private let previewView = CameraPreviewView()

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

    private let orientationControl: UISegmentedControl = {
        let control = UISegmentedControl(items: ExternalOutputOrientation.allCases.map(\.rawValue))
        control.selectedSegmentIndex = ExternalOutputOrientation.allCases
            .firstIndex(of: ExternalOutputSettings.orientation) ?? 0
        control.translatesAutoresizingMaskIntoConstraints = false
        return control
    }()

    private let rotationControl: UISegmentedControl = {
        let items = ExternalRotationDirection.allCases.map(\.rawValue)
        let control = UISegmentedControl(items: items)
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
        config.contentInsets = NSDirectionalEdgeInsets(top: 14, leading: 24, bottom: 14, trailing: 24)
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

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        modalPresentationStyle = .fullScreen

        previewView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(previewView)
        view.addSubview(airPlayBanner)
        view.addSubview(controlsStack)

        controlsStack.addArrangedSubview(orientationControl)
        controlsStack.addArrangedSubview(rotationControl)
        controlsStack.addArrangedSubview(stopButton)

        NSLayoutConstraint.activate([
            previewView.topAnchor.constraint(equalTo: view.topAnchor),
            previewView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            previewView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            previewView.trailingAnchor.constraint(equalTo: view.trailingAnchor),

            airPlayBanner.topAnchor.constraint(
                equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 16),
            airPlayBanner.leadingAnchor.constraint(
                greaterThanOrEqualTo: view.leadingAnchor, constant: 24),
            airPlayBanner.trailingAnchor.constraint(
                lessThanOrEqualTo: view.trailingAnchor, constant: -24),
            airPlayBanner.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            airPlayBanner.heightAnchor.constraint(equalToConstant: 36),
            airPlayBanner.widthAnchor.constraint(greaterThanOrEqualToConstant: 240),

            controlsStack.leadingAnchor.constraint(
                equalTo: view.leadingAnchor, constant: 24),
            controlsStack.trailingAnchor.constraint(
                equalTo: view.trailingAnchor, constant: -24),
            controlsStack.bottomAnchor.constraint(
                equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -20)
        ])

        orientationControl.addTarget(self, action: #selector(orientationChanged),
                                     for: .valueChanged)
        rotationControl.addTarget(self, action: #selector(rotationChanged),
                                  for: .valueChanged)
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
            selector: #selector(cameraEndedExternally),
            name: ExternalDisplayManager.cameraDidEndNotification,
            object: nil
        )
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        startCameraIfNeeded()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        if isBeingDismissed || isMovingFromParent {
            previewView.detach()
            if ExternalDisplayManager.shared.isCameraLive {
                ExternalDisplayManager.shared.stopCameraAndRestoreLibrary()
            }
        }
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    // MARK: - Camera Session

    private func startCameraIfNeeded() {
        Task { @MainActor in
            let granted = await CameraManager.shared.checkPermissions()
            guard granted else {
                presentPermissionAlert()
                return
            }
            CameraManager.shared.configureSession()
            previewView.attach(
                session: CameraManager.shared.captureSession,
                videoGravity: .resizeAspect
            )
            CameraManager.shared.startSession()
            ExternalDisplayManager.shared.presentCamera()
            updateAirPlayBanner()
        }
    }

    private func presentPermissionAlert() {
        let alert = UIAlertController(
            title: "Camera Access Needed",
            message: "Enable camera access in Settings to present a live feed on your TV.",
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel) { [weak self] _ in
            self?.dismiss(animated: true)
        })
        alert.addAction(UIAlertAction(title: "Open Settings", style: .default) { _ in
            if let url = URL(string: UIApplication.openSettingsURLString) {
                UIApplication.shared.open(url)
            }
        })
        present(alert, animated: true)
    }

    // MARK: - Actions

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
        previewView.detach()
        ExternalDisplayManager.shared.stopCameraAndRestoreLibrary()
        dismiss(animated: true)
    }

    @objc private func externalDisplayChanged() {
        updateAirPlayBanner()
    }

    @objc private func cameraEndedExternally() {
        guard presentedViewController == nil else { return }
        previewView.detach()
        dismiss(animated: true)
    }

    // MARK: - UI State

    private func updateRotationVisibility() {
        rotationControl.isHidden = ExternalOutputSettings.orientation != .portrait
    }

    private func updateAirPlayBanner() {
        airPlayBanner.isHidden = ExternalDisplayManager.shared.isConnected
    }
}
