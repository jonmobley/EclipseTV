//
//  ExternalDisplayManager.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

// ExternalDisplayManager.swift
import UIKit
import os.log

/// Detects an external display (an AirPlay-mirrored Apple TV appears to iOS as a second
/// `UIScreen`) and hosts a `PresentationViewController` on it. When the app places a
/// window on the external screen, iOS shows that content instead of plain mirroring,
/// so the phone keeps its normal UI while the TV shows the selected item fullscreen.
///
/// No companion app, entitlement, or Apple TV-side change is required.
final class ExternalDisplayManager {

    /// Overlay content that takes priority over the library live item.
    enum OverlaySource: Equatable {
        case camera
        case web(URL)
    }

    /// Shared instance; started once from the scene delegate.
    static let shared = ExternalDisplayManager()

    /// Posted when an external display connects or disconnects so UI (e.g. the header)
    /// can reflect that presentation is active.
    static let didChangeNotification = Notification.Name("ExternalDisplayManager.didChange")

    /// Posted when camera presentation ends because another source was presented or
    /// the display was cleared (so the phone camera UI can dismiss).
    static let cameraDidEndNotification = Notification.Name("ExternalDisplayManager.cameraDidEnd")

    /// Posted when web presentation ends so the phone remote can dismiss.
    static let webDidEndNotification = Notification.Name("ExternalDisplayManager.webDidEnd")

    /// Whether an external display is currently connected.
    private(set) var isConnected = false

    /// Active overlay (camera or web), if any.
    private(set) var overlaySource: OverlaySource?

    /// Whether the live camera is the active presentation source (AirPlay path).
    var isCameraLive: Bool {
        if case .camera = overlaySource { return true }
        return false
    }

    /// Whether a web page is the active presentation source (AirPlay path).
    var isWebLive: Bool {
        if case .web = overlaySource { return true }
        return false
    }

    /// Whether any overlay (camera or web) is currently live.
    var isOverlayLive: Bool { overlaySource != nil }

    /// Supplies the source to show when a screen connects with nothing presented yet
    /// (e.g. an item is already live when the user starts mirroring). Set by the grid.
    var currentSourceProvider: (() -> PresentationSource?)?

    private var window: UIWindow?
    private var presentationVC: PresentationViewController?
    private var lastSource: PresentationSource?
    private let logger = Logger(subsystem: "com.eclipseapp.ios", category: "ExternalDisplay")

    private init() {}

    // MARK: - Lifecycle

    // NOTE: This uses the pre-iOS-16 `UIScreen` connect/disconnect notifications, which are
    // deprecated (but still functional). The modern path is a `UISceneSession` with the
    // `.windowExternalDisplayNonInteractive` role, which requires enabling
    // `UIApplicationSupportsMultipleScenes` and an external-display scene config in
    // Info.plist plus scene-lifecycle handling. That migration is app-wide and needs
    // testing on real AirPlay/external-display hardware, so it's intentionally deferred.

    /// Begins observing screen connect/disconnect and adopts any already-connected screen.
    func start() {
        NotificationCenter.default.addObserver(
            self, selector: #selector(screenDidConnect(_:)),
            name: UIScreen.didConnectNotification, object: nil)
        NotificationCenter.default.addObserver(
            self, selector: #selector(screenDidDisconnect(_:)),
            name: UIScreen.didDisconnectNotification, object: nil)

        // A display may already be attached when the app launches.
        if let external = UIScreen.screens.first(where: { $0 != UIScreen.main }) {
            attach(to: external)
        }
    }

    // MARK: - Presentation

    /// Updates the external display with `source`. A no-op visually when no display is
    /// connected, but the source is remembered and applied as soon as one connects.
    /// Non-overlay sources tear down any active camera/web overlay.
    func present(_ source: PresentationSource) {
        switch source.content {
        case .camera:
            beginOverlay(.camera, endingOther: true)
        case .web(let url):
            beginOverlay(.web(url), endingOther: true)
        default:
            if overlaySource != nil {
                endOverlay(notify: true)
            }
        }
        lastSource = source
        presentationVC?.show(source)
        updateIdleTimer()
    }

    /// Starts presenting the live camera on the external display (and remembers it).
    func presentCamera() {
        present(.camera)
    }

