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
/// Capture chrome stays on the phone's physical bottom edge: under the panel in
/// Vertical, on the right of the panel in Landscape. Slide toward Flip → live.
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

    /// Stand-in preview for when AirPlay owns the session's one hardware preview layer.
    let mirrorView = CameraMirrorView()

    /// True while the panel is showing `mirrorView`; nil before the first routing pass.
    var isPreviewMirrored: Bool?

    /// Pending swap back to the hardware preview layer after stop-live.
    var previewHandoffWorkItem: DispatchWorkItem?

    /// PNG frame overlay (aspect-fit on the Display Mode panel).
    let frameOverlayView = UIImageView()

    /// Covers warm-up / preview-handoff black until the live source paints.
    let freezeFrameView: UIImageView = {
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

    /// Top-chrome status pill — "LIVE" while on-air; hidden when idle.
    let goLiveButton = UIButton(type: .system)

    /// Elapsed record time shown beside the LIVE badge while holding to record.
    let recordingTimerLabel: UILabel = {
        let label = UILabel()
        label.font = .monospacedDigitSystemFont(ofSize: 15, weight: .semibold)
        label.textColor = .white
        label.textAlignment = .left
        label.isHidden = true
        label.translatesAutoresizingMaskIntoConstraints = true
        label.layer.shadowColor = UIColor.black.cgColor
        label.layer.shadowOpacity = 0.45
        label.layer.shadowRadius = 2
        label.layer.shadowOffset = CGSize(width: 0, height: 1)
        return label
    }()

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
    /// Gap between the panel and the shutter chrome strip.
    static let chromeGap: CGFloat = 16

    /// Track behind the shutter — toward Flip is live, toward Frame is off.
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
    /// `.custom` so the control doesn't delay/cancel the zero-duration press gesture.
    let shutterButton = UIButton(type: .custom)
    /// Switches between the back and front cameras.
    let flipButton = UIButton(type: .system)
    /// Opens the frame drawer to pick, hide, import, or delete overlays.
    let frameButton = UIButton(type: .system)
    /// Show that receives captures taken here, when the camera was opened from one.
    var captureDestinationShowId: UUID?

    /// 0 = off-live end of the track, 1 = live end (toward Flip).
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
    /// Touch origin in `view` at shutter press `.began` (for slide axis delta).
    var shutterTouchOrigin: CGPoint = .zero
    /// Rest frame for the shutter track (updated in bottom chrome layout).
    var shutterTrackFrame: CGRect = .zero
    /// Wall-clock start of the active movie recording (drives the LIVE timer).
    var recordingStartedAt: Date?
    /// 0.25s tick while recording to refresh `recordingTimerLabel`.
    var recordingTickTimer: Timer?
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
        panelView.addSubview(mirrorView)
        panelView.addSubview(freezeFrameView)
        previewView.translatesAutoresizingMaskIntoConstraints = true
        mirrorView.translatesAutoresizingMaskIntoConstraints = true
        mirrorView.isHidden = true
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
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(recordingDidChange),
            name: CameraManager.recordingDidChangeNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(cameraPositionDidChange),
            name: CameraManager.cameraPositionDidChangeNotification,
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
        updateLivePreviewSource(force: true)
        startCameraPreviewIfNeeded()
    }

    /// Landscape Display Mode → landscape camera UI; Vertical → portrait.
    override var supportedInterfaceOrientations: UIInterfaceOrientationMask {
        ExternalOutputSettings.phoneOrientationMask
    }

    override var preferredInterfaceOrientationForPresentation: UIInterfaceOrientation {
        ExternalOutputSettings.preferredPhoneOrientation
    }

    override var shouldAutorotate: Bool { true }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        guard isBeingDismissed || isMovingFromParent else { return }
        // Safety net if dismiss bypassed `closeTapped` (interactive sheet, etc.).
        // Prefer the UI path so last-capture preview is updated when possible.
        if CameraManager.shared.isRecording {
            CameraManager.shared.closeOutRecordingIfNeeded()
        }
        stopRecordingTimer()
        shutterHoldTimer?.invalidate()
        shutterHoldTimer = nil
        CameraManager.shared.captureLastFrame(from: previewView)
        teardownLivePreviewSource()
        previewView.detach()
        // Leaving the control UI does not stop AirPlay — slide the shutter off
        // live for that. Session stays up for the home Camera tile warm preview.
    }

    @objc private func recordingDidChange() {
        // Lock / background stop goes through CameraManager (no UI completion) — pick
        // up the Caches preview so it still files into the Eclipse library.
        if !CameraManager.shared.isRecording,
           let url = CameraManager.shared.consumeInAppVideoPreviewURL() {
            // A system-stopped recording has no elapsed time to report; it still belongs
            // in the library rather than being dropped for it.
            fileMovieInLibrary(at: url, duration: 0)
        }
        refreshLiveChrome()
    }

    /// Flip rebuilds the preview connection — re-apply rotation on phone + mirror.
    @objc private func cameraPositionDidChange() {
        previewView.syncDisplayModeOrientation()
        layoutPhoneCameraViewport()
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    // MARK: - Viewport

    func layoutPhoneCameraViewport() {
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
        layoutMirrorView()
        layoutFrameOverlay()
        previewView.syncDisplayModeOrientation()
    }

    /// Display Mode panel inside the stage.
    ///
    /// Vertical: full-width 9:16 with a strip under the card for shutter chrome.
    /// Landscape: largest 16:9 with that same chrome on the right of the card — the
    /// physical bottom edge when the phone is held sideways.
    private func phoneCameraPanelRect(in bounds: CGRect) -> CGRect {
        let isVertical = ExternalOutputSettings.isVerticalMode
        // Track short side (+ gap) — under the panel in Vertical, beside it in Landscape.
        let chromeReserve = Self.chromeGap + Self.shutterSize + 8
        let aspect = ExternalOutputSettings.orientation.aspectRatio
        let available: CGRect
        if isVertical {
            let topInset = view.safeAreaInsets.top + 6
            let bottomInset = view.safeAreaInsets.bottom + 6
            available = CGRect(
                x: 0,
                y: topInset,
                width: bounds.width,
                height: max(0, bounds.height - topInset - bottomInset - chromeReserve)
            )
        } else {
            // Island / notch is on a short edge in landscape — honor leading safe area.
            let leading = max(view.safeAreaInsets.left, 12)
            let trailing = chromeReserve + max(view.safeAreaInsets.right, 6)
            // Same top/bottom inset so leftover space after fitting 16:9 splits evenly.
            let vertical = max(view.safeAreaInsets.top, view.safeAreaInsets.bottom) + 6
            available = CGRect(
                x: leading,
                y: vertical,
                width: max(0, bounds.width - leading - trailing),
                height: max(0, bounds.height - vertical * 2)
            )
        }
        guard available.width > 1, available.height > 1 else { return .zero }

        var width = available.width
        var height = width / aspect
        if height > available.height {
            height = available.height
            width = height * aspect
        }

        let x = available.midX - width / 2
        // Vertical: top-align for a fixed under-panel strip. Landscape: vertically center.
        let y = isVertical ? available.minY : available.midY - height / 2
        return CGRect(x: x, y: y, width: width, height: height)
    }

    /// Asks the window scene to match Display Mode (Landscape ↔ landscape UI).
    func requestDisplayModeGeometry() {
        requestDisplayModeSceneGeometry()
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

    /// Fades out the freeze cover once the live preview source is painting.
    func hideFreezeFrame() {
        guard !freezeFrameView.isHidden else { return }
        UIView.animate(withDuration: 0.15, animations: {
            self.freezeFrameView.alpha = 0
        }, completion: { _ in
            self.freezeFrameView.isHidden = true
            self.layoutFrameOverlay()
        })
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
                self.updateLivePreviewSource(force: true)
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
    ///
    /// If a movie is in flight, finishes and saves it first so Back never orphans
    /// a recording. AirPlay stays live when already live — only the shutter stops
    /// that; the home tile keeps the warm session.
    @objc func closeTapped() {
        shutterHoldTimer?.invalidate()
        shutterHoldTimer = nil
        shutterDidLongPress = false
        isShutterDragging = false
        if CameraManager.shared.isRecording {
            finalizeRecordingIfNeeded { [weak self] in
                self?.dismiss(animated: true)
            }
            return
        }
        dismiss(animated: true)
    }

    @objc private func cameraEndedExternally() {
        guard presentedViewController == nil else { return }
        shutterHoldTimer?.invalidate()
        shutterHoldTimer = nil
        finalizeRecordingIfNeeded { [weak self] in
            guard let self else { return }
            CameraManager.shared.captureLastFrame(from: self.previewView)
            self.teardownLivePreviewSource()
            self.previewView.detach()
            self.refreshLiveChrome()
            self.dismiss(animated: true)
        }
    }

    @objc private func outputSettingsChanged() {
        requestDisplayModeGeometry()
        updateLivePreviewSource(force: true)
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
