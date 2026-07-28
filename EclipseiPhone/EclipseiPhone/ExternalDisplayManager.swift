//
//  ExternalDisplayManager.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import UIKit
import os.log

/// Coordinates content shown on an AirPlay / wired external display.
///
/// When iOS offers a `.windowExternalDisplayNonInteractive` scene, attaching a
/// window replaces system mirroring with app-owned fullscreen content. The phone
/// keeps its normal UI; the TV shows the selected item / camera / web page.
///
/// No companion app, entitlement, or Apple TV-side change is required.
final class ExternalDisplayManager {

    /// Overlay content that takes priority over the library live item.
    enum OverlaySource: Equatable {
        case camera
        case web(URL)
    }

    /// Shared instance; started once from the main scene delegate.
    static let shared = ExternalDisplayManager()

    /// Posted when an external display connects or disconnects so UI (e.g. the header)
    /// can reflect that presentation is active.
    static let didChangeNotification = Notification.Name("ExternalDisplayManager.didChange")

    /// Posted when camera presentation ends because another source was presented or
    /// the display was cleared (so the phone camera UI can dismiss).
    static let cameraDidEndNotification = Notification.Name("ExternalDisplayManager.cameraDidEnd")

    /// Posted when web presentation ends so the phone preview can dismiss.
    static let webDidEndNotification = Notification.Name("ExternalDisplayManager.webDidEnd")

    /// Whether an external display scene is attached and showing app content.
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

    /// Retained so the external window isn't deallocated (which falls back to mirroring).
    private var externalWindow: UIWindow?
    private var presentationVC: PresentationViewController?
    private var lastSource: PresentationSource?
    private var lifecycleObservers: [NSObjectProtocol] = []
    /// Coalesces transient `sceneDidDisconnect` during app-switcher / background.
    private var disconnectWorkItem: DispatchWorkItem?
    private var backgroundTaskID = UIBackgroundTaskIdentifier.invalid
    private let logger = Logger(subsystem: "com.eclipseapp.ios", category: "ExternalDisplay")

    private init() {}

    // MARK: - Lifecycle

    /// Marks the manager ready and begins watching for external display scenes.
    func start() {
        guard lifecycleObservers.isEmpty else {
            refreshConnection()
            return
        }

        let center = NotificationCenter.default
        lifecycleObservers = [
            center.addObserver(
                forName: UIApplication.didBecomeActiveNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                self?.disconnectWorkItem?.cancel()
                self?.refreshConnection()
                self?.keepPresentationAlive()
            },
            center.addObserver(
                forName: UIApplication.willResignActiveNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                // App switcher / Control Center: keep the TV window unhidden so iOS
                // doesn't fall back to phone mirroring.
                self?.keepPresentationAlive()
            },
            center.addObserver(
                forName: UIApplication.didEnterBackgroundNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                self?.beginBackgroundPresentationTask()
                self?.keepPresentationAlive()
            },
            center.addObserver(
                forName: UIScene.didActivateNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                self?.disconnectWorkItem?.cancel()
                self?.refreshConnection()
                self?.keepPresentationAlive()
            }
        ]
        refreshConnection()
    }

    /// Re-asserts the external window so AirPlay stays on app content (not mirror).
    /// Safe to call from background / resign-active transitions.
    func keepPresentationAlive() {
        guard let window = externalWindow else {
            refreshConnection()
            return
        }
        // Hiding or releasing this window is what returns AirPlay to mirroring.
        if window.isHidden {
            window.isHidden = false
        }
        if let scene = window.windowScene,
           UIApplication.shared.connectedScenes.contains(scene),
           let root = window.rootViewController as? PresentationViewController {
            presentationVC = root
            isConnected = true
            if let source = lastSource ?? currentSourceProvider?() {
                root.show(source)
            }
        } else {
            refreshConnection()
        }
    }

    /// Attaches (or reuses) a presentation window on `windowScene`.
    /// - Returns: The external window, retained by the manager.
    @discardableResult
    func attach(to windowScene: UIWindowScene) -> UIWindow {
        if let existing = externalWindow,
           existing.windowScene === windowScene,
           let root = existing.rootViewController as? PresentationViewController {
            existing.isHidden = false
            markConnected(presentationVC: root)
            return existing
        }

        if let existing = windowScene.windows.first,
           let root = existing.rootViewController as? PresentationViewController {
            existing.isHidden = false
            externalWindow = existing
            markConnected(presentationVC: root)
            return existing
        }

        let presentationVC = PresentationViewController()
        let window = UIWindow(windowScene: windowScene)
        window.rootViewController = presentationVC
        window.overrideUserInterfaceStyle = .dark
        // Unhiding kicks AirPlay out of phone-mirroring into this window's content.
        window.isHidden = false
        externalWindow = window
        markConnected(presentationVC: presentationVC)
        logger.info("Attached presentation window to external display scene")
        return window
    }

