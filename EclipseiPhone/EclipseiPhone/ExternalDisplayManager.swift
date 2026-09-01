//
//  ExternalDisplayManager.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import AVFoundation
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
    /// UserInfo key on `didChangeNotification` when an external display truly dropped.
    static let disconnectReasonKey = "disconnected"

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

    /// Camera overlay is active, but output is temporarily showing a still
    /// (Show Background, or a user cutaway). Phone camera UI stays open; session keeps running.
    private(set) var parkedCameraStill: CameraParkedStill?

    /// True while `parkedCameraStill` is set.
    var isCameraParkedOnStill: Bool { parkedCameraStill != nil }

    /// Parked on a quick-change still (not Show Background).
    var isParkedOnQuickChangeStill: Bool {
        if case .cutaway = parkedCameraStill { return true }
        return false
    }

    /// Camera Show tile is live for the feed or a parked quick-change still.
    var isCameraTileLive: Bool {
        CameraStillRibbon.cameraTileIsLive(
            isCameraLive: isCameraLive,
            parked: parkedCameraStill
        )
    }

    /// Quick-change art for the Camera tile while that still is on program.
    var cameraTileParkedStillImage: UIImage? {
        guard case .cutaway(let id) = parkedCameraStill else { return nil }
        return CameraAlternateStillStore.shared.image(for: id)
    }

    /// AirPlay source for the parked still, if any.
    var parkedStillPresentationSource: PresentationSource? {
        switch parkedCameraStill {
        case .background:
            return LogoStore.shared.presentationSource
        case .cutaway(let id):
            return CameraAlternateStillStore.shared.presentationSource(for: id)
        case nil:
            return nil
        }
    }

    /// True when program is the Show Background still.
    var isShowingBackgroundStill: Bool {
        guard case .image(let url, _) = lastSource?.content else { return false }
        return LogoStore.shared.isLogoFileURL(url)
    }

    /// Whether camera mode owns the overlay (session may still be running).
    var isCameraModeActive: Bool {
        if case .camera = overlaySource { return true }
        return false
    }

    /// Whether the live camera is the active AirPlay presentation source.
    var isCameraLive: Bool {
        isCameraModeActive && !isCameraParkedOnStill
    }

    /// Whether a web page is the active presentation source (AirPlay path).
    var isWebLive: Bool {
        if case .web = overlaySource { return true }
        return false
    }

    /// URL of the live web overlay, if any.
    var liveWebURL: URL? {
        guard case .web(let url) = overlaySource else { return nil }
        return url
    }

    /// Whether the QuestPoll projector page is on the external display.
    var isQuestPollLive: Bool {
        guard let liveWebURL else { return false }
        return QuestPollConfig.isPresentURL(liveWebURL)
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

    /// What AirPlay is showing (or would show), including Screensaver fallback.
    /// Nil when no external display is attached.
    var presentedSource: PresentationSource? {
        guard isConnected else { return nil }
        return resolvedPresentationSource()
    }

    /// Supplies the source to show when a screen connects with nothing presented yet
    /// (e.g. an item is already live when the user starts mirroring). Set by the grid.
    var currentSourceProvider: (() -> PresentationSource?)?

    /// Retained so the external window isn't deallocated (which falls back to mirroring).
    private var externalWindow: UIWindow?
    private var presentationVC: PresentationViewController?
    private var lastSource: PresentationSource?
    /// What to put back when blackout is toggled off.
    private var blackoutRestore: BlackoutRestore?
    private var lifecycleObservers: [NSObjectProtocol] = []
    /// Coalesces transient `sceneDidDisconnect` during app-switcher / background.
    private var disconnectWorkItem: DispatchWorkItem?
    private var backgroundTaskID = UIBackgroundTaskIdentifier.invalid
    private let logger = Logger(subsystem: "com.eclipseapp.ios", category: "ExternalDisplay")

    private struct BlackoutRestore {
        let source: PresentationSource
        let joined: Bool
        let webPageId: UUID?
        let pdfDocumentId: UUID?
    }

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
            },
            center.addObserver(
                forName: UIScreen.didConnectNotification,
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
            if let source = resolvedPresentationSource() {
                lastSource = source
                root.showIfNeeded(source)
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

        // Capture resume time while the AirPlay player is still alive.
        parkCurrentVideoForDisconnect()

        // Drop TV-side players / web / camera layer. Do not stop the phone camera
        // session or dismiss phone browser/PDF — those stay useful offline.
        presentationVC?.showIdle()
        if overlaySource == .camera {
            dropCameraOverlayAfterDisconnect()
        } else if overlaySource != nil {
            overlaySource = nil
            parkedCameraStill = nil
            liveWebPageId = nil
            livePDFDocumentId = nil
        }

        isJoinedLive = false
        blackoutRestore = nil
        // Do not set `window.windowScene = nil` — that forces mirroring.
        externalWindow = nil
        presentationVC = nil
        isConnected = false
        endBackgroundPresentationTask()
        updateIdleTimer()
        NotificationCenter.default.post(
            name: Self.didChangeNotification,
            object: self,
            userInfo: [Self.disconnectReasonKey: true]
        )
    }

    /// Parks library-video resume before disconnect tears down the AirPlay player.
    private func parkCurrentVideoForDisconnect() {
        guard let lastSource else { return }
        parkLeavingVideoIfNeeded(replacing: lastSource, with: .black)
    }

    private func hasExternalDisplayScene() -> Bool {
        extraScreenWindowScene() != nil
            || UIApplication.shared.connectedScenes.contains { scene in
                guard let windowScene = scene as? UIWindowScene else { return false }
                return Self.isExternalDisplayRole(windowScene.session.role)
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
                  Self.isExternalDisplayRole(windowScene.session.role) else {
                continue
            }
            attach(to: windowScene)
            return
        }

        if let windowScene = extraScreenWindowScene() {
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

    /// True for AirPlay / HDMI scene roles (interactive and non-interactive).
    nonisolated static func isExternalDisplayRole(_ role: UISceneSession.Role) -> Bool {
        if role == .windowExternalDisplayNonInteractive { return true }
        return role.rawValue.localizedCaseInsensitiveContains("ExternalDisplay")
    }

    /// Scene for a connected screen that isn't the phone (AirPlay / HDMI).
    private func extraScreenWindowScene() -> UIWindowScene? {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first { scene in
                scene.screen !== UIScreen.main
                    && !scene.session.role.rawValue.contains("CarPlay")
            }
    }

    // MARK: - Presentation

    /// Current playback time of the AirPlay library video matching `itemId`, if any.
    func currentVideoPlaybackTime(forItemId itemId: String) -> TimeInterval? {
        guard let lastSource,
              case .video(let url, _, _) = lastSource.content,
              AirPlayVideoTransport.url(
                url,
                matchesItemId: itemId,
                localURL: LocalMediaStore.shared.localURL(forId: itemId)
              ),
              let player = presentationVC?.player
        else { return nil }
        let seconds = CMTimeGetSeconds(player.currentTime())
        guard seconds.isFinite, seconds > 0 else { return nil }
        return seconds
    }

    /// Seek offset of the last presented library video matching `itemId`.
    ///
    /// Available even with no display attached (Practice Mode hero playback).
    func lastPresentedVideoStartAt(forItemId itemId: String) -> TimeInterval {
        guard let lastSource,
              case .video(let url, _, _) = lastSource.content,
              AirPlayVideoTransport.url(
                url,
                matchesItemId: itemId,
                localURL: LocalMediaStore.shared.localURL(forId: itemId)
              )
        else { return 0 }
        return lastSource.videoStartAt
    }

    /// AirPlay library-video player when a video is live on the external display.
    var libraryVideoPlayer: AVPlayer? {
        guard isConnected, case .video = lastSource?.content else { return nil }
        return presentationVC?.player
    }

    /// Presentation host for AirPlay library-video transport. Nil when disconnected.
    var libraryVideoPresentation: PresentationViewController? {
        guard libraryVideoPlayer != nil else { return nil }
        return presentationVC
    }

    /// Parks resume state when AirPlay leaves a library video for different content.
    private func parkLeavingVideoIfNeeded(
        replacing previous: PresentationSource?,
        with next: PresentationSource
    ) {
        guard let previous,
              case .video(let url, _, _) = previous.content
        else { return }
        // Same file again (e.g. mute/loop rebuild) — keep playing, don't park.
        if case .video(let nextURL, _, _) = next.content, nextURL == url { return }
        let itemId = TVLibraryStore.shared.items.first(where: { item in
            guard item.isVideo else { return false }
            if let local = LocalMediaStore.shared.localURL(forId: item.id) {
                return local == url
            }
            return url.lastPathComponent == item.id
        })?.id ?? url.lastPathComponent
        VideoResumeStore.shared.parkLeavingVideoIfNeeded(itemId: itemId)
    }

    /// Updates the external display with `source`. A no-op visually when no display is
    /// connected, but the source is remembered and applied as soon as one connects.
    /// Non-overlay sources tear down any active camera/web overlay.
    /// Clears joined sticky state unless `asJoined` is true.
    func present(_ source: PresentationSource, asJoined: Bool = false) {
        present(source, asJoined: asJoined, preservingCameraOverlay: false)
    }

    /// - Parameter preservingCameraOverlay: Keeps a live camera overlay alive under the
    ///   new source. Only a blackout uses this: it is temporary, and `endBlackout`
    ///   restores camera by re-presenting it, which reaches `beginOverlay` — that restores
    ///   state but cannot restart a stopped capture session, so tearing the camera down
    ///   here brings it back as a dead feed with the phone UI already told camera ended.
    ///   Web and PDF overlays are still torn down, since `endBlackout` rebuilds those and
    ///   a retained `WKWebView` would hold a content process for the whole blackout.
    private func present(
        _ source: PresentationSource,
        asJoined: Bool,
        preservingCameraOverlay: Bool
    ) {
        refreshConnection()
        // Capture mid-play leave before teardown — skip blackout (temporary blank).
        if source.content != .black {
            parkLeavingVideoIfNeeded(replacing: lastSource, with: source)
        }
        isJoinedLive = asJoined
        // Any non-black present supersedes a pending blackout restore.
        if source.content != .black {
            blackoutRestore = nil
        }
        AudioAmbientPolicy.applyYieldIfNeeded(for: source)
        switch source.content {
        case .camera:
            beginOverlay(.camera, endingOther: true)
            parkedCameraStill = nil
        case .web(let url):
            beginOverlay(.web(url), endingOther: true)
        case .pdf(let url):
            beginOverlay(.pdf(url), endingOther: true)
        default:
            if let current = overlaySource,
               !(preservingCameraOverlay && current == .camera) {
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

    /// Starts presenting the live camera (AirPlay when a display is attached).
    ///
    /// If still-parked, resumes the live feed — callers that want the camera
    /// (phone UI open / re-open) should never leave output stuck on a still.
    func presentCamera() {
        if isCameraParkedOnStill {
            resumeCameraFromStillPark()
            return
        }
        present(.camera)
    }

    /// Parks on a still without ending camera mode or stopping the session.
    ///
    /// AirPlay shows the still when a display is attached. The phone camera
    /// viewfinder stays on the live camera either way.
    func parkCameraOnStill(
        _ source: PresentationSource,
        kind: CameraParkedStill
    ) {
        guard isCameraModeActive else { return }
        parkedCameraStill = kind
        AudioAmbientPolicy.applyYieldIfNeeded(for: source)
        lastSource = source
        if isConnected {
            refreshConnection()
            presentationVC?.show(source)
            updateIdleTimer()
        }
    }

    /// Ends camera overlay and leaves Show Background as the live source.
    ///
    /// Used when the user closes Camera while parked on Background so the
    /// Show grid's Background tile takes the red live stroke.
    func commitCameraParkToBackground() {
        guard CameraStillRibbon.shouldCommitToBackground(parked: parkedCameraStill),
              let source = LogoStore.shared.presentationSource
        else { return }
        lastSource = source
        parkedCameraStill = nil
        endOverlay(notify: false)
        AudioAmbientPolicy.applyYieldIfNeeded(for: source)
        if isConnected {
            refreshConnection()
            presentationVC?.show(source)
        }
        updateIdleTimer()
        NotificationCenter.default.post(name: Self.didChangeNotification, object: self)
    }

    /// Restores live camera after `parkCameraOnStill(_:kind:)`.
    func resumeCameraFromStillPark() {
        guard isCameraParkedOnStill else { return }
        parkedCameraStill = nil
        guard isCameraModeActive else { return }
        let source = PresentationSource.camera
        AudioAmbientPolicy.applyYieldIfNeeded(for: source)
        lastSource = source
        if isConnected {
            refreshConnection()
            presentationVC?.show(source)
            updateIdleTimer()
        }
    }

    /// Camera overlay cannot survive a real AirPlay drop (the preview layer is gone).
    ///
    /// Drop `.camera` as the reconnect source so a new display does not attach
    /// camera without overlay state and steal the phone preview layer.
    func dropCameraOverlayAfterDisconnect() {
        guard overlaySource == .camera else { return }
        if lastSource?.content == .camera {
            lastSource = nil
        }
        overlaySource = nil
        parkedCameraStill = nil
    }

    /// Starts presenting a web page on the external display.
    /// - Parameter pageId: Saved bookmark id so the home tile stays live after the
    ///   phone browser is closed (and after in-page navigation changes the URL).
    func presentWeb(_ url: URL, pageId: UUID? = nil) {
        // Set the live id after `present` so a same-kind replace cannot clear it
        // mid-transition via `clearLiveOverlayId`.
        present(.web(url))
        if let pageId {
            liveWebPageId = pageId
        }
    }

    /// Starts presenting a PDF on the external display.
    /// - Parameter documentId: Saved id so the home tile stays live after the
    ///   phone reader is closed.
    func presentPDF(_ url: URL, documentId: UUID? = nil) {
        present(.pdf(url))
        if let documentId {
            livePDFDocumentId = documentId
        }
    }

    /// Presents a solid black screen on the external display.
    func presentBlack() {
        beginBlackout()
    }

    /// Blanks AirPlay, remembering the prior source for `endBlackout()`.
    ///
    /// No-op when already black so a second tap does not rebuild the transition.
    func beginBlackout() {
        if case .black = lastSource?.content { return }
        if blackoutRestore == nil {
            if let last = lastSource, last.content != .black {
                blackoutRestore = BlackoutRestore(
                    source: parkedVideoSource(last),
                    joined: isJoinedLive,
                    webPageId: liveWebPageId,
                    pdfDocumentId: livePDFDocumentId
                )
            } else if let provided = currentSourceProvider?(), provided.content != .black {
                blackoutRestore = BlackoutRestore(
                    source: parkedVideoSource(provided),
                    joined: false,
                    webPageId: liveWebPageId,
                    pdfDocumentId: livePDFDocumentId
                )
            }
        }
        present(.black, asJoined: false, preservingCameraOverlay: true)
    }

    /// Restores the source captured by `beginBlackout()`, or clears to idle.
    func endBlackout() {
        let restore = blackoutRestore
        blackoutRestore = nil
        guard let restore else {
            restoreCurrentSource()
            return
        }
        switch restore.source.content {
        case .web(let url):
            presentWeb(url, pageId: restore.webPageId)
        case .pdf(let url):
            presentPDF(url, documentId: restore.pdfDocumentId)
        case .black:
            clear()
        default:
            present(parkedVideoSource(restore.source), asJoined: restore.joined)
        }
    }

    /// Library video returns paused at the current frame; other sources are unchanged.
    private func parkedVideoSource(_ source: PresentationSource) -> PresentationSource {
        guard case .video = source.content else { return source }
        let startAt = AirPlayVideoTransport.parkedStartTime(
            player: presentationVC?.player,
            fallback: source.videoStartAt
        )
        return source.pausingVideo(at: startAt)
    }

    /// Stops the camera session and restores the library live item when available.
    func stopCameraAndRestoreLibrary() {
        endOverlay(notify: false)
        restoreLibraryOrIdle()
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

    /// Clears overlays and falls back to Screensaver (never a grey idle while connected).
    func clear() {
        if overlaySource != nil {
            endOverlay(notify: true)
        }
        isJoinedLive = false
        lastSource = nil
        if let source = resolvedPresentationSource() {
            present(source)
        } else {
            presentationVC?.showIdle()
            updateIdleTimer()
        }
    }

    /// Re-presents the live item from `currentSourceProvider`, or Screensaver.
    /// No-op while a joined album item is sticky-live.
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
            if let source = resolvedPresentationSource() {
                present(source)
            } else {
                presentationVC?.showIdle()
                updateIdleTimer()
            }
        }
    }

    // MARK: - Web Preview Forwarders

    /// Loads a navigated URL on the external web view without ending the overlay.
    /// - Parameter pageId: Optional bookmark id when the in-browser site identity changes.
    func loadWeb(url: URL, pageId: UUID? = nil) {
        guard case .web = overlaySource else {
            presentWeb(url, pageId: pageId)
            return
        }
        overlaySource = .web(url)
        lastSource = .web(url)
        if let pageId {
            liveWebPageId = pageId
        }
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
        let hostChanged = self.presentationVC !== presentationVC
        self.presentationVC = presentationVC
        isConnected = true

        // Re-attach while already connected is common (`present` → `refreshConnection`).
        // Re-showing + posting every time re-enters the grid observer → `present` again
        // (stack overflow on HDMI/AirPlay connect). Only seed content / notify on edges.
        if !wasConnected || hostChanged {
            presentationVC.loadViewIfNeeded()
            if let source = resolvedPresentationSource() {
                // Avoid re-entering beginOverlay when already presenting this source.
                lastSource = source
                presentationVC.showIfNeeded(source)
            } else {
                presentationVC.showIdle()
            }
            updateIdleTimer()
        }

        guard !wasConnected else { return }
        logger.info("External display connected")
        NotificationCenter.default.post(name: Self.didChangeNotification, object: self)
    }

    /// Remembered source, grid live item, or bundled Screensaver — never nil when the
    /// Screensaver video is in the bundle.
    private func resolvedPresentationSource() -> PresentationSource? {
        if let lastSource { return lastSource }
        if let provided = currentSourceProvider?() { return provided }
        return ScreensaverStore.presentationSource
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
            if Self.isSameOverlayKind(current, next) {
                // web→web / pdf→pdf: swap content in `show` without telling the phone
                // UI the overlay ended (that would dismiss the browser/reader).
            } else {
                tearDown(current)
                clearLiveOverlayId(for: current)
                notifyOverlayEnd(current)
            }
        }
        if case .camera = next {} else {
            parkedCameraStill = nil
        }
        overlaySource = next
    }

    /// Whether both overlays are the same content kind (URL may differ).
    private static func isSameOverlayKind(_ a: OverlaySource, _ b: OverlaySource) -> Bool {
        switch (a, b) {
        case (.web, .web), (.pdf, .pdf), (.camera, .camera):
            return true
        default:
            return false
        }
    }

    private func endOverlay(notify: Bool) {
        guard let current = overlaySource else { return }
        tearDown(current)
        overlaySource = nil
        parkedCameraStill = nil
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
        if let source = resolvedPresentationSource() {
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
