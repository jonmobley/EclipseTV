//
//  CameraPicturesSheetModel.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import Foundation

// MARK: - CameraPictureEntry

/// One tile in the camera's Pictures sheet or frame ribbon.
enum CameraPictureEntry: Hashable {
    /// Frame from the Mac show's Camera Kit.
    case kitFrame(UUID)
    /// Picture from the Mac show's Camera Kit.
    case kitStill(UUID)
    /// One of the phone's own frames.
    case ownFrame(UUID)
    /// One of the phone's own quick-change pictures.
    case ownStill(UUID)

    /// True for frames (drawn over a transparency checkerboard).
    var isFrame: Bool {
        switch self {
        case .kitFrame, .ownFrame: return true
        case .kitStill, .ownStill: return false
        }
    }

    /// The underlying id.
    var id: UUID {
        switch self {
        case .kitFrame(let id), .kitStill(let id), .ownFrame(let id), .ownStill(let id):
            return id
        }
    }
}

// MARK: - CameraPicturesSection

/// A titled group of tiles in the Pictures sheet.
struct CameraPicturesSection: Equatable {
    let title: String
    let entries: [CameraPictureEntry]
}

// MARK: - CameraPicturesSheetModel

/// Decides what the Pictures sheet and frame ribbon show (pure, unit-tested).
enum CameraPicturesSheetModel {

    /// What the phone has to offer.
    struct Inputs {
        var showName: String?
        var kitFrames: [UUID] = []
        var kitStills: [UUID] = []
        var ownFrames: [UUID] = []
        var ownStills: [UUID] = []
        /// False when the show's kit is locked.
        var showsOwn = true
    }

    /// Sheet sections, kit first; empty sections are left out.
    /// - Parameter inputs: Available pictures.
    /// - Returns: Sections in display order.
    static func sections(_ inputs: Inputs) -> [CameraPicturesSection] {
        var result: [CameraPicturesSection] = []
        let show = inputs.showName ?? "Camera Kit"
        append(&result, "\(show) · Frames", inputs.kitFrames.map(CameraPictureEntry.kitFrame))
        append(&result, "\(show) · Pictures", inputs.kitStills.map(CameraPictureEntry.kitStill))
        if inputs.showsOwn {
            append(&result, "My Frames", inputs.ownFrames.map(CameraPictureEntry.ownFrame))
            append(&result, "My Pictures", inputs.ownStills.map(CameraPictureEntry.ownStill))
        }
        return result
    }

    /// Frame ribbon order: kit frames, then own frames unless locked.
    /// - Parameter inputs: Available pictures.
    /// - Returns: Frame entries.
    static func frameRibbon(_ inputs: Inputs) -> [CameraPictureEntry] {
        let own = inputs.showsOwn ? inputs.ownFrames.map(CameraPictureEntry.ownFrame) : []
        return inputs.kitFrames.map(CameraPictureEntry.kitFrame) + own
    }

    private static func append(
        _ sections: inout [CameraPicturesSection],
        _ title: String,
        _ entries: [CameraPictureEntry]
    ) {
        guard !entries.isEmpty else { return }
        sections.append(CameraPicturesSection(title: title, entries: entries))
    }
}