    /// Called when an external scene reports disconnect.
    ///
    /// iOS often fires this during app-switcher / background even though AirPlay is
    /// still up. Dropping the window immediately forces phone mirroring — so we keep
    /// the window retained and only tear down if no external scene returns.
    func didDisconnect(from scene: UIScene? = nil) {
        if let scene = scene as? UIWindowScene,
           let externalWindow,
           externalWindow.windowScene !== scene {
            return
        }
        guard isConnected || presentationVC != nil || externalWindow != nil else { return }

        disconnectWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.finalizeDisconnectIfNeeded()
        }
        disconnectWorkItem = work
        // Keep presentation alive across the transition; finalize only if still gone.
        keepPresentationAlive()
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0, execute: work)
    }

    private func finalizeDisconnectIfNeeded() {
        if hasExternalDisplayScene() {
            refreshConnection()
            keepPresentationAlive()
            return
        }
        logger.info("External display disconnected")
        // Do not set `window.windowScene = nil` — that forces mirroring.
        externalWindow = nil
        presentationVC = nil
        isConnected = false
        endBackgroundPresentationTask()
        NotificationCenter.default.post(name: Self.didChangeNotification, object: self)
    }

    private func hasExternalDisplayScene() -> Bool {
        UIApplication.shared.connectedScenes.contains { scene in
            guard let windowScene = scene as? UIWindowScene else { return false }
            return isExternalDisplayRole(windowScene.session.role)
        }
    }

    private func beginBackgroundPresentationTask() {
        guard backgroundTaskID == .invalid else { return }
        backgroundTaskID = UIApplication.shared.beginBackgroundTask(
            withName: "EclipseExternalPresentation"
        ) { [weak self] in
            self?.endBackgroundPresentationTask()
        }
        // End shortly — only needed to ride out the suspend transition.
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) { [weak self] in
            self?.endBackgroundPresentationTask()
        }
    }

    private func endBackgroundPresentationTask() {
        guard backgroundTaskID != .invalid else { return }
        UIApplication.shared.endBackgroundTask(backgroundTaskID)
        backgroundTaskID = .invalid
    }

    /// Scans connected scenes and attaches a TV window when an external role is present.
    /// Safe to call often (app active, presenting camera/web, scene activate).
    ///
    /// Never tears down an existing attachment on a miss — scene activation races used
    /// to call this, clear the window, and leave the UI thinking AirPlay was gone.
    func refreshConnection() {
        logConnectedScenes()

        for scene in UIApplication.shared.connectedScenes {
            guard let windowScene = scene as? UIWindowScene,
                  isExternalDisplayRole(windowScene.session.role) else {
                continue
            }
            attach(to: windowScene)
            return
        }

        // Keep a still-valid attachment if our window's scene is connected.
        if let window = externalWindow,
           let windowScene = window.windowScene,
           UIApplication.shared.connectedScenes.contains(windowScene),
           let root = window.rootViewController as? PresentationViewController {
            window.isHidden = false
            markConnected(presentationVC: root)
        }
    }

    private func isExternalDisplayRole(_ role: UISceneSession.Role) -> Bool {
        if role == .windowExternalDisplayNonInteractive { return true }
        // Older alias still appears on some system paths.
        return role.rawValue.contains("ExternalDisplay")
    }

    // MARK: - Presentation

    /// Updates the external display with `source`. A no-op visually when no display is
    /// connected, but the source is remembered and applied as soon as one connects.
    /// Non-overlay sources tear down any active camera/web overlay.
    func present(_ source: PresentationSource) {
        refreshConnection()
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

    // MARK: - Web Preview Forwarders

    /// Loads a navigated URL on the external web view without ending the overlay.
    func loadWeb(url: URL) {
        guard case .web = overlaySource else {
            presentWeb(url)
            return
        }
        overlaySource = .web(url)
        lastSource = .web(url)
        presentationVC?.loadWeb(url: url)
    }

    /// Mirrors the phone browser's scroll offset onto the external web view.
    func setWebContentOffset(_ offset: CGPoint) {
        presentationVC?.setWebContentOffset(offset)
    }

    /// Mirrors normalized vertical scroll progress (0...1) onto the external web view.
    func setWebScrollProgress(_ progress: CGFloat) {
        presentationVC?.setWebScrollProgress(progress)
    }

    /// Reloads the external web page.
    func reloadWeb() {
        presentationVC?.reloadWeb()
    }

    /// Scrolls the external web page to the top.
    func scrollWebToTop() {
        presentationVC?.scrollWebToTop()
    }

    // MARK: - Connection Helpers

    private func markConnected(presentationVC: PresentationViewController) {
        let wasConnected = isConnected
        self.presentationVC = presentationVC
        isConnected = true

        presentationVC.loadViewIfNeeded()
        if let source = lastSource ?? currentSourceProvider?() {
            // Avoid re-entering beginOverlay when already presenting this source.
            lastSource = source
            presentationVC.show(source)
        } else {
            presentationVC.showIdle()
        }
        updateIdleTimer()

        if !wasConnected {
            logger.info("External display connected")
            NotificationCenter.default.post(name: Self.didChangeNotification, object: self)
        } else {
            NotificationCenter.default.post(name: Self.didChangeNotification, object: self)
        }
    }

    private func logConnectedScenes() {
        let roles = UIApplication.shared.connectedScenes.map { scene -> String in
            guard let windowScene = scene as? UIWindowScene else {
                return String(describing: type(of: scene))
            }
            return windowScene.session.role.rawValue
        }
        logger.debug("Connected scenes: \(roles.joined(separator: ", "), privacy: .public)")
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
        // Keep the device awake while anything is live on the external display.
        UIApplication.shared.isIdleTimerDisabled = isConnected && lastSource != nil
    }
}
