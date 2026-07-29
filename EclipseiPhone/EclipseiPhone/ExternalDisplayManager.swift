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
/// keeps its normal UI; the TV shows the selected item / camera / web / PDF.
///
/// No companion app, entitlement, or Apple TV-side change is required.
@MainActor
final class ExternalDisplayManager {

    /// Overlay content that takes priority over the library live item.
    enum OverlaySource: Equatable {
        case camera
        case web(URL)
        case pdf(URL)
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

    /// Posted when PDF presentation ends so the phone reader can dismiss.
    static let pdfDidEndNotification = Notification.Name("ExternalDisplayManager.pdfDidEnd")

    /// Whether an external display scene is attached and showing app content.
    private(set) var isConnected = false

    /// Active overlay (camera, web, or PDF), if any.
    private(set) var overlaySource: OverlaySource?

    /// Camera overlay is active, but AirPlay is temporarily showing Logo.
    /// Phone camera UI stays open; session keeps running.
    private(set) var isCameraParkedOnLogo = false

    /// Whether camera mode owns the overlay (session may still be running).
    var isCameraModeActive: Bool {
        if case .camera = overlaySource { return true }
        return false
    }

    /// Whether the live camera is the active AirPlay presentation source.
    var isCameraLive: Bool {
        isCameraModeActive && !isCameraParkedOnLogo
    }

    /// Whether a web page is the active presentation source (AirPlay path).
    var isWebLive: Bool {
        if case .web = overlaySource { return true }
        return false
    }

    /// Whether a PDF is the active presentation source (AirPlay path).
    var isPDFLive: Bool {
        if case .pdf = overlaySource { return true }
        return false
    }

    /// Bookmark that owns the live web overlay (survives closing the phone browser).
    private(set) var liveWebPageId: UUID?

    /// Bookmark that owns the live PDF overlay (survives closing the phone reader).
    private(set) var livePDFDocumentId: UUID?

    /// Whether a joined (cloud) album item is sticky-live on the external display.
    /// Survives closing the Join browser; cleared when home-grid content takes over.
    private(set) var isJoinedLive = false

    /// Whether any overlay (camera, web, or PDF) is currently live.
    var isOverlayLive: Bool { overlaySource != nil }

    /// Supplies the source to show when a screen connects with nothing presented yet
    /// (e.g. an item is already live when the user starts mirroring). Set by the grid.
    var currentSourceProvider: (() -> PresentationSource?)?

