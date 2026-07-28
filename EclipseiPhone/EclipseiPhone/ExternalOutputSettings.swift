//
//  ExternalOutputSettings.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import UIKit

/// Orientation of AirPlay / external-display output and phone media chrome.
///
/// `.portrait` is shown in the UI as **Vertical** (9:16 experience). The raw value
/// is `"Vertical"`; legacy `"Portrait"` values still decode.
enum ExternalOutputOrientation: String, CaseIterable {
    case landscape = "Landscape"
    case portrait = "Vertical"

    /// Aspect ratio (width / height) for this orientation.
    var aspectRatio: CGFloat {
        self == .landscape ? 16.0 / 9.0 : 9.0 / 16.0
    }

    /// Library / albums grid column count for this mode.
    var gridColumnCount: CGFloat {
        self == .landscape ? 2 : 3
    }

    /// Cell height ÷ width: 16:9 cells in Landscape, 9:16 cells in Vertical.
    var gridCellHeightOverWidth: CGFloat {
        self == .landscape ? 9.0 / 16.0 : 16.0 / 9.0
    }

    /// Wire / storage bucket for this display mode.
    var libraryMode: EclipseShareProtocol.LibraryMode {
        self == .landscape ? .landscape : .vertical
    }

    /// Decodes current and legacy UserDefaults strings.
    static func resolved(fromStored raw: String?) -> ExternalOutputOrientation {
        switch raw {
        case Self.landscape.rawValue: return .landscape
        case Self.portrait.rawValue, "Portrait": return .portrait
        default: return .landscape
        }
    }
}

/// Rotation applied when the external display is a vertically mounted TV.
enum ExternalRotationDirection: String, CaseIterable {
    case left = "Rotate Left"
    case right = "Rotate Right"

    var degrees: Double {
        self == .left ? -90 : 90
    }

    var iconName: String {
        self == .left ? "rotate.left" : "rotate.right"
    }
}

/// Logical width of the shared phone/TV web viewport (smaller = larger text).
enum WebTextSize: String, CaseIterable {
    case small = "Small"
    case medium = "Medium"
    case large = "Large"

    /// CSS viewport width before scale-up. Phone and AirPlay use the same value.
    var logicalWidth: CGFloat {
        switch self {
        case .small: return 520
        case .medium: return 430
        case .large: return 360
        }
    }
}

/// Persisted external-display preferences shared by camera and web presentation.
///
/// Orientation keys keep their original `EclipseTV.camera.*` names so existing
/// installs retain the user's landscape/portrait choice.
enum ExternalOutputSettings {
    private static let orientationKey = "EclipseTV.camera.outputOrientation"
    private static let rotationKey = "EclipseTV.camera.rotationDirection"
    private static let textSizeKey = "EclipseTV.web.textSize"

    /// Posted when orientation, rotation, or text size changes.
    static let didChangeNotification = Notification.Name("ExternalOutputSettings.didChange")

    static var orientation: ExternalOutputOrientation {
        get {
            ExternalOutputOrientation.resolved(
                fromStored: UserDefaults.standard.string(forKey: orientationKey))
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: orientationKey)
            NotificationCenter.default.post(name: didChangeNotification, object: nil)
        }
    }

    /// Convenience: Vertical (9:16) mode is active.
    static var isVerticalMode: Bool { orientation == .portrait }

    /// Active Landscape / Vertical library bucket.
    static var libraryMode: EclipseShareProtocol.LibraryMode {
        orientation.libraryMode
    }

    /// First-launch default is Landscape. Does not override a user's saved Display Mode
    /// (forcing Landscape every launch was hiding media left in Vertical).
    static func applyLaunchDefault() {
        guard UserDefaults.standard.string(forKey: orientationKey) == nil else { return }
        orientation = .landscape
    }

    static var rotationDirection: ExternalRotationDirection {
        get {
            guard let raw = UserDefaults.standard.string(forKey: rotationKey),
                  let value = ExternalRotationDirection(rawValue: raw) else {
                return .left
            }
            return value
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: rotationKey)
            NotificationCenter.default.post(name: didChangeNotification, object: nil)
        }
    }

    static var webTextSize: WebTextSize {
        get {
            guard let raw = UserDefaults.standard.string(forKey: textSizeKey),
                  let value = WebTextSize(rawValue: raw) else {
                return .medium
            }
            return value
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: textSizeKey)
            NotificationCenter.default.post(name: didChangeNotification, object: nil)
        }
    }

    /// Degrees to rotate external content (0 in landscape output).
    static var rotationDegrees: Double {
        orientation == .landscape ? 0 : rotationDirection.degrees
    }

    /// Shared web CSS viewport for phone preview and AirPlay TV.
    /// Vertical → 9:16; Landscape → 16:9. Width from `webTextSize`.
    static var webLogicalSize: CGSize {
        let width = webTextSize.logicalWidth
        let height = width / orientation.aspectRatio
        return CGSize(width: width, height: height)
    }

    /// Largest centered rect of the active Display Mode aspect that fits in `bounds`.
    /// Used by phone camera / Pages stages so framing matches the AirPlay panel.
    static func displayModePanelRect(in bounds: CGRect) -> CGRect {
        guard bounds.width > 0, bounds.height > 0 else { return .zero }
        let aspect = orientation.aspectRatio
        var width = bounds.width
        var height = width / aspect
        if height > bounds.height {
            height = bounds.height
            width = height * aspect
        }
        return CGRect(
            x: bounds.midX - width / 2,
            y: bounds.midY - height / 2,
            width: width,
            height: height
        )
    }
}
