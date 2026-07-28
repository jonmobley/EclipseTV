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
/// Preview is staged in a 9:16 (Vertical) or 16:9 (Landscape) panel — the same
/// Display Mode aspect AirPlay uses — so framing matches the TV. Mode is set from
/// Home ⋯, not on this screen.
final class CameraLiveViewController: UIViewController {

    // MARK: - Subviews

    private let stageView: UIView = {
        let view = UIView()
        view.backgroundColor = .black
        view.clipsToBounds = true
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    private let panelView: UIView = {
        let view = UIView()
        view.backgroundColor = .black
        view.clipsToBounds = true
        return view
    }()

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

    private let modeLabel: UILabel = {
        let label = UILabel()
        label.textColor = UIColor.white.withAlphaComponent(0.75)
        label.font = .systemFont(ofSize: 13, weight: .medium)
        label.textAlignment = .center
        label.numberOfLines = 2
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
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

        view.addSubview(stageView)
        stageView.addSubview(panelView)
        panelView.addSubview(previewView)
        // Frame-driven like AirPlay camera — avoid Auto Layout fighting bounds.
        previewView.translatesAutoresizingMaskIntoConstraints = true
        view.addSubview(airPlayBanner)
        view.addSubview(controlsStack)

        controlsStack.addArrangedSubview(modeLabel)
        controlsStack.addArrangedSubview(stopButton)

        NSLayoutConstraint.activate([
            stageView.topAnchor.constraint(equalTo: view.topAnchor),
            stageView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            stageView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            stageView.bottomAnchor.constraint(equalTo: controlsStack.topAnchor, constant: -12),

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

        stopButton.addTarget(self, action: #selector(stopTapped), for: .touchUpInside)

        updateModeLabel()
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
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(outputSettingsChanged),
            name: ExternalOutputSettings.didChangeNotification,
            object: nil
        )
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        layoutPhoneCameraViewport()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        ExternalDisplayManager.shared.refreshConnection()
        updateAirPlayBanner()
        updateModeLabel()
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

    // MARK: - Viewport

    /// Stages the preview in a Display Mode aspect panel (no TV rotation on phone).
    private func layoutPhoneCameraViewport() {
        let bounds = stageView.bounds
        guard bounds.width > 0, bounds.height > 0 else { return }

        let panel = ExternalOutputSettings.displayModePanelRect(in: bounds)
        panelView.frame = panel

        // Same upright fill the TV uses inside its (possibly rotated) panel.
        PresentationViewController.applyRotatedLayout(
            to: previewView,
            in: panelView,
            scale: 1,
            rotationDegrees: 0
        )
    }

    // MARK: - Camera Session

    private func startCameraIfNeeded() {
        Task { @MainActor in
            let granted = await CameraManager.shared.checkPermissions()
            guard granted else {
                presentPermissionAlert()
                return
            }
            CameraManager.shared.prepareAndStart { [weak self] in
                guard let self else { return }
                // Attach after inputs exist so phone + AirPlay aren't blank.
                self.previewView.attach(
                    session: CameraManager.shared.captureSession,
                    videoGravity: .resizeAspect
                )
                self.layoutPhoneCameraViewport()
                ExternalDisplayManager.shared.presentCamera()
                self.updateAirPlayBanner()
            }
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

    @objc private func outputSettingsChanged() {
        updateModeLabel()
        layoutPhoneCameraViewport()
    }

    // MARK: - UI State

    private func updateModeLabel() {
        let mode = ExternalOutputSettings.orientation.rawValue
        if ExternalOutputSettings.isVerticalMode {
            let rotation = ExternalOutputSettings.rotationDirection.rawValue
            modeLabel.text = "Display Mode: \(mode) · \(rotation)\nChange in Settings"
        } else {
            modeLabel.text = "Display Mode: \(mode)\nChange in Settings"
        }
    }

    private func updateAirPlayBanner() {
        airPlayBanner.isHidden = ExternalDisplayManager.shared.isConnected
    }
}
