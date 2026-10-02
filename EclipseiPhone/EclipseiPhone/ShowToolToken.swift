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
    /// A network PTZ camera (OBSBOT Tail 2) shown and controlled via CamTailKit.
    static let ptzCamera = "__eclipse.tool.ptzCamera"

    /// Every reserved tool id starts with this. Unknown ids with it (tools added by a
    /// newer Eclipse) are kept through sync, so an older build never strips them —
    /// except `retired` ones, which are deliberately dropped.
    static let prefix = "__eclipse.tool."

    /// Tool ids Eclipse no longer uses; dropped from surfaces rather than kept.
    static let retired: Set<String> = ["__eclipse.tool.blackout"]

    /// Default leading tools when a Show has no customized surface. (PTZ Camera is not
    /// a default: it only appears when added from the + menu.)
    static let all: [String] = [screensaver, logo, camera]

    /// Default tools that can appear in the + menu when removed from the surface.
    static let addable: [String] = all

    /// Opt-in tools (not on new Shows) offered in the + menu until added.
    static let optional: [String] = [ptzCamera]

    /// Display title for + menu / accessibility.
    static func title(for token: String) -> String? {
        switch token {
        case screensaver: return "Screensaver"
        case logo: return "Background"
        case camera: return "Camera"
        case ptzCamera: return "PTZ Camera"
        default: return nil
        }
    }

    /// SF Symbol for + menu actions.
    static func systemImage(for token: String) -> String? {
        switch token {
        case screensaver: return "sparkles.tv"
        case logo: return "seal.fill"
        case camera: return "camera.fill"
        case ptzCamera: return "web.camera"
        default: return nil
        }
    }

    static func isTool(_ id: String) -> Bool {
        id == screensaver || id == logo || id == camera || id == ptzCamera
    }
}
