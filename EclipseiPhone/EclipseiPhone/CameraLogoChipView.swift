//
//  CameraLogoChipView.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import UIKit

/// Corner Logo thumbnail used to park/resume Logo while staying in camera mode.
final class CameraLogoChipView: UIControl {

    // MARK: - Subviews

    private let imageView: UIImageView = {
        let view = UIImageView()
        view.contentMode = .scaleAspectFill
        view.clipsToBounds = true
        view.isUserInteractionEnabled = false
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    private let liveBadge: PaddedLabel = {
        let label = PaddedLabel()
        label.text = "LIVE"
        label.font = .systemFont(ofSize: 10, weight: .bold)
        label.textColor = .white
        label.backgroundColor = .systemRed
        label.textAlignment = .center
        label.layer.cornerRadius = 4
        label.layer.masksToBounds = true
        label.isHidden = true
        label.isUserInteractionEnabled = false
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    /// When true, shows the red stroke and LIVE badge.
    var isLogoLive = false {
        didSet { updateLiveChrome() }
    }

    // MARK: - Init

    override init(frame: CGRect) {
        super.init(frame: frame)
        setup()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Public

    /// Updates the chip image from `LogoStore`.
    func reloadImage() {
        imageView.image = LogoStore.shared.image
    }

    // MARK: - Private

    private func setup() {
        backgroundColor = .black
        layer.cornerRadius = 12
        layer.masksToBounds = true
        layer.borderColor = UIColor.systemRed.cgColor
        accessibilityLabel = "Logo"
        accessibilityTraits = .button

        addSubview(imageView)
        addSubview(liveBadge)

        NSLayoutConstraint.activate([
            imageView.topAnchor.constraint(equalTo: topAnchor),
            imageView.leadingAnchor.constraint(equalTo: leadingAnchor),
            imageView.trailingAnchor.constraint(equalTo: trailingAnchor),
            imageView.bottomAnchor.constraint(equalTo: bottomAnchor),

            liveBadge.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 6),
            liveBadge.topAnchor.constraint(equalTo: topAnchor, constant: 6)
        ])

        reloadImage()
        updateLiveChrome()
    }

    private func updateLiveChrome() {
        liveBadge.isHidden = !isLogoLive
        layer.borderWidth = isLogoLive ? 3 : 0
        accessibilityValue = isLogoLive ? "Live" : nil
    }
}
