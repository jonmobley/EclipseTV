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

    /// Phone-portrait baseline column count (Landscape 2, Vertical 3).
    var gridColumnCount: CGFloat {
        self == .landscape ? 2 : 3
    }

    /// Preferred cell width so iPad / wide panes add columns instead of huge tiles.
    ///
    /// Vertical uses a wider target than Landscape's per-column density so a
    /// phone turned sideways lands on 4-up rather than packing 5–6 skinny tiles.
    var preferredGridItemWidth: CGFloat {
        self == .landscape ? 180 : 160
    }

    /// Width at which a Vertical grid gains its phone-landscape column (3 → 4).
    ///
    /// Below this, the portrait baseline (3) wins; at a turned phone's safe
    /// width (~600+) the floor becomes 4 before iPad fitted counts take over.
    private static let verticalLandscapeMinWidth: CGFloat = 600

    /// Column count for a collection width, never below the phone baseline.
    ///
    /// Vertical: 3-up in portrait, 4-up once the pane is phone-landscape wide,
    /// then more on iPad. Landscape: 2-up on a phone, more on wider panes.
    func gridColumnCount(
        forWidth width: CGFloat,
        sectionInset: CGFloat,
        spacing: CGFloat
    ) -> Int {
        let base = Int(gridColumnCount)
        let minimum: Int
        if self == .portrait, width >= Self.verticalLandscapeMinWidth {
            minimum = base + 1
        } else {
            minimum = base
        }
        let available = width - sectionInset * 2
        guard available > 0 else { return minimum }
        let preferred = preferredGridItemWidth
        let fitted = Int(floor((available + spacing) / (preferred + spacing)))
        return max(minimum, fitted)
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
    /// Desktop-width so responsive sites don't snap to their phone breakpoint.
    var logicalWidth: CGFloat {
        switch self {
        case .small: return 1440
        case .medium: return 1280
        case .large: return 1024
        }
    }
}

/// How the AirPlay / TV surface replaces one piece of content with another.
enum ContentTransitionStyle: String, CaseIterable {
    case crossfade = "Crossfade"
    case cut = "Cut"
}

/// Persisted external-display preferences shared by camera and web presentation.
///
/// Orientation keys keep their original `EclipseTV.camera.*` names so existing
/// installs retain the user's landscape/portrait choice.
enum ExternalOutputSettings {
    private static let orientationKey = "EclipseTV.camera.outputOrientation"
    private static let rotationKey = "EclipseTV.camera.rotationDirection"
    private static let textSizeKey = "EclipseTV.web.textSize"
    private static let transitionKey = "EclipseTV.contentTransition"
    private static let includeFrameInCapturesKey = "EclipseTV.camera.includeFrameInCaptures"
    private static let alwaysRecordWhenLiveKey = "EclipseTV.camera.alwaysRecordWhenLive"

    /// Posted when orientation, rotation, text size, transition,
    /// frame-in-captures, or always-record-when-live changes.
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

    /// Vertical is opt-in. If nothing is stored as a Vertical Show, snap back to
    /// Landscape — launch used to adopt Vertical just because that media bucket
    /// had test files.
    static func restoreLandscapeIfNoVerticalShows(_ albums: [LocalAlbum]) {
        guard isVerticalMode else { return }
        guard !albums.contains(where: { $0.orientation == .portrait }) else { return }
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

    /// Crossfade (default) or cut when switching live content.
    static var contentTransition: ContentTransitionStyle {
        get {
            guard let raw = UserDefaults.standard.string(forKey: transitionKey),
                  let value = ContentTransitionStyle(rawValue: raw) else {
                return .crossfade
            }
            return value
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: transitionKey)
            NotificationCenter.default.post(name: didChangeNotification, object: nil)
        }
    }

    /// When true, the selected camera frame is burned into saved photos and videos.
    ///
    /// Defaults on. Live preview always shows the overlay regardless of this setting.
    static var includeFrameInCaptures: Bool {
        get {
            guard UserDefaults.standard.object(forKey: includeFrameInCapturesKey) != nil else {
                return true
            }
            return UserDefaults.standard.bool(forKey: includeFrameInCapturesKey)
        }
        set {
            UserDefaults.standard.set(newValue, forKey: includeFrameInCapturesKey)
            NotificationCenter.default.post(name: didChangeNotification, object: nil)
        }
    }

    /// When true, video recording starts automatically whenever camera is live on AirPlay.
    ///
    /// Defaults off. Recording stops when you leave camera live (cutaway or another
    /// source). The record button does not start or stop independently while this is
    /// on; the photo button still takes a picture.
    static var alwaysRecordWhenLive: Bool {
        get {
            UserDefaults.standard.bool(forKey: alwaysRecordWhenLiveKey)
        }
        set {
            UserDefaults.standard.set(newValue, forKey: alwaysRecordWhenLiveKey)
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
