//
//  ThumbnailTypeIcon.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import UIKit

/// Content kind shown as a bottom-leading glyph on a library thumbnail.
enum ThumbnailTypeIcon: Equatable {
    case photo
    case video
    case slideshow
    case website
    case pdf

    /// SF Symbol used on the overlay (matches existing Show-grid placeholders).
    var systemName: String {
        switch self {
        case .photo: return "photo.fill"
        case .video: return "video.fill"
        case .slideshow: return "rectangle.stack.fill"
        case .website: return "safari"
        case .pdf: return "doc.richtext"
        }
    }

    /// VoiceOver fragment appended to the tile name.
    var spokenName: String {
        switch self {
        case .photo: return "photo"
        case .video: return "video"
        case .slideshow: return "slideshow"
        case .website: return "website"
        case .pdf: return "PDF"
        }
    }

    /// Photo vs video for a library still or clip.
    static func media(isVideo: Bool) -> ThumbnailTypeIcon {
        isVideo ? .video : .photo
    }
}

/// Dark disc + white glyph so the type reads on light or dark thumbnail art.
final class ThumbnailTypeIconView: UIView {

    static let side: CGFloat = 24
    static let inset: CGFloat = 8
    /// Caption leading inset that clears this disc.
    static let captionClearance: CGFloat = 38

    private let iconView = UIImageView()
    /// Last icon shown, or nil when hidden.
    private(set) var appliedIcon: ThumbnailTypeIcon?

    override init(frame: CGRect) {
        super.init(frame: frame)
        isHidden = true
        isUserInteractionEnabled = false
        backgroundColor = UIColor.black.withAlphaComponent(0.55)
        layer.cornerRadius = Self.side / 2
        clipsToBounds = true

        iconView.tintColor = .white
        iconView.contentMode = .scaleAspectFit
        iconView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(iconView)
        NSLayoutConstraint.activate([
            iconView.centerXAnchor.constraint(equalTo: centerXAnchor),
            iconView.centerYAnchor.constraint(equalTo: centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 13),
            iconView.heightAnchor.constraint(equalToConstant: 13)
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// Shows `icon`, or hides when `icon` is nil.
    func apply(_ icon: ThumbnailTypeIcon?) {
        appliedIcon = icon
        isHidden = icon == nil
        guard let icon else { return }
        let config = UIImage.SymbolConfiguration(pointSize: 11, weight: .semibold)
        iconView.image = UIImage(systemName: icon.systemName, withConfiguration: config)
        accessibilityLabel = icon.spokenName
    }
}
