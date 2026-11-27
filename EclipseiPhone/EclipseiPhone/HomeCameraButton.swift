//
//  HomeCameraButton.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import UIKit

/// Round Camera button in the bottom-leading corner of Home, Library, Show and
/// Music, mirroring the Music circle in the trailing corner (owner's call
/// 2026-11-26, replacing the "Camera" word on the tab row).
///
/// Dark grey, never blue: blue means "on the TV", and the Music circle stays the
/// one coloured control. While the phone camera is on the TV it wears a blue ring.
final class HomeCameraButton: UIButton {

    /// Same size as the Music circle, so the two corners match.
    static let side: CGFloat = AudioMiniPlayerBubbleView.side
    /// Same distance from the screen edges as the Music circle.
    static let edgeInset: CGFloat = AudioMiniPlayerView.compactTrailingInset
    static let bottomInset: CGFloat = AudioMiniPlayerView.compactBottomInset
    /// Room kept between the button and the open music card before it hides.
    static let clearance: CGFloat = 8

    override init(frame: CGRect) {
        super.init(frame: frame)
        setup()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var intrinsicContentSize: CGSize {
        CGSize(width: Self.side, height: Self.side)
    }

    /// Whether the button gives way: while the music card would cover it (it
    /// spans the width of a phone held upright), while tiles are being arranged
    /// or selected, and while a search field has the keyboard.
    static func shouldHide(
        cardFrame: CGRect?,
        buttonFrame: CGRect,
        isEditing: Bool,
        isSearching: Bool
    ) -> Bool {
        if isEditing || isSearching { return true }
        guard let cardFrame, !cardFrame.isEmpty else { return false }
        return cardFrame.intersects(buttonFrame.insetBy(dx: -clearance, dy: -clearance))
    }

    /// Blue ring while the phone camera is what the TV shows.
    func setCameraOnTV(_ onTV: Bool) {
        layer.borderWidth = onTV ? 2.5 : 0
        accessibilityValue = onTV ? "On the TV" : nil
    }

    // MARK: - Private

    private func setup() {
        var config = UIButton.Configuration.filled()
        config.image = UIImage(
            systemName: "camera.fill",
            withConfiguration: UIImage.SymbolConfiguration(pointSize: 22, weight: .semibold)
        )
        config.baseForegroundColor = .white
        config.baseBackgroundColor = UIColor(white: 0.22, alpha: 0.96)
        config.cornerStyle = .capsule
        configuration = config

        layer.cornerRadius = Self.side / 2
        layer.borderColor = UIColor.liveStroke.cgColor
        layer.shadowColor = UIColor.black.cgColor
        layer.shadowOpacity = 0.28
        layer.shadowRadius = 12
        layer.shadowOffset = CGSize(width: 0, height: 4)

        accessibilityIdentifier = "home.cameraButton"
        accessibilityLabel = "Camera"
        accessibilityHint =
            "Opens the camera. Nothing goes to the TV until you tap the picture."
        setContentHuggingPriority(.required, for: .horizontal)
        setContentHuggingPriority(.required, for: .vertical)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        layer.shadowPath = UIBezierPath(ovalIn: bounds).cgPath
    }
}
