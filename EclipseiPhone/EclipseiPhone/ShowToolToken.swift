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
    /// The Show's first teleprompter: a scrolling script for the presenter. Its script
    /// is keyed by the Show id (the `prompter-<showId>` record the Mac also reads).
    static let prompter = "__eclipse.tool.prompter"
    /// Further Prompters in the same Show: `__eclipse.tool.prompter.<scriptId>`, each
    /// with its own script keyed by that id. Older builds keep these tokens through
    /// sync because they carry `prefix`.
    static let extraPrompterPrefix = prompter + "."

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
    static let optional: [String] = [prompter, ptzCamera]

    /// Display title for + menu / accessibility.
    static func title(for token: String) -> String? {
        switch token {
        case screensaver: return "Screensaver"
        case logo: return "Background"
        case camera: return "Camera"
        case ptzCamera: return "PTZ Camera"
        case prompter: return "Prompter"
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
        case prompter: return "text.alignleft"
        default: return nil
        }
    }

    static func isTool(_ id: String) -> Bool {
        id == screensaver || id == logo || id == camera || id == ptzCamera
            || isPrompter(id)
    }

    // MARK: - Prompters

    /// Whether `id` is any Prompter tile (the first one or an extra one).
    static func isPrompter(_ id: String) -> Bool {
        id == prompter || extraPrompterScriptId(from: id) != nil
    }

    /// Token for an extra Prompter whose script is keyed by `scriptId`.
    static func extraPrompterToken(scriptId: UUID) -> String {
        extraPrompterPrefix + scriptId.uuidString
    }

    /// The script id in an extra Prompter token, or nil for any other id.
    static func extraPrompterScriptId(from id: String) -> UUID? {
        guard id.hasPrefix(extraPrompterPrefix) else { return nil }
        return UUID(uuidString: String(id.dropFirst(extraPrompterPrefix.count)))
    }

    /// The `PrompterScriptStore` key behind a Prompter token in Show `showId`:
    /// the Show id for the first Prompter, its own id for an extra one.
    static func prompterScriptId(from id: String, showId: UUID) -> UUID? {
        id == prompter ? showId : extraPrompterScriptId(from: id)
    }

    /// The surface token for the Prompter whose script is keyed by `scriptId`.
    static func prompterToken(scriptId: UUID, showId: UUID) -> String {
        scriptId == showId ? prompter : extraPrompterToken(scriptId: scriptId)
    }

    /// Script ids of every Prompter on `surfaceIds` (Show `showId`), in grid order.
    static func prompterScriptIds(in surfaceIds: [String], showId: UUID) -> [UUID] {
        surfaceIds.compactMap { prompterScriptId(from: $0, showId: showId) }
    }
}
