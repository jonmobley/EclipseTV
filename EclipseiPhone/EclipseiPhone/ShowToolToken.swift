//
//  ShowToolToken.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import Foundation

/// Reserved ids for per-Show tool tiles in `LocalAlbum.surfaceIds`.
///
/// Never used as media / website membership ids.
enum ShowToolToken {
    static let screensaver = "__eclipse.tool.screensaver"
    static let logo = "__eclipse.tool.logo"
    static let camera = "__eclipse.tool.camera"

    /// Default leading tools when a Show has no customized surface.
    static let all: [String] = [screensaver, logo, camera]

    /// Display title for + menu / accessibility.
    static func title(for token: String) -> String? {
        switch token {
        case screensaver: return "Screensaver"
        case logo: return "Background"
        case camera: return "Camera"
        default: return nil
        }
    }

    /// SF Symbol for + menu actions.
    static func systemImage(for token: String) -> String? {
        switch token {
        case screensaver: return "sparkles.tv"
        case logo: return "seal.fill"
        case camera: return "camera.fill"
        default: return nil
        }
    }

    static func isTool(_ id: String) -> Bool {
        id == screensaver || id == logo || id == camera
    }
}
