//
//  CameraLiveViewController.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import UIKit
import AVFoundation

/// Phone-side camera control: opens in preview, then Go Live for AirPlay.
///
/// Preview is staged in a 9:16 (Vertical) or 16:9 (Landscape) panel — the same
/// Display Mode aspect AirPlay uses — so framing matches the TV.
final class CameraLiveViewController: UIViewController {

    // MARK: - Subviews

    let stageView: UIView = {
        let view = UIView()
        view.backgroundColor = .black
        view.clipsToBounds = true
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    let panelView: UIView = {
        let view = UIView()
        view.backgroundColor = .black
        view.clipsToBounds = true
        return view
    }()

    let previewView = CameraPreviewView()

    /// PNG frame overlay (aspect-fit on the Display Mode panel).
    let frameOverlayView = UIImageView()
    let frameButton = UIButton(type: .system)

    /// Covers warm-up black until the capture session paints.
    private let freezeFrameView: UIImageView = {
        let view = UIImageView()
        view.contentMode = .scaleAspectFill
        view.clipsToBounds = true
        view.isUserInteractionEnabled = false
        return view
    }()

    let stopButton: UIButton = {
        var config = UIButton.Configuration.plain()
        let symbol = UIImage.SymbolConfiguration(pointSize: 14, weight: .semibold)
        config.image = UIImage(systemName: "stop.fill", withConfiguration: symbol)
        config.baseForegroundColor = .white
        config.background.backgroundColor = UIColor.black.withAlphaComponent(0.45)
        config.cornerStyle = .capsule
        config.contentInsets = NSDirectionalEdgeInsets(
            top: 10, leading: 10, bottom: 10, trailing: 10
        )
        let button = UIButton(configuration: config)
        button.accessibilityLabel = "Stop Camera"
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }()

    let closeButton: UIButton = {
        var config = UIButton.Configuration.plain()
        let symbol = UIImage.SymbolConfiguration(pointSize: 14, weight: .semibold)
        config.image = UIImage(systemName: "xmark", withConfiguration: symbol)
        config.baseForegroundColor = .white
        config.background.backgroundColor = UIColor.black.withAlphaComponent(0.45)
        config.cornerStyle = .capsule
        config.contentInsets = NSDirectionalEdgeInsets(
            top: 10, leading: 10, bottom: 10, trailing: 10
        )
        let button = UIButton(configuration: config)
        button.accessibilityLabel = "Close"
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }()

    let goLiveButton = UIButton(type: .system)
    let previewBanner = UILabel()

    /// Corner Logo thumbnail — tap to park/resume Logo on AirPlay (live only).
    let logoChip = CameraLogoChipView()

    /// When true, disappearing tears down the live camera (Stop).
    private var shouldStopOnDismiss = false
    /// Zoom factor at the start of the active pinch.
    private var pinchStartZoom: CGFloat = 1

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        modalPresentationStyle = .fullScreen

        view.addSubview(stageView)
        stageView.addSubview(panelView)
        panelView.addSubview(previewView)
        panelView.addSubview(freezeFrameView)
        previewView.translatesAutoresizingMaskIntoConstraints = true
        freezeFrameView.translatesAutoresizingMaskIntoConstraints = true
        view.addSubview(stopButton)
        view.addSubview(closeButton)
        setupPreviewChrome()
        setupLogoChip()
        setupFrameOverlay()

        let pinch = UIPinchGestureRecognizer(target: self, action: #selector(handlePinch(_:)))
        stageView.addGestureRecognizer(pinch)
        stageView.isUserInteractionEnabled = true

        NSLayoutConstraint.activate([
            stageView.topAnchor.constraint(equalTo: view.topAnchor),
            stageView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            stageView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            stageView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            stopButton.topAnchor.constraint(
                equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 12),
            stopButton.leadingAnchor.constraint(
                equalTo: view.leadingAnchor, constant: 16),
            stopButton.widthAnchor.constraint(equalToConstant: 44),
            stopButton.heightAnchor.constraint(equalToConstant: 44),

            closeButton.topAnchor.constraint(
                equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 12),
            closeButton.trailingAnchor.constraint(
                equalTo: view.trailingAnchor, constant: -16),
            closeButton.widthAnchor.constraint(equalToConstant: 44),
            closeButton.heightAnchor.constraint(equalToConstant: 44)
        ])

        stopButton.addTarget(self, action: #selector(stopTapped), for: .touchUpInside)
        closeButton.addTarget(self, action: #selector(closeTapped), for: .touchUpInside)

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
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(externalDisplayChanged),
            name: ExternalDisplayManager.didChangeNotification,
            object: nil
        )
        refreshLiveChrome()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        layoutPhoneCameraViewport()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        ExternalDisplayManager.shared.refreshConnection()
        refreshLiveChrome()
        showFreezeFrameIfNeeded()
        attachPreviewIfNeeded()
        startCameraPreviewIfNeeded()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        guard isBeingDismissed || isMovingFromParent else { return }
        CameraManager.shared.captureLastFrame(from: previewView)
        previewView.detach()

        let mgr = ExternalDisplayManager.shared
        if shouldStopOnDismiss, mgr.isCameraModeActive {
            mgr.stopCameraAndRestoreLibrary()
        } else if !mgr.isCameraModeActive {
            // Preview-only dismiss — never pushed camera to AirPlay.
            CameraManager.shared.stopSession()
        }
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    // MARK: - Viewport

    private func layoutPhoneCameraViewport() {
        let bounds = stageView.bounds
        guard bounds.width > 0, bounds.height > 0 else { return }

        let panel = ExternalOutputSettings.displayModePanelRect(in: bounds)
        panelView.frame = panel

        PresentationViewController.applyRotatedLayout(
            to: previewView,
            in: panelView,
            scale: 1,
            rotationDegrees: 0
        )
        freezeFrameView.frame = previewView.frame
        freezeFrameView.transform = previewView.transform
        layoutFrameOverlay()
        previewView.syncDisplayModeOrientation()
    }

    // MARK: - Camera Session

    private func showFreezeFrameIfNeeded() {
        guard !isAirPlayLive, let image = CameraManager.shared.lastFrame else {
            freezeFrameView.isHidden = true
            return
        }
        freezeFrameView.image = image
        freezeFrameView.alpha = 1
        freezeFrameView.isHidden = false
        panelView.bringSubviewToFront(freezeFrameView)
    }

    private func hideFreezeFrame() {
        guard !freezeFrameView.isHidden else { return }
        UIView.animate(withDuration: 0.2, animations: {
            self.freezeFrameView.alpha = 0
        }, completion: { _ in
            self.freezeFrameView.isHidden = true
            self.layoutFrameOverlay()
        })
    }

    private func attachPreviewIfNeeded() {
        let gravity: AVLayerVideoGravity =
            ExternalOutputSettings.isVerticalMode ? .resizeAspectFill : .resizeAspect
        previewView.attach(
            session: CameraManager.shared.captureSession,
            videoGravity: gravity
        )
        previewView.syncDisplayModeOrientation()
        layoutPhoneCameraViewport()
    }

    /// Starts capture for phone framing only — does not push AirPlay unless already live.
    private func startCameraPreviewIfNeeded() {
        Task { @MainActor in
            let granted = await CameraManager.shared.checkPermissions()
            guard granted else {
                presentPermissionAlert()
                return
            }
            CameraManager.shared.prepareAndStart { [weak self] in
                guard let self else { return }
                self.attachPreviewIfNeeded()
                self.refreshLiveChrome()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in
                    self?.hideFreezeFrame()
                }
            }
        }
    }

    private func presentPermissionAlert() {
        let alert = UIAlertController(
            title: "Camera Access Needed",
            message: "Enable camera access in Settings to use the camera.",
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

    @objc private func closeTapped() {
        shouldStopOnDismiss = false
        let mgr = ExternalDisplayManager.shared

        if !mgr.isCameraModeActive {
            // Preview only — just leave; session stops in viewWillDisappear.
            shouldStopOnDismiss = true
            dismiss(animated: true)
            return
        }

        // Live: apply Settings → When Camera Closes.
        if ExternalOutputSettings.cameraCloseDestination != .camera {
            CameraManager.shared.captureLastFrame(from: previewView)
            previewView.detach()
            mgr.stopCameraAndApplyCloseDestination()
        } else if mgr.isCameraParkedOnLogo {
            mgr.resumeCameraFromLogoPark()
        }
        dismiss(animated: true)
    }

    @objc private func stopTapped() {
        shouldStopOnDismiss = true
        dismiss(animated: true)
    }

    @objc private func cameraEndedExternally() {
        guard presentedViewController == nil else { return }
        shouldStopOnDismiss = false
        CameraManager.shared.captureLastFrame(from: previewView)
        previewView.detach()
        refreshLiveChrome()
        dismiss(animated: true)
    }

    @objc private func outputSettingsChanged() {
        attachPreviewIfNeeded()
    }

    @objc private func externalDisplayChanged() {
        refreshLiveChrome()
    }

    @objc private func handlePinch(_ gesture: UIPinchGestureRecognizer) {
        let camera = CameraManager.shared
        switch gesture.state {
        case .began:
            pinchStartZoom = camera.zoomFactor
        case .changed:
            camera.setZoomFactor(pinchStartZoom * gesture.scale)
        default:
            break
        }
    }
}
