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
/// where the aspect allows). A Landscape Show on a portrait-held phone keeps
/// that 16:9 crop — same framing as the home Camera tile — instead of rotating
/// the camera UI. Capture controls sit outside the panel, like the system
/// Camera app: a photo shutter beside a record button. Tap record to start/stop
/// video (except Always Record When Live, which owns recording while on-air).
/// Photos work in preview, live, and while a clip is rolling. Tap the stage to
/// go live or stop when AirPlay, EclipseTV, or Practice Mode is on. Otherwise
/// the stage stays a viewfinder.
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

    /// Top-chrome status pill — "LIVE" while the camera feed is on-air.
    /// Hidden in preview and while a cutaway still is on program.
    let goLiveButton = UIButton(type: .system)

    /// Centered preview hint. Shown when the camera is open but not on-air,
    /// and again while a cutaway still is live.
    let tapToGoLiveHintView = UIButton(type: .system)

    /// Dark capsule behind the record timer so elapsed time stays readable.
    let recordingTimerPillView: UIView = {
        let view = UIView()
        view.backgroundColor = UIColor.black.withAlphaComponent(0.55)
        view.clipsToBounds = true
        view.isHidden = true
        view.isUserInteractionEnabled = false
        view.translatesAutoresizingMaskIntoConstraints = true
        return view
    }()

    /// Elapsed record time, centered in the camera preview while recording.
    let recordingTimerLabel: UILabel = {
        let label = UILabel()
        label.font = .monospacedDigitSystemFont(ofSize: 15, weight: .semibold)
        label.textColor = .white
        label.textAlignment = .center
        label.translatesAutoresizingMaskIntoConstraints = true
        return label
    }()

    /// Top-right gear — Recording and Frames.
    let settingsButton = UIButton(type: .system)

    /// Shared diameter for Settings / Flip circular controls.
    static let chromeControlSize: CGFloat = 44
    /// Record button diameter.
    static let shutterSize: CGFloat = 72
    /// Photo shutter diameter (sits beside the larger record control).
    static let photoSize: CGFloat = 52
    /// Space between the photo shutter and the record button.
    static let shutterPairGap: CGFloat = 12
    /// Gap between the Display Mode panel and the outside shutter strip.
    static let chromeGap: CGFloat = 16

    /// Record — tap to start/stop video (preview or live).
    let shutterButton = UIButton(type: .custom)
    /// Photo shutter — tap to take a still, including while recording.
    let photoButton = UIButton(type: .custom)
    /// Switches between the back and front cameras.
    let flipButton = UIButton(type: .system)
    /// Opens the frame library to choose which overlays appear on the ribbon.
    let frameButton = UIButton(type: .system)
    /// Overlay-frame thumbnails beside the stills ribbon. Tap makes a frame live.
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
    /// Background, quick-change stills, and a trailing + that adds another.
    let stillRibbonView: UICollectionView = {
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
    /// Cutaway being replaced by the active Photos picker, or nil when adding.
    var stillPickerReplaceId: UUID?
    /// True while Back is committing a Background park so `cameraDidEnd` won't re-dismiss.
    var isCommittingParkOnClose = false
    /// Posted after Camera dismisses so the Show grid can sync live stroke / tile art.
    static let didDismissNotification =
        Notification.Name("CameraLiveViewController.didDismiss")
    /// Show that receives captures taken here, when the camera was opened from one.
    var captureDestinationShowId: UUID?

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
        setupStillRibbon()
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
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(captureRotationAngleDidChange),
            name: CameraManager.captureRotationAngleDidChangeNotification,
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

    /// Vertical Show stays portrait. Landscape Show follows the phone so a
    /// portrait hold keeps a 16:9 crop instead of rotating the camera UI.
    override var supportedInterfaceOrientations: UIInterfaceOrientationMask {
        ExternalOutputSettings.isVerticalMode ? .portrait : .allButUpsideDown
    }

    override var preferredInterfaceOrientationForPresentation: UIInterfaceOrientation {
        if ExternalOutputSettings.isVerticalMode { return .portrait }
        return view.phoneInterfaceOrientation
    }

    override var shouldAutorotate: Bool { true }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        guard isBeingDismissed || isMovingFromParent else { return }
        if !isCommittingParkOnClose {
            isCommittingParkOnClose = true
            commitParkedStillOnClose()
        }
        // Safety net if dismiss bypassed `closeTapped` (interactive sheet, etc.).
        // Prefer the UI path so last-capture preview is updated when possible.
        if CameraManager.shared.isRecording {
            CameraManager.shared.closeOutRecordingIfNeeded()
        }
        stopRecordingTimer()
        CameraManager.shared.captureLastFrame(from: previewView)
        teardownLivePreviewSource()
        previewView.detach()
        // Leaving the control UI does not stop AirPlay. Program stays until
        // another source is selected. Session stays up for the home Camera tile.
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        guard isBeingDismissed || isMovingFromParent else { return }
        NotificationCenter.default.post(name: Self.didDismissNotification, object: self)
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
        layoutPhoneCameraViewport()
    }

    /// Phone turned while the UI stayed put (Vertical Show pins portrait) — only the
    /// frame-tap mirror needs re-rotating; the hardware layer follows its coordinator.
    @objc private func captureRotationAngleDidChange() {
        layoutMirrorView()
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    // MARK: - Viewport

    func layoutPhoneCameraViewport() {
        let bounds = stageView.bounds
        guard bounds.width > 0, bounds.height > 0 else { return }

        let portrait = isPhoneCameraPortraitLayout
        let dock = Self.captureDockSpan(safeTrailing: portrait
            ? view.safeAreaInsets.bottom
            : view.safeAreaInsets.right)
        let panel = Self.phoneCameraPanelRect(
            in: bounds,
            aspect: ExternalOutputSettings.orientation.aspectRatio,
            dockOnBottom: portrait,
            dockSpan: dock
        )
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
        previewView.syncPhoneViewerOrientation(previewView.phoneInterfaceOrientation)
    }

    /// Bottom shutter dock when the camera UI is taller than it is wide.
    var isPhoneCameraPortraitLayout: Bool {
        stageView.bounds.height >= stageView.bounds.width
    }

    /// Largest Display Mode panel in the stage, with the shutter strip reserved outside.
    ///
    /// Dock follows how the phone is held, not Show format: bottom in portrait,
    /// trailing in landscape. Aspect stays the Show's 16:9 / 9:16 — a Landscape
    /// Show on a portrait phone is a 16:9 crop, matching the home Camera tile.
    static func phoneCameraPanelRect(
        in bounds: CGRect,
        aspect: CGFloat,
        dockOnBottom: Bool,
        dockSpan: CGFloat
    ) -> CGRect {
        let available: CGRect
        if dockOnBottom {
            available = CGRect(
                x: 0,
                y: 0,
                width: bounds.width,
                height: max(0, bounds.height - dockSpan)
            )
        } else {
            available = CGRect(
                x: 0,
                y: 0,
                width: max(0, bounds.width - dockSpan),
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

    /// Outside-panel strip for Frame · photo · record · Flip
    /// (gap + record button + safe-area pad).
    static func captureDockSpan(safeTrailing: CGFloat) -> CGFloat {
        chromeGap + shutterSize + max(8, safeTrailing)
    }

    /// Vertical Show still pins portrait. Landscape Show stays with the phone.
    func requestDisplayModeGeometry() {
        guard ExternalOutputSettings.isVerticalMode else {
            setNeedsUpdateOfSupportedInterfaceOrientations()
            return
        }
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
    /// a recording. AirPlay stays live when already live; pick another source to
    /// leave it. The home tile keeps the warm session.
    @objc func closeTapped() {
        isCommittingParkOnClose = true
        commitParkedStillOnClose()
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
        if isCommittingParkOnClose || isBeingDismissed || isMovingFromParent {
            return
        }
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
