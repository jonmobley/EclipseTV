//
//  ImagePreviewViewController.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import UIKit

/// Notifies the host when the user confirms or cancels sending a previewed image.
protocol ImagePreviewDelegate: AnyObject {
    func imagePreview(_ controller: ImagePreviewViewController, didConfirm image: UIImage)
    func imagePreviewDidCancel(_ controller: ImagePreviewViewController)
}

/// A lightweight confirmation screen shown after the user picks an image.
/// Copy reflects whether Multipeer is linked to the Eclipse TV app (Send) or the
/// image is only being added to the phone library (Add).
final class ImagePreviewViewController: UIViewController {

    // MARK: - Properties

    weak var delegate: ImagePreviewDelegate?
    private let image: UIImage
    /// True when the Eclipse TV Multipeer link is up — confirms a send, not just an add.
    private let sendsToAppleTV: Bool

    // MARK: - UI Elements

    private let containerView: UIView = {
        let view = UIView()
        view.backgroundColor = .black
        view.layer.cornerRadius = 12
        view.clipsToBounds = true
        return view
    }()

    private let imageView: UIImageView = {
        let imageView = UIImageView()
        imageView.contentMode = .scaleAspectFit
        imageView.backgroundColor = .black
        imageView.layer.cornerRadius = 8
        imageView.clipsToBounds = true
        return imageView
    }()

    private let instructionLabel: UILabel = {
        let label = UILabel()
        label.textColor = .lightGray
        label.font = UIFont.systemFont(ofSize: 16)
        label.textAlignment = .center
        label.numberOfLines = 0
        return label
    }()

    private let buttonStackView: UIStackView = {
        let stack = UIStackView()
        stack.axis = .horizontal
        stack.distribution = .fillEqually
        stack.spacing = 16
        return stack
    }()

    private let cancelButton: UIButton = {
        let button = UIButton(type: .system)
        button.setTitle("Cancel", for: .normal)
        button.titleLabel?.font = UIFont.systemFont(ofSize: 18, weight: .medium)
        button.setTitleColor(.systemRed, for: .normal)
        button.backgroundColor = UIColor.systemRed.withAlphaComponent(0.1)
        button.layer.cornerRadius = 25
        return button
    }()

    private let confirmButton: UIButton = {
        let button = UIButton(type: .system)
        button.titleLabel?.font = UIFont.systemFont(ofSize: 18, weight: .medium)
        button.setTitleColor(.white, for: .normal)
        button.backgroundColor = .systemBlue
        button.layer.cornerRadius = 25
        return button
    }()

    // MARK: - Initialization

    /// - Parameter sendsToAppleTV: When true, copy asks to send to the TV app; otherwise
    ///   it asks to add to the phone library.
    init(image: UIImage, sendsToAppleTV: Bool) {
        self.image = image
        self.sendsToAppleTV = sendsToAppleTV
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
        setupActions()
        imageView.image = image
        if sendsToAppleTV {
            instructionLabel.text = "Send this image to your Apple TV?"
            confirmButton.setTitle("Send", for: .normal)
        } else {
            instructionLabel.text = "Add this image to your Show?"
            confirmButton.setTitle("Add", for: .normal)
        }
    }

    // MARK: - Setup

    private func setupUI() {
        view.backgroundColor = UIColor.black.withAlphaComponent(0.8)

        view.addSubview(containerView)
        containerView.addSubview(imageView)
        containerView.addSubview(instructionLabel)
        containerView.addSubview(buttonStackView)

        buttonStackView.addArrangedSubview(cancelButton)
        buttonStackView.addArrangedSubview(confirmButton)

        containerView.translatesAutoresizingMaskIntoConstraints = false
        imageView.translatesAutoresizingMaskIntoConstraints = false
        instructionLabel.translatesAutoresizingMaskIntoConstraints = false
        buttonStackView.translatesAutoresizingMaskIntoConstraints = false

        NSLayoutConstraint.activate([
            containerView.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            containerView.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            containerView.widthAnchor.constraint(equalTo: view.widthAnchor, multiplier: 0.9),
            containerView.heightAnchor.constraint(lessThanOrEqualTo: view.heightAnchor, multiplier: 0.85),

            imageView.topAnchor.constraint(equalTo: containerView.topAnchor, constant: 20),
            imageView.leadingAnchor.constraint(equalTo: containerView.leadingAnchor, constant: 20),
            imageView.trailingAnchor.constraint(equalTo: containerView.trailingAnchor, constant: -20),
            // Preview chrome matches active library: 16:9 Landscape or 9:16 Vertical.
            imageView.heightAnchor.constraint(
                equalTo: imageView.widthAnchor,
                multiplier: ExternalOutputSettings.isVerticalMode ? (16.0 / 9.0) : (9.0 / 16.0)
            ),

            instructionLabel.topAnchor.constraint(equalTo: imageView.bottomAnchor, constant: 16),
            instructionLabel.leadingAnchor.constraint(equalTo: containerView.leadingAnchor, constant: 20),
            instructionLabel.trailingAnchor.constraint(equalTo: containerView.trailingAnchor, constant: -20),

            buttonStackView.topAnchor.constraint(equalTo: instructionLabel.bottomAnchor, constant: 24),
            buttonStackView.leadingAnchor.constraint(equalTo: containerView.leadingAnchor, constant: 20),
            buttonStackView.trailingAnchor.constraint(equalTo: containerView.trailingAnchor, constant: -20),
            buttonStackView.bottomAnchor.constraint(equalTo: containerView.bottomAnchor, constant: -20),
            buttonStackView.heightAnchor.constraint(equalToConstant: 50)
        ])
    }

    private func setupActions() {
        cancelButton.addTarget(self, action: #selector(cancelTapped), for: .touchUpInside)
        confirmButton.addTarget(self, action: #selector(confirmTapped), for: .touchUpInside)
    }

    // MARK: - Actions

    @objc private func cancelTapped() {
        delegate?.imagePreviewDidCancel(self)
    }

    @objc private func confirmTapped() {
        delegate?.imagePreview(self, didConfirm: image)
    }
}
