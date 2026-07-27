//
//  ExternalOutputSettings.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import UIKit

/// Orientation of AirPlay / external-display output (camera, web, etc.).
enum ExternalOutputOrientation: String, CaseIterable {
    case landscape = "Landscape"
    case portrait = "Portrait"

    /// Aspect ratio (width / height) for this orientation.
    var aspectRatio: CGFloat {
        self == .landscape ? 16.0 / 9.0 : 9.0 / 16.0
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

/// Logical width of the web view before scale-up (smaller = larger text on TV).
enum WebTextSize: String, CaseIterable {
    case small = "Small"
    case medium = "Medium"
    case large = "Large"

    /// Phone-like logical width used when rendering the page before scaling.
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
            guard let raw = UserDefaults.standard.string(forKey: orientationKey),
                  let value = ExternalOutputOrientation(rawValue: raw) else {
                return .landscape
            }
            return value
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: orientationKey)
            NotificationCenter.default.post(name: didChangeNotification, object: nil)
        }
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
}
