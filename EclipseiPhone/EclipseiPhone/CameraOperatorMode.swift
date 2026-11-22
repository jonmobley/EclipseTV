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
/// Camera QR code). It is the regular full-screen Camera with Show navigation
/// hidden — a clean camera for a TV, and optionally linked to Eclipse on a Mac
/// (Connect to Mac in the camera settings), which then gets the picture with
/// its frame and parked stills. The mode survives relaunch and relinks to the
/// same Mac while that Mac session is still running.
///
/// Thread safety: main actor only. Frames reach the Mac through
/// `MacProgramCompositor` on the camera's frame queue.
@MainActor
final class CameraOperatorMode {

    // MARK: - Types

    /// Mac link state shown in the Camera Mode status pill and settings.
    enum MacStatus: Equatable {
        /// No Mac link (a plain camera, e.g. for a TV).
        case off
        case connecting
        /// The Mac is receiving the picture.
        case linked
        /// The Mac is showing this camera on its Audience Display.
        case live
        case reconnecting
        case failed(String)

        /// True while a Mac link exists or is being made.
        var isLinkedOrTrying: Bool {
            switch self {
            case .connecting, .linked, .live, .reconnecting: return true
            case .off, .failed: return false
            }
        }
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
    private(set) var macStatus: MacStatus = .off {
        didSet {
            guard oldValue != macStatus else { return }
            NotificationCenter.default.post(name: Self.didChangeNotification, object: self)
        }
    }

    private static let activeKey = "EclipseTV.cameraMode.active"
    private static let linkKey = "cameraMode.macLink"
    private static let retryDelay: UInt64 = 4_000_000_000
    private static let idleSettleDelay: UInt64 = 500_000_000
    private static let removedByMacMessage = "The Mac stopped using this camera. Connect again to send it."
    private static let notLocalMessage = "That code isn't for a Mac on this Wi-Fi network. Scan the QR code on the Mac."

    private let feed = PhoneCameraFrameFeed()
    private lazy var session = PhoneCameraSessionController(frameFeed: feed)
    private var phaseSubscription: AnyCancellable?
    private var programObservers: [NSObjectProtocol] = []
    private var retryTask: Task<Void, Never>?

    // MARK: - Initialization

    private init() {}

    // MARK: - Public Interface

    /// Turns Camera Mode on (screen stays awake) and relinks to a Mac if asked.
    /// - Parameter link: A freshly scanned QR link, or nil to reuse the Mac
    ///   this phone was linked to (none: stays a plain camera).
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
        } else if !macStatus.isLinkedOrTrying, let saved = KeychainStore.string(forKey: Self.linkKey) {
            connect(link: saved)
        }
    }

    /// Turns Camera Mode off and leaves (and forgets) the Mac.
    func deactivate() {
        isActive = false
        disconnectMac()
        MacProgramCompositor.shared.stop()
        UIApplication.shared.isIdleTimerDisabled = false
        NotificationCenter.default.post(name: Self.didChangeNotification, object: self)
    }

    /// Unlinks from the Mac and forgets it; the camera keeps running.
    func disconnectMac() {
        retryTask?.cancel()
        retryTask = nil
        KeychainStore.removeValue(forKey: Self.linkKey)
        macStatus = .off
        session.disconnect()
        CameraKitSync.shared.reset()
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
        let overlay = CameraKitStore.shared.activeFrameImage.flatMap(Self.ciImage)
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
        CameraKitSync.shared.clientProvider = { [weak self] in self?.session.apiClient }
        session.onEvent = { [weak self] data in
            CameraKitSync.shared.handleEvent(data, phoneId: self?.session.phoneId)
        }
        phaseSubscription = session.$phase
            .combineLatest(session.$isOnAir)
            .removeDuplicates { $0 == $1 }
            .receive(on: DispatchQueue.main)
            .sink { [weak self] phase, isOnAir in
                self?.handle(phase, isOnAir: isOnAir)
            }
    }

    private func observeProgramIfNeeded() {
        guard programObservers.isEmpty else { return }
        let names: [Notification.Name] = [
            CameraFrameStore.didChangeNotification,
            CameraAlternateStillStore.didChangeNotification,
            CameraKitStore.didChangeNotification,
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
    private func handle(_ phase: PhoneCameraSessionController.Phase, isOnAir: Bool) {
        guard isActive, macStatus != .off else { return }
        switch phase {
        case .streaming:
            let wasLinked = macStatus == .linked || macStatus == .live
            macStatus = isOnAir ? .live : .linked
            if !wasLinked { CameraKitSync.shared.refresh(force: true) }
        case .connecting, .needsPIN:
            if macStatus != .reconnecting { macStatus = .connecting }
        case .idle:
            confirmRemovedByMacIfStillIdle()
        case .failed(let message):
            handleFailure(message)
        }
    }

    /// Idle while linked means the Mac removed this camera — unless it was only
    /// the brief idle a failing session passes through on its way to `.failed`.
    private func confirmRemovedByMacIfStillIdle() {
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: Self.idleSettleDelay)
            guard let self, self.isActive, self.macStatus.isLinkedOrTrying,
                  self.session.phase == .idle else { return }
            KeychainStore.removeValue(forKey: Self.linkKey)
            self.macStatus = .failed(Self.removedByMacMessage)
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
        case .cutaway(let id):
            return CameraAlternateStillStore.shared.image(for: id) ?? CameraKitStore.shared.image(for: id)
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
