//
//  ThumbnailTypeIcon.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import UIKit

/// Content kind of a library tile. Tiles show no type glyph (titles are plain
/// text, 2026-11-02); the kind feeds VoiceOver and the centre placeholder.
enum ThumbnailTypeIcon: Equatable {
    case photo
    case video
    case slideshow
    case website
    case webVideo
    case pdf
    case camera
    case ptzCamera
    case livePoll
    case countdown

    /// VoiceOver fragment appended to the tile name.
    var spokenName: String {
        switch self {
        case .photo: return "photo"
        case .video: return "video"
        case .slideshow: return "slideshow"
        case .website: return "website"
        case .webVideo: return "video link"
        case .pdf: return "PDF"
        case .camera: return "camera"
        case .ptzCamera: return "PTZ camera"
        case .livePoll: return "QuestPoll"
        case .countdown: return "countdown"
        }
    }

    /// Camera and Countdown fill the card centre themselves (preview / clock), so
    /// the large placeholder glyph is dropped. A poll card has nothing else there.
    var hidesCenterPlaceholder: Bool {
        self == .camera || self == .ptzCamera || self == .countdown
    }

    /// Photo vs video for a library still or clip.
    static func media(isVideo: Bool) -> ThumbnailTypeIcon {
        isVideo ? .video : .photo
    }
}
