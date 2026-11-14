//
//  ShowToolToken.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import CryptoKit
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
    /// Further Prompters in the same Show: `__eclipse.tool.prompter.<nonce>`, each with
    /// its own script keyed by `extraPrompterScriptId(nonce:showId:)`. Older builds keep
    /// these tokens through sync because they carry `prefix`.
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
        id == prompter || extraPrompterNonce(from: id) != nil
    }

    /// Token for a new extra Prompter: a random nonce, not the script id.
    static func newExtraPrompterToken() -> String {
        extraPrompterPrefix + UUID().uuidString
    }

    /// The nonce in an extra Prompter token, or nil for any other id.
    static func extraPrompterNonce(from id: String) -> UUID? {
        guard id.hasPrefix(extraPrompterPrefix) else { return nil }
        return UUID(uuidString: String(id.dropFirst(extraPrompterPrefix.count)))
    }

    /// The script id of the extra Prompter with `nonce` in Show `showId`.
    ///
    /// Derived from both, so the script belongs to that Show by construction: the
    /// same token on another Show (planted through a synced or shared surface, or
    /// left after its own Show removed the tile) names a different, empty script and
    /// can never read, edit, copy or delete this one. The result is a version-8 UUID;
    /// Show ids are random version-4 ids, so it is never a Show's own script either.
    static func extraPrompterScriptId(nonce: UUID, showId: UUID) -> UUID {
        let digest = SHA256.hash(data: Data("eclipse.prompter|\(showId.uuidString)|\(nonce.uuidString)".utf8))
        var bytes = Array(digest.prefix(16))
        bytes[6] = (bytes[6] & 0x0F) | 0x80
        bytes[8] = (bytes[8] & 0x3F) | 0x80
        return UUID(uuid: (
            bytes[0], bytes[1], bytes[2], bytes[3], bytes[4], bytes[5], bytes[6], bytes[7],
            bytes[8], bytes[9], bytes[10], bytes[11], bytes[12], bytes[13], bytes[14], bytes[15]
        ))
    }

    /// Whether `id` has the extra-Prompter (version 8) shape.
    static func isExtraPrompterScriptId(_ id: UUID) -> Bool {
        id.uuid.6 & 0xF0 == 0x80
    }

    /// The `PrompterScriptStore` key behind a Prompter token in Show `showId`:
    /// the Show id for the first Prompter, derived from Show and nonce for an extra one.
    static func prompterScriptId(from id: String, showId: UUID) -> UUID? {
        if id == prompter { return showId }
        return extraPrompterNonce(from: id).map { extraPrompterScriptId(nonce: $0, showId: showId) }
    }

    /// Script ids of every Prompter on `surfaceIds` (Show `showId`), in grid order.
    static func prompterScriptIds(in surfaceIds: [String], showId: UUID) -> [UUID] {
        surfaceIds.compactMap { prompterScriptId(from: $0, showId: showId) }
    }
}
