//
//  CameraOperatorMode.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import Combine
import EclipsePhoneCameraClient
import EclipsePhoneCameraProtocol
import UIKit

// MARK: - CameraOperatorMode

/// Camera Mode: this phone runs the camera for Eclipse on a Mac.
///
/// A volunteer opens Camera Mode from Home (or by scanning the Mac's Phone
/// Camera QR code). It is the regular full-screen Camera, with Show navigation
/// hidden, sending its picture (frame and parked stills included) to the Mac.
/// The mode survives relaunch: the app reopens into it and reconnects with the
/// last scanned link while that Mac session is still running.
///
/// Thread safety: main actor only. Frames reach the Mac through
/// `MacProgramCompositor` on the camera's frame queue.
@MainActor
final class CameraOperatorMode {

    // MARK: - Types

    /// Mac link state shown in the Camera Mode status pill.
    enum MacStatus: Equatable {
        case notConnected
        case connecting
        case live
        case reconnecting
        case failed(String)
    }

    // MARK: - Properties

    static let shared = CameraOperatorMode()

    /// Posted on main when `isActive` or `macStatus` changes.
    static let didChangeNotification = Notification.Name("CameraOperatorMode.didChange")

    /// True while Camera Mode should keep the screen awake.
    static var keepsScreenAwake: Bool { shared.isActive }

    /// Whether Camera Mode is on (persisted so a relaunch reopens it).
    private(set) var isActive: Bool {
        get { UserDefaults.standard.bool(forKey: Self.activeKey) }
        set { UserDefaults.standard.set(newValue, forKey: Self.activeKey) }
    }

    /// Current Mac link state.
    private(set) var macStatus: MacStatus = .notConnected {
        didSet {
            guard oldValue != macStatus else { return }
            NotificationCenter.default.post(name: Self.didChangeNotification, object: self)
        }
    }

    private static let activeKey = "EclipseTV.cameraMode.active"
    private static let linkKey = "cameraMode.macLink"
    private static let retryDelay: UInt64 = 4_000_000_000
    private static let notLocalMessage = "That code isn't for a Mac on this Wi-Fi network. Scan the QR code on the Mac."

    private let feed = PhoneCameraFrameFeed()
    private lazy var session = PhoneCameraSessionController(frameFeed: feed)
    private var phaseSubscription: AnyCancellable?
    private var programObservers: [NSObjectProtocol] = []
    private var retryTask: Task<Void, Never>?

    // MARK: - Initialization

    private init() {}

    // MARK: - Public Interface

    /// Turns Camera Mode on: screen stays awake and the Mac link starts.
    /// - Parameter link: A freshly scanned QR link, or nil to reuse the saved one.
    func activate(link: String? = nil) {
        isActive = true
        UIApplication.shared.isIdleTimerDisabled = true
        MacProgramCompositor.shared.start(feed: feed)
        observeSessionIfNeeded()
        observeProgramIfNeeded()
        refreshProgram()
        NotificationCenter.default.post(name: Self.didChangeNotification, object: self)
        if let link {
            connect(link: link)
        } else if case .notConnected = macStatus, let saved = KeychainStore.string(forKey: Self.linkKey) {
            connect(link: saved)
        }
    }

    /// Turns Camera Mode off and leaves the Mac.
    func deactivate() {
        isActive = false
        retryTask?.cancel()
        retryTask = nil
        session.disconnect()
        MacProgramCompositor.shared.stop()
        UIApplication.shared.isIdleTimerDisabled = false
        macStatus = .notConnected
        NotificationCenter.default.post(name: Self.didChangeNotification, object: self)
    }

    /// Connects to the Mac using a scanned Phone Camera QR link.
    /// - Parameter link: `eclipse://phone-camera?...` payload from the Mac.
    func connect(link: String) {
        retryTask?.cancel()
        retryTask = nil
        guard CameraModeLinkPolicy.isAllowed(link) else {
            macStatus = .failed(Self.notLocalMessage)
            return
        }
        KeychainStore.set(link, forKey: Self.linkKey)
        macStatus = .connecting
        session.connect(scannedURL: link)
    }