    /// Starts presenting a web page on the external display.
    func presentWeb(_ url: URL) {
        present(.web(url))
    }

    /// Stops the camera session and restores the library live item when available.
    func stopCameraAndRestoreLibrary() {
        endOverlay(notify: false)
        restoreLibraryOrIdle()
    }

    /// Stops web presentation and restores the library live item when available.
    func stopWebAndRestoreLibrary() {
        endOverlay(notify: false)
        restoreLibraryOrIdle()
    }

    /// Clears the external display back to a neutral screen.
    func clear() {
        if overlaySource != nil {
            endOverlay(notify: true)
        }
        lastSource = nil
        presentationVC?.showIdle()
        updateIdleTimer()
    }

    /// Re-presents the live item from `currentSourceProvider` (e.g. after closing a
    /// temporary album preview), or clears the display when nothing is live.
    func restoreCurrentSource() {
        switch overlaySource {
        case .camera:
            present(.camera)
        case .web(let url):
            present(.web(url))
        case .none:
            if let source = currentSourceProvider?() {
                present(source)
            } else {
                clear()
            }
        }
    }

    // MARK: - Web Remote Forwarders

    /// Forwards a scroll delta to the external web view.
    func scrollWeb(by delta: CGPoint) {
        presentationVC?.scrollWeb(by: delta)
    }

    /// Reloads the external web page.
    func reloadWeb() {
        presentationVC?.reloadWeb()
    }

    /// Scrolls the external web page to the top.
    func scrollWebToTop() {
        presentationVC?.scrollWebToTop()
    }

    // MARK: - Overlay Helpers

    private func beginOverlay(_ next: OverlaySource, endingOther: Bool) {
        if endingOther, let current = overlaySource, current != next {
            tearDown(current)
            notifyOverlayEnd(current)
        }
        overlaySource = next
    }

    private func endOverlay(notify: Bool) {
        guard let current = overlaySource else { return }
        tearDown(current)
        overlaySource = nil
        if notify {
            notifyOverlayEnd(current)
        }
        updateIdleTimer()
    }

    private func tearDown(_ source: OverlaySource) {
        switch source {
        case .camera:
            CameraManager.shared.stopSession()
        case .web:
            presentationVC?.teardownWeb()
        }
    }

    private func notifyOverlayEnd(_ source: OverlaySource) {
        switch source {
        case .camera:
            NotificationCenter.default.post(name: Self.cameraDidEndNotification, object: self)
        case .web:
            NotificationCenter.default.post(name: Self.webDidEndNotification, object: self)
        }
    }

    private func restoreLibraryOrIdle() {
        lastSource = nil
        if let source = currentSourceProvider?() {
            present(source)
        } else {
            presentationVC?.showIdle()
            updateIdleTimer()
        }
    }

    private func updateIdleTimer() {
        UIApplication.shared.isIdleTimerDisabled = overlaySource != nil
    }

    // MARK: - Screen Handling

    @objc private func screenDidConnect(_ notification: Notification) {
        guard let screen = notification.object as? UIScreen else { return }
        attach(to: screen)
    }

    @objc private func screenDidDisconnect(_ notification: Notification) {
        guard (notification.object as? UIScreen) != nil else { return }
        detach()
    }

    private func attach(to screen: UIScreen) {
        guard window == nil else { return }
        logger.info("External display connected")

        let presentationVC = PresentationViewController()

        let window = UIWindow(frame: screen.bounds)
        window.screen = screen
        window.rootViewController = presentationVC
        window.overrideUserInterfaceStyle = .dark
        // Show without becoming key so the phone's main window stays interactive.
        window.isHidden = false

        self.window = window
        self.presentationVC = presentationVC
        isConnected = true

        // Force the view to load before pushing content.
        presentationVC.loadViewIfNeeded()
        if let source = lastSource ?? currentSourceProvider?() {
            present(source)
        } else {
            presentationVC.showIdle()
        }

        NotificationCenter.default.post(name: Self.didChangeNotification, object: self)
    }

    private func detach() {
        guard window != nil else { return }
        logger.info("External display disconnected")
        window?.isHidden = true
        window = nil
        presentationVC = nil
        isConnected = false
        NotificationCenter.default.post(name: Self.didChangeNotification, object: self)
    }
}
