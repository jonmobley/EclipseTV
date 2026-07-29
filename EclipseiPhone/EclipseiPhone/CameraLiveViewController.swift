//
//  CameraLiveViewController.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import UIKit
import AVFoundation

/// Phone-side camera control: preview first, slide shutter to go live on AirPlay.
///
/// Preview is staged in a 9:16 (Vertical) or 16:9 (Landscape) panel — the same
/// Display Mode aspect AirPlay uses — so framing matches the TV.
/// Both Display Modes slide the same way: right goes live, left leaves live.
/// While live, tap takes a photo and hold records video.
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
        view.layer.cornerRadius = 32
        // All four corners — Vertical full-width card and Landscape panel.
        view.layer.maskedCorners = [
            .layerMinXMinYCorner, .layerMaxXMinYCorner,
            .layerMinXMaxYCorner, .layerMaxXMaxYCorner
        ]
        return view
    }()

    let previewView = CameraPreviewView()

    /// PNG frame overlay (aspect-fit on the Display Mode panel).
    let frameOverlayView = UIImageView()

    /// Covers warm-up black until the capture session paints.
    private let freezeFrameView: UIImageView = {
        let view = UIImageView()
        view.contentMode = .scaleAspectFill
        view.clipsToBounds = true
        view.isUserInteractionEnabled = false
        return view
    }()

    /// Left chevron — dismisses like Website’s header back control.
    let backButton: UIButton = {
        var config = UIButton.Configuration.plain()
        let symbol = UIImage.SymbolConfiguration(pointSize: 15, weight: .semibold)
        config.image = UIImage(systemName: "chevron.backward", withConfiguration: symbol)
        config.baseForegroundColor = .white
        config.background.backgroundColor = UIColor.black.withAlphaComponent(0.45)
        config.cornerStyle = .capsule
        config.contentInsets = NSDirectionalEdgeInsets(
            top: 10, leading: 12, bottom: 10, trailing: 12
        )
        let button = UIButton(configuration: config)
        button.accessibilityLabel = "Back"
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }()

    /// Non-interactive LIVE badge shown in the top chrome while camera is on-air.
    let goLiveButton = UIButton(type: .system)

    /// Top-right gear — Frames and When Camera Closes.
    let settingsButton = UIButton(type: .system)

    /// Shared diameter for Settings / Flip circular controls.
    static let chromeControlSize: CGFloat = 44
    /// Shutter thumb diameter.
    static let shutterSize: CGFloat = 72
    /// Distance the shutter thumb travels along the live track.
    static let shutterTrackTravel: CGFloat = 56
    /// Inset between the track edge and the shutter thumb.
    static let shutterTrackPadding: CGFloat = 4
    /// Gap between panel bottom and shutter row in Vertical mode.
    static let verticalChromeGap: CGFloat = 16

    /// Horizontal track behind the shutter — right end is live, left end is off.
    let shutterTrackView: UIView = {
        let view = UIView()
        view.backgroundColor = UIColor.white.withAlphaComponent(0.14)
        view.clipsToBounds = true
        return view
    }()
    /// Chevron in the empty side of the track, pointing where the next slide goes.
    let shutterHintView: UIImageView = {
        let view = UIImageView()
        view.tintColor = .white
        view.contentMode = .center
        view.isUserInteractionEnabled = false
        return view
    }()
    /// Shutter thumb — slide to live; when live, tap = photo, hold = video.
    let shutterButton = UIButton(type: .system)
    /// Mock flip-to-selfie control (layout placeholder).
    let flipButton = UIButton(type: .system)
    /// Opens Photos after a capture has been saved.
    let libraryButton = UIButton(type: .system)

    /// 0 = off-live (left) end of the track, 1 = live (right) end.
    var shutterSlideProgress: CGFloat = 0
    /// True while the user is dragging the shutter thumb.
    var isShutterDragging = false
    /// True while the thumb animates to a committed end, so layout leaves it alone.
    var isShutterSettling = false
    /// Progress the active drag started from, captured once at `.began`.
    var shutterDragBaseProgress: CGFloat = 0
    /// Translation where the press became a slide, so the thumb tracks the finger 1:1.
    var shutterSlideAnchor: CGFloat = 0
    /// True once the current press moved enough to count as a slide.
    var shutterDidSlide = false
    /// Timer discriminating shutter tap vs hold-to-record (live only).
    var shutterHoldTimer: Timer?
    /// True once the hold threshold fires for the active shutter press.
    var shutterDidLongPress = false
    /// Rest frame for the shutter track (updated in bottom chrome layout).
    var shutterTrackFrame: CGRect = .zero
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
        view.addSubview(backButton)
        setupPreviewChrome()
        setupCaptureMocks()
        setupFrameOverlay()
        setupSettingsButton()

        let pinch = UIPinchGestureRecognizer(target: self, action: #selector(handlePinch(_:)))
        stageView.addGestureRecognizer(pinch)
        stageView.isUserInteractionEnabled = true

        // Top chrome is framed in `layoutTopChromeInPanel` inside the panel.
        backButton.translatesAutoresizingMaskIntoConstraints = true
        goLiveButton.translatesAutoresizingMaskIntoConstraints = true

        NSLayoutConstraint.activate([
            stageView.topAnchor.constraint(equalTo: view.topAnchor),
            stageView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            stageView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            stageView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])

        backButton.addTarget(self, action: #selector(closeTapped), for: .touchUpInside)

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
        requestDisplayModeGeometry()
        ExternalDisplayManager.shared.refreshConnection()
        refreshLiveChrome()
        showFreezeFrameIfNeeded()
        attachPreviewIfNeeded()
        startCameraPreviewIfNeeded()
    }

    /// Landscape Display Mode → landscape camera UI; Vertical → portrait.
    override var supportedInterfaceOrientations: UIInterfaceOrientationMask {
        ExternalOutputSettings.isVerticalMode ? .portrait : .landscape
    }

    override var preferredInterfaceOrientationForPresentation: UIInterfaceOrientation {
        ExternalOutputSettings.isVerticalMode ? .portrait : .landscapeRight
    }

    override var shouldAutorotate: Bool { true }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        guard isBeingDismissed || isMovingFromParent else { return }
        // Leaving the camera while holding the shutter would otherwise leave the movie
        // open with no UI left to stop it.
        CameraManager.shared.closeOutRecordingIfNeeded()
        CameraManager.shared.captureLastFrame(from: previewView)
        previewView.detach()
        // Back leaves AirPlay alone — stop-live is slide-off-shutter only.
        // Leave the session running for the home Camera tile warm preview.
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    // MARK: - Viewport

    private func layoutPhoneCameraViewport() {
        let bounds = stageView.bounds
        guard bounds.width > 0, bounds.height > 0 else { return }

        let panel = phoneCameraPanelRect(in: bounds)
        panelView.frame = panel
        layoutTopChromeInPanel()
        layoutBottomChromeInPanel()

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

    /// Display Mode panel inside the stage.
    ///
    /// Vertical (portrait UI): full-width 9:16, leaving room under the card for
    /// shutter / Flip / camera-roll. Landscape (landscape UI): largest centered
    /// 16:9 with chrome framed inside the panel.
    private func phoneCameraPanelRect(in bounds: CGRect) -> CGRect {
        let topInset = view.safeAreaInsets.top + 6
        let bottomInset = view.safeAreaInsets.bottom + 6
        let isVertical = ExternalOutputSettings.isVerticalMode
        // Vertical: reserve horizontal shutter track under the camera container.
        let chromeReserve: CGFloat = isVertical
            ? Self.verticalChromeGap + Self.shutterSize + 8
            : 0
        let sideInset: CGFloat = isVertical ? 0 : 12
        let aspect = ExternalOutputSettings.orientation.aspectRatio
        let available = CGRect(
            x: sideInset,
            y: topInset,
            width: max(0, bounds.width - sideInset * 2),
            height: max(0, bounds.height - topInset - bottomInset - chromeReserve)
        )
        guard available.width > 1, available.height > 1 else { return .zero }

        var width = available.width
        var height = width / aspect
        if height > available.height {
            height = available.height
            width = height * aspect
        }

        let x = available.midX - width / 2
        // Vertical: top-align under the status bar. Landscape: center in the stage.
        let y = isVertical
            ? available.minY
            : available.midY - height / 2
        return CGRect(x: x, y: y, width: width, height: height)
    }

    /// Asks the window scene to match Display Mode (Landscape ↔ landscape UI).
    func requestDisplayModeGeometry() {
        let mask: UIInterfaceOrientationMask =
            ExternalOutputSettings.isVerticalMode ? .portrait : .landscape
        guard let scene = view.window?.windowScene ??
                UIApplication.shared.connectedScenes
                .compactMap({ $0 as? UIWindowScene })
                .first(where: { $0.session.role == .windowApplication })
        else { return }
        scene.requestGeometryUpdate(.iOS(interfaceOrientations: mask)) { _ in }
        setNeedsUpdateOfSupportedInterfaceOrientations()
    }

    // MARK: - Camera Session

    private func showFreezeFrameIfNeeded() {
        // Home tile already warmed the session — show live immediately, no black hold.
        if CameraManager.shared.isSessionRunning {
            freezeFrameView.isHidden = true
            return
        }
        guard !isAirPlayLive,
              let image = CameraManager.shared.lastFrame,
              !CameraManager.isNearlyBlack(image)
        else {
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
        // Panel aspect matches Display Mode — fill the card in both modes.
        previewView.attach(
            session: CameraManager.shared.captureSession,
            videoGravity: .resizeAspectFill
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
                self.hideFreezeFrame()
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

    /// Leaves the camera screen (same as Website header back).
    @objc func closeTapped() {
        dismiss(animated: true)
    }

    @objc private func cameraEndedExternally() {
        guard presentedViewController == nil else { return }
        CameraManager.shared.captureLastFrame(from: previewView)
        previewView.detach()
        refreshLiveChrome()
        dismiss(animated: true)
    }

    @objc private func outputSettingsChanged() {
        requestDisplayModeGeometry()
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
