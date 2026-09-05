//
//  DisplayModeOrientation.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import UIKit

// MARK: - Display Mode Interface Orientation

extension ExternalOutputSettings {

    /// Interface orientations that match the active Display Mode.
    ///
    /// The in-app web browser pins itself to this so a 16:9 container is shown on a
    /// turned phone rather than as a letterbox strip across a portrait screen.
    /// Camera follows the phone instead: a Landscape Show in portrait is a 16:9 crop.
    static var phoneOrientationMask: UIInterfaceOrientationMask {
        isVerticalMode ? .portrait : .landscape
    }

    /// Orientation a Display Mode screen should open in.
    static var preferredPhoneOrientation: UIInterfaceOrientation {
        isVerticalMode ? .portrait : .landscapeRight
    }
}

extension UIInterfaceOrientation {

    /// `AVCaptureVideoPreviewLayer` angle that stands subjects upright for this
    /// interface orientation (sensor buffers are landscape-native).
    ///
    /// Landscape Left and Right are not the same angle — treating both as `0`
    /// leaves one side upside-down on AirPlay when the phone scene settles there.
    var cameraPreviewRotationAngle: CGFloat {
        switch self {
        case .portrait: return 90
        case .portraitUpsideDown: return 270
        case .landscapeRight: return 0
        case .landscapeLeft: return 180
        default: return 90
        }
    }

    /// True for portrait and portrait upside-down.
    var isPortrait: Bool {
        self == .portrait || self == .portraitUpsideDown
    }

    /// True for landscape left and landscape right.
    var isLandscape: Bool {
        self == .landscapeLeft || self == .landscapeRight
    }
}

extension UIView {

    /// Interface orientation for this view's window scene.
    ///
    /// Defaults to portrait when the scene is unknown (app's upright default).
    var phoneInterfaceOrientation: UIInterfaceOrientation {
        let orientation = window?.windowScene?.interfaceOrientation
            ?? UIApplication.shared.connectedScenes
                .compactMap { $0 as? UIWindowScene }
                .first { $0.session.role == .windowApplication }?
                .interfaceOrientation
        guard let orientation, orientation != .unknown else { return .portrait }
        return orientation
    }
}

extension UIViewController {

    /// Asks the phone's window scene to rotate to the Display Mode orientation.
    ///
    /// Needed on top of `supportedInterfaceOrientations`: these screens open from a
    /// portrait grid, and without a geometry request iOS leaves the scene as-is until
    /// the user happens to turn the device.
    func requestDisplayModeSceneGeometry() {
        requestSceneOrientations(ExternalOutputSettings.phoneOrientationMask)
        setNeedsUpdateOfSupportedInterfaceOrientations()
    }

    /// Returns the window scene to the app's upright default.
    ///
    /// Counterpart to `requestDisplayModeSceneGeometry()`. The scene preference outlives
    /// the screen that set it, so a Landscape Display Mode stage would otherwise leave
    /// everything behind it turned once the user closes it.
    ///
    /// Call this after the screen is off-screen: while it is still the topmost controller
    /// its own landscape mask leaves the request nothing to resolve to. iPad has no
    /// upright default worth forcing, so it is left alone.
    func restoreUprightSceneGeometry() {
        guard traitCollection.userInterfaceIdiom == .phone else { return }
        requestSceneOrientations(.portrait)
    }

    private func requestSceneOrientations(_ mask: UIInterfaceOrientationMask) {
        // Falls back to scanning scenes because the window is already gone on the way out.
        let scene = view.window?.windowScene ?? UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first { $0.session.role == .windowApplication }
        guard let scene else { return }
        scene.requestGeometryUpdate(.iOS(interfaceOrientations: mask)) { _ in }
    }
}

// MARK: - Orientation-Forwarding Navigation

/// Navigation controller that lets its top screen pick the interface orientation.
///
/// `UINavigationController` answers the orientation callbacks itself and does not
/// consult its children, so a Display Mode screen pushed or rooted inside a plain
/// navigation controller never rotates.
final class DisplayModeNavigationController: UINavigationController {

    override var supportedInterfaceOrientations: UIInterfaceOrientationMask {
        topViewController?.supportedInterfaceOrientations
            ?? super.supportedInterfaceOrientations
    }

    override var preferredInterfaceOrientationForPresentation: UIInterfaceOrientation {
        topViewController?.preferredInterfaceOrientationForPresentation
            ?? super.preferredInterfaceOrientationForPresentation
    }
}