    /// Rebuilds what the Mac shows from the camera's frame / still state.
    func refreshProgram() {
        let display = ExternalDisplayManager.shared
        var still: CIImage?
        if display.isCameraParkedOnStill {
            still = Self.parkedStillImage(display).flatMap(Self.ciImage)
        }
        let overlay = CameraFrameStore.shared.selectedImage.flatMap(Self.ciImage)
        let quality = PhoneCameraStreamQuality.load()
        let isVertical = ExternalOutputSettings.isVerticalMode
        let size = isVertical
            ? CGSize(width: CGFloat(quality.height), height: CGFloat(quality.width))
            : CGSize(width: CGFloat(quality.width), height: CGFloat(quality.height))
        MacProgramCompositor.shared.update(.init(overlay: overlay, still: still, outputSize: size))
    }

    // MARK: - Private Helpers

    private func observeSessionIfNeeded() {
        guard phaseSubscription == nil else { return }
        phaseSubscription = session.$phase
            .receive(on: DispatchQueue.main)
            .sink { [weak self] phase in
                self?.handle(phase)
            }
    }

    private func observeProgramIfNeeded() {
        guard programObservers.isEmpty else { return }
        let names: [Notification.Name] = [
            CameraFrameStore.didChangeNotification,
            CameraAlternateStillStore.didChangeNotification,
            ExternalDisplayManager.didChangeNotification,
            ExternalOutputSettings.didChangeNotification
        ]
        programObservers = names.map { name in
            NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { _ in
                Task { @MainActor in CameraOperatorMode.shared.refreshProgram() }
            }
        }
    }

    /// Maps the shared session's phase to the pill and retries dropped links.
    private func handle(_ phase: PhoneCameraSessionController.Phase) {
        guard isActive else { return }
        switch phase {
        case .streaming:
            macStatus = .live
        case .connecting, .needsPIN:
            if macStatus != .reconnecting { macStatus = .connecting }
        case .idle:
            break
        case .failed(let message):
            handleFailure(message)
        }
    }

    /// A rejected link means the Mac made a new code; anything else is retried.
    private func handleFailure(_ message: String) {
        if Self.isRejectedLink(message) {
            KeychainStore.removeValue(forKey: Self.linkKey)
            macStatus = .failed("The Mac's code changed. Scan its QR code again.")
            return
        }
        guard let saved = KeychainStore.string(forKey: Self.linkKey) else {
            macStatus = .failed(message)
            return
        }
        macStatus = .reconnecting
        retryTask?.cancel()
        retryTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: Self.retryDelay)
            guard !Task.isCancelled, let self, self.isActive else { return }
            self.session.connect(scannedURL: saved)
        }
    }

    /// True when the Mac refused the saved link (it restarted or made a new code).
    static func isRejectedLink(_ message: String) -> Bool {
        message == PhoneCameraAPIError.badStatus.errorDescription
            || message == PhoneCameraAPIError.missingSessionCookie.errorDescription
    }

    private static func parkedStillImage(_ display: ExternalDisplayManager) -> UIImage? {
        switch display.parkedCameraStill {
        case .background: return LogoStore.shared.image
        case .cutaway(let id): return CameraAlternateStillStore.shared.image(for: id)
        case nil: return nil
        }
    }

    private static func ciImage(_ image: UIImage) -> CIImage? {
        if let cg = image.cgImage {
            return CIImage(cgImage: cg).oriented(CGImagePropertyOrientation(image.imageOrientation))
        }
        return image.ciImage
    }
}

// MARK: - CGImagePropertyOrientation

private extension CGImagePropertyOrientation {
    /// Maps UIKit's image orientation to Core Image's.
    init(_ orientation: UIImage.Orientation) {
        switch orientation {
        case .down: self = .down
        case .left: self = .left
        case .right: self = .right
        case .upMirrored: self = .upMirrored
        case .downMirrored: self = .downMirrored
        case .leftMirrored: self = .leftMirrored
        case .rightMirrored: self = .rightMirrored
        default: self = .up
        }
    }
}
