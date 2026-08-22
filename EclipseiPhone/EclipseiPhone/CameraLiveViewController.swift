//
//  CameraLiveViewController.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import UIKit
import AVFoundation

/// Phone-side camera control: Display Mode preview, tap to toggle live.
///
/// The preview is the largest 16:9 / 9:16 panel that fits the stage (edge contact
/// where the aspect allows). The shutter row sits outside that panel, like the
/// system Camera app. Shutter always captures: tap = photo, hold = record
/// (except Always Record When Live, which owns recording while on-air).
/// Tap the stage to go live or stop — with a display that is AirPlay; without
/// one, Camera still goes live on the phone.
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

    /// Top-right gear — Recording, Frames, and When Camera Closes.
    let settingsButton = UIButton(type: .system)

    /// Shared diameter for Settings / Flip circular controls.
    static let chromeControlSize: CGFloat = 44
    /// Shutter button diameter.
    static let shutterSize: CGFloat = 72
    /// Gap between the Display Mode panel and the outside shutter strip.
    static let chromeGap: CGFloat = 16

    /// Shutter — tap = photo, hold = video (preview or live).
    /// `.custom` so the control doesn't delay/cancel the zero-duration press gesture.
    let shutterButton = UIButton(type: .custom)
    /// Switches between the back and front cameras.
    let flipButton = UIButton(type: .system)
    /// Opens the frame library to choose which overlays appear on the ribbon.
    let frameButton = UIButton(type: .system)
    /// Overlay-frame thumbnails beside the cutaway still. Tap makes a frame live.
    let frameRibbonView: UICollectionView = {
        let layout = UICollectionViewFlowLayout()
        layout.scrollDirection = .horizontal
        layout.minimumInteritemSpacing = 8
        layout.minimumLineSpacing = 8
        let view = UICollectionView(frame: .zero, collectionViewLayout: layout)
        view.backgroundColor = .clear
        view.showsHorizontalScrollIndicator = false
        view.alwaysBounceHorizontal = true
        view.clipsToBounds = false
        view.contentInsetAdjustmentBehavior = .never
        view.delaysContentTouches = false
        view.translatesAutoresizingMaskIntoConstraints = true
        return view
    }()
    /// Program thumb of what's on AirPlay while this camera is still preview-only.
    let liveOutputThumbView = CameraLiveOutputThumbView()
    /// Cutaway still thumbnail — tap parks that photo (AirPlay, or locally).
    let alternateStillButton = UIButton(type: .custom)
    /// Aspect-fill photo inside `alternateStillButton` (Background when none chosen).
    let alternateStillImageView: UIImageView = {
        let view = UIImageView()
        view.contentMode = .scaleAspectFill
        view.clipsToBounds = true
        view.isUserInteractionEnabled = false
        view.translatesAutoresizingMaskIntoConstraints = false
        view.isHidden = true
        return view
    }()
    /// Full-panel still while the cutaway is parked with no external display.
    let cutawayCoverView: UIImageView = {
        let view = UIImageView()
        view.contentMode = .scaleAspectFill
        view.clipsToBounds = true
        view.isUserInteractionEnabled = false
        view.isHidden = true
        view.translatesAutoresizingMaskIntoConstraints = true
        return view
    }()
    /// Show that receives captures taken here, when the camera was opened from one.
    var captureDestinationShowId: UUID?

    /// Timer discriminating shutter tap vs hold-to-record.
    var shutterHoldTimer: Timer?
    /// True once the hold threshold fires for the active shutter press.
    var shutterDidLongPress = false
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
        setupAlternateStillButton()
        setupLiveOutputThumb()
        setupFrameRibbon()
        setupFrameOverlay()
        setupSettingsButton()

        let pinch = UIPinchGestureRecognizer(target: self, action: #selector(handlePinch(_:)))
        stageView.addGestureRecognizer(pinch)
        let stageTap = UITapGestureRecognizer(target: self, action: #selector(handleStageTap(_:)))
        stageTap.cancelsTouchesInView = false
        stageView.addGestureRecognizer(stageTap)
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
        // Leaving the control UI does not stop AirPlay — tap the stage off live
        // for that. Session stays up for the home Camera tile warm preview.
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
        layoutCutawayCover()
        previewView.syncDisplayModeOrientation()
    }

    /// Largest Display Mode panel in the stage, with the shutter strip reserved outside.
    ///
    /// Vertical: preview region above a bottom shutter dock; Landscape: preview left of
    /// a trailing dock (physical bottom when the phone is held sideways). Aspect stays
    /// 16:9 / 9:16 — the panel touches the stage edges where that ratio allows.
    private func phoneCameraPanelRect(in bounds: CGRect) -> CGRect {
        let isVertical = ExternalOutputSettings.isVerticalMode
        let aspect = ExternalOutputSettings.orientation.aspectRatio
        let dock = Self.captureDockSpan(safeTrailing: isVertical
            ? view.safeAreaInsets.bottom
            : view.safeAreaInsets.right)
        let available: CGRect
        if isVertical {
            available = CGRect(
                x: 0,
                y: 0,
                width: bounds.width,
                height: max(0, bounds.height - dock)
            )
        } else {
            available = CGRect(
                x: 0,
                y: 0,
                width: max(0, bounds.width - dock),
                height: bounds.height
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
        let y = available.midY - height / 2
        return CGRect(x: x, y: y, width: width, height: height)
    }

    /// Outside-panel strip for Frame · shutter · Flip (gap + button + safe-area pad).
    static func captureDockSpan(safeTrailing: CGFloat) -> CGFloat {
        chromeGap + shutterSize + max(8, safeTrailing)
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
    /// a recording. AirPlay stays live when already live — only tapping the stage
    /// off live stops that; the home tile keeps the warm session.
    @objc func closeTapped() {
        shutterHoldTimer?.invalidate()
        shutterHoldTimer = nil
        shutterDidLongPress = false
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
        startAlwaysLiveRecordingIfNeeded()
        updateShutterAccessibilityHint()
    }

    @objc private func externalDisplayChanged() {
        // AirPlay / HDMI drop clears overlay live — reclaim the hardware preview layer.
        updateLivePreviewSource(force: true)
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