    /// Retained so the external window isn't deallocated (which falls back to mirroring).
    private var externalWindow: UIWindow?
    private var presentationVC: PresentationViewController?
    private var lastSource: PresentationSource?
    /// AirPlay source captured just before camera went live (for Previous restore).
    private var preCameraSource: PresentationSource?
    /// Whether `preCameraSource` was a joined sticky live item.
    private var preCameraWasJoined = false
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
                Task { @MainActor in
                    self?.disconnectWorkItem?.cancel()
                    self?.refreshConnection()
                    self?.keepPresentationAlive()
                }
            },
            center.addObserver(
                forName: UIApplication.willResignActiveNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                // App switcher / Control Center: keep the TV window unhidden so iOS
                // doesn't fall back to phone mirroring.
                Task { @MainActor in
                    self?.keepPresentationAlive()
                }
            },
            center.addObserver(
                forName: UIApplication.didEnterBackgroundNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor in
                    self?.beginBackgroundPresentationTask()
                    self?.keepPresentationAlive()
                }
            },
            center.addObserver(
                forName: UIScene.didActivateNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor in
                    self?.disconnectWorkItem?.cancel()
                    self?.refreshConnection()
                    self?.keepPresentationAlive()
                }
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
        // Release the presented content before dropping our references. Otherwise the web
        // view, `AVPlayer`, and attached camera preview stayed alive behind a window nobody
        // can see, and the app still reported an overlay as live — camera session running,
        // home tiles showing LIVE, phone browser refusing to let go of the page.
        presentationVC?.showIdle()
        endOverlay(notify: true)
        isJoinedLive = false

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
    /// Clears joined sticky state unless `asJoined` is true.
    func present(_ source: PresentationSource, asJoined: Bool = false) {
        refreshConnection()
        isJoinedLive = asJoined
        AudioAmbientPolicy.applyYieldIfNeeded(for: source)
        switch source.content {
        case .camera:
            beginOverlay(.camera, endingOther: true)
            isCameraParkedOnLogo = false
        case .web(let url):
            beginOverlay(.web(url), endingOther: true)
        case .pdf(let url):
            beginOverlay(.pdf(url), endingOther: true)
        default:
            if overlaySource != nil {
                endOverlay(notify: true)
            }
        }
        lastSource = source
        presentationVC?.show(source)
        updateIdleTimer()
    }

    /// Presents a joined-album item and keeps it sticky after the Join browser closes.
    func presentJoined(_ source: PresentationSource) {
        present(source, asJoined: true)
    }

    /// Drops joined sticky state without changing what's on screen.
    func clearJoinedLive() {
        isJoinedLive = false
    }

    /// Starts presenting the live camera on the external display (and remembers it).
    ///
    /// If AirPlay was Logo-parked, resumes the live feed — callers that want the
    /// camera (phone UI open / re-open) should never leave the TV stuck on Logo.
    /// Snapshots the prior non-camera source the first time camera goes live.
    func presentCamera() {
        if isCameraParkedOnLogo {
            resumeCameraFromLogoPark()
            return
        }
        if !isCameraModeActive {
            snapshotPreCameraSource()
        }
        present(.camera)
    }

    /// Remembers what AirPlay showed before camera took over.
    private func snapshotPreCameraSource() {
        if let last = lastSource, last.content != .camera {
            preCameraSource = last
            preCameraWasJoined = isJoinedLive
            return
        }
        preCameraSource = currentSourceProvider?()
        preCameraWasJoined = false
    }

    /// Parks AirPlay on Logo without ending camera mode or stopping the session.
    func parkCameraOnLogo() {
        guard isCameraModeActive, !isCameraParkedOnLogo else { return }
        guard let url = LogoStore.shared.fileURL else { return }
        refreshConnection()
        isCameraParkedOnLogo = true
        let source = PresentationSource.image(url)
        AudioAmbientPolicy.applyYieldIfNeeded(for: source)
        lastSource = source
        presentationVC?.show(source)
        updateIdleTimer()
    }

    /// Restores live camera on AirPlay after `parkCameraOnLogo()`.
    func resumeCameraFromLogoPark() {
        guard isCameraParkedOnLogo, isCameraModeActive else {
            isCameraParkedOnLogo = false
            return
        }
        isCameraParkedOnLogo = false
        refreshConnection()
        let source = PresentationSource.camera
        AudioAmbientPolicy.applyYieldIfNeeded(for: source)
        lastSource = source
        presentationVC?.show(source)
        updateIdleTimer()
    }

    /// Starts presenting a web page on the external display.
    /// - Parameter pageId: Saved bookmark id so the home tile stays live after the
    ///   phone browser is closed (and after in-page navigation changes the URL).
    func presentWeb(_ url: URL, pageId: UUID? = nil) {
        if let pageId {
            liveWebPageId = pageId
        }
        present(.web(url))
    }

    /// Starts presenting a PDF on the external display.
    /// - Parameter documentId: Saved id so the home tile stays live after the
    ///   phone reader is closed.
    func presentPDF(_ url: URL, documentId: UUID? = nil) {
        if let documentId {
            livePDFDocumentId = documentId
        }
        present(.pdf(url))
    }

    /// Presents a solid black screen on the external display.
    func presentBlack() {
        present(.black)
    }

    /// Stops the camera session and restores the library live item when available.
    func stopCameraAndRestoreLibrary() {
        endOverlay(notify: false)
        restoreLibraryOrIdle()
    }

    /// Posted after stop-live applies a close destination so the home grid can
    /// update Black / Logo selection. `userInfo["destination"]` is the raw value.
    static let didApplyCameraCloseDestinationNotification =
        Notification.Name("ExternalDisplayManager.didApplyCameraCloseDestination")

    /// Stops camera live and presents Previous / Logo / Black per settings.
    ///
    /// Keeps the capture session running and does not dismiss the phone camera UI
    /// (`cameraDidEnd` is not posted).
    func stopCameraAndApplyCloseDestination() {
        guard isCameraModeActive else { return }

        // Drop overlay without tearDown — preview/session stay warm on the phone.
        overlaySource = nil
        isCameraParkedOnLogo = false

        let destination = ExternalOutputSettings.cameraCloseDestination
        let applied: CameraCloseDestination
        switch destination {
        case .previous:
            restorePreCameraSource()
            applied = .previous
        case .logo:
            if let url = LogoStore.shared.fileURL {
                present(.image(url))
                applied = .logo
            } else {
                present(.black)
                applied = .black
            }
        case .black:
            present(.black)
            applied = .black
        }

        NotificationCenter.default.post(
            name: Self.didApplyCameraCloseDestinationNotification,
            object: self,
            userInfo: ["destination": applied.rawValue]
        )
        updateIdleTimer()
    }

    /// Restores `preCameraSource`, else the library live item, else Black.
    private func restorePreCameraSource() {
        if let prior = preCameraSource, prior.content != .camera {
            let joined = preCameraWasJoined
            preCameraSource = nil
            preCameraWasJoined = false
            present(prior, asJoined: joined)
            return
        }
        preCameraSource = nil
        preCameraWasJoined = false
        if let source = currentSourceProvider?() {
            present(source)
        } else {
            present(.black)
        }
    }

    /// Stops web presentation and restores the library live item when available.
    func stopWebAndRestoreLibrary() {
        endOverlay(notify: true)
        restoreLibraryOrIdle()
    }

    /// Stops PDF presentation and restores the library live item when available.
    func stopPDFAndRestoreLibrary() {
        endOverlay(notify: true)
        restoreLibraryOrIdle()
    }

    /// Clears the external display back to a neutral screen.
    func clear() {
        if overlaySource != nil {
            endOverlay(notify: true)
        }
        isJoinedLive = false
        lastSource = nil
        presentationVC?.showIdle()
        updateIdleTimer()
    }

    /// Re-presents the live item from `currentSourceProvider`, or clears the display
    /// when nothing is live. No-op while a joined album item is sticky-live.
    func restoreCurrentSource() {
        if isJoinedLive, let lastSource {
            present(lastSource, asJoined: true)
            return
        }
        switch overlaySource {
        case .camera:
            present(.camera)
        case .web(let url):
            present(.web(url))
        case .pdf(let url):
            present(.pdf(url))
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

    /// Mirrors an HTML5 media play/pause/seek event onto the AirPlay WebView.
    func syncWebMedia(_ event: EclipseWebMediaSync.Event) {
        presentationVC?.applyWebMediaSync(event)
    }

    // MARK: - PDF Preview Forwarders

    /// Jumps the external PDF to a page index (used with scroll progress).
    func setPDFPageIndex(_ index: Int) {
        presentationVC?.setPDFPageIndex(index)
    }

    /// Mirrors normalized vertical scroll progress (0...1) onto the external PDF view.
    func setPDFScrollProgress(_ progress: CGFloat) {
        presentationVC?.setPDFScrollProgress(progress)
    }

    /// Mirrors zoom relative to fit-scale onto the external PDF view.
    func setPDFRelativeScale(_ relative: CGFloat) {
        presentationVC?.setPDFRelativeScale(relative)
    }

    /// Relayouts the external PDF view after Display Mode changes.
    func reloadPDFLayout() {
        presentationVC?.applyPDFLayout()
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
            clearLiveOverlayId(for: current)
            notifyOverlayEnd(current)
        }
        if case .camera = next {} else {
            isCameraParkedOnLogo = false
        }
        overlaySource = next
    }

    private func endOverlay(notify: Bool) {
        guard let current = overlaySource else { return }
        tearDown(current)
        overlaySource = nil
        isCameraParkedOnLogo = false
        clearLiveOverlayId(for: current)
        if notify {
            notifyOverlayEnd(current)
        }
        updateIdleTimer()
    }

    private func clearLiveOverlayId(for source: OverlaySource) {
        switch source {
        case .web:
            liveWebPageId = nil
        case .pdf:
            livePDFDocumentId = nil
        case .camera:
            break
        }
    }

    private func tearDown(_ source: OverlaySource) {
        switch source {
        case .camera:
            CameraManager.shared.stopSession()
        case .web:
            presentationVC?.teardownWeb()
        case .pdf:
            presentationVC?.teardownPDF()
        }
    }

    private func notifyOverlayEnd(_ source: OverlaySource) {
        switch source {
        case .camera:
            NotificationCenter.default.post(name: Self.cameraDidEndNotification, object: self)
        case .web:
            NotificationCenter.default.post(name: Self.webDidEndNotification, object: self)
        case .pdf:
            NotificationCenter.default.post(name: Self.pdfDidEndNotification, object: self)
        }
    }

    private func restoreLibraryOrIdle() {
        lastSource = nil
        isJoinedLive = false
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
