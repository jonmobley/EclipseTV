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

    /// Shared instance; started once from the scene delegate.
    static let shared = ExternalDisplayManager()

    /// Posted when an external display connects or disconnects so UI (e.g. the header)
    /// can reflect that presentation is active.
    static let didChangeNotification = Notification.Name("ExternalDisplayManager.didChange")

    /// Whether an external display is currently connected.
    private(set) var isConnected = false

    /// Supplies the source to show when a screen connects with nothing presented yet
    /// (e.g. an item is already live when the user starts mirroring). Set by the grid.
    var currentSourceProvider: (() -> PresentationSource?)?

    private var window: UIWindow?
    private var presentationVC: PresentationViewController?
    private var lastSource: PresentationSource?
    private let logger = Logger(subsystem: "com.eclipseapp.ios", category: "ExternalDisplay")

    private init() {}

    // MARK: - Lifecycle

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
    func present(_ source: PresentationSource) {
        lastSource = source
        presentationVC?.show(source)
    }

    /// Clears the external display back to a neutral screen.
    func clear() {
        lastSource = nil
        presentationVC?.showIdle()
    }

    /// Re-presents the live item from `currentSourceProvider` (e.g. after closing a
    /// temporary album preview), or clears the display when nothing is live.
    func restoreCurrentSource() {
        if let source = currentSourceProvider?() {
            present(source)
        } else {
            clear()
        }
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
