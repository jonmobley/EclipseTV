//
//  MediaImportProgressView.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import UIKit

/// Blocking overlay shown while picked media downloads from iCloud.
///
/// A determinate bar when the system tells us how far along the download is, a
/// spinner when it hasn't said yet, and a Cancel that stops it. The backdrop
/// swallows touches so a second import can't be started on top of this one.
final class MediaImportProgressView: UIView {

    /// Called when the user taps Cancel.
    var onCancel: (() -> Void)?

    private let card = UIView()
    private let titleLabel = UILabel()
    private let progressBar = UIProgressView(progressViewStyle: .default)
    private let spinner = UIActivityIndicatorView(style: .medium)
    private let cancelButton = UIButton(type: .system)
    private var isShown = false

    // MARK: - Init

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupUI()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupUI()
    }

    // MARK: - Updates

    /// Sets the message and progress.
    ///
    /// - Parameters:
    ///   - title: What the import is doing right now.
    ///   - fraction: Combined download progress, or nil while unknown.
    ///   - canCancel: False once a cancel is already unwinding.
    func update(title: String, fraction: Double?, canCancel: Bool = true) {
        titleLabel.text = title
        if let fraction {
            spinner.stopAnimating()
            spinner.isHidden = true
            progressBar.isHidden = false
            progressBar.setProgress(Float(min(max(fraction, 0), 1)), animated: true)
        } else {
            progressBar.isHidden = true
            spinner.isHidden = false
            spinner.startAnimating()
        }
        cancelButton.isEnabled = canCancel
        cancelButton.alpha = canCancel ? 1 : 0.4
    }

    /// Fades the overlay in or out. Repeat calls with the same value do nothing,
    /// so per-tick renders don't restart the animation.
    func setVisible(_ visible: Bool) {
        guard visible != isShown else { return }
        isShown = visible
        if visible { isHidden = false }
        UIView.animate(withDuration: 0.2) {
            self.alpha = visible ? 1 : 0
        } completion: { _ in
            if !visible {
                self.isHidden = true
                self.spinner.stopAnimating()
                self.progressBar.setProgress(0, animated: false)
            }
        }
    }

    // MARK: - Setup

    private func setupUI() {
        backgroundColor = UIColor.black.withAlphaComponent(0.35)
        alpha = 0
        isHidden = true

        card.backgroundColor = UIColor.black.withAlphaComponent(0.8)
        card.layer.applyContinuousCorner(radius: CornerRadii.card)

        titleLabel.textAlignment = .center
        titleLabel.textColor = .white
        titleLabel.font = .systemFont(ofSize: 16, weight: .semibold)
        titleLabel.numberOfLines = 2

        progressBar.progressTintColor = .systemBlue
        progressBar.trackTintColor = UIColor.white.withAlphaComponent(0.25)
        progressBar.isHidden = true

        spinner.color = .white
        spinner.hidesWhenStopped = false
        spinner.isHidden = true

        cancelButton.setTitle("Cancel", for: .normal)
        cancelButton.titleLabel?.font = .systemFont(ofSize: 17, weight: .medium)
        cancelButton.setTitleColor(.white, for: .normal)
        cancelButton.backgroundColor = .systemRed
        cancelButton.layer.applyContinuousCorner(radius: CornerRadii.standard)
        cancelButton.addTarget(self, action: #selector(cancelTapped), for: .touchUpInside)

        addSubview(card)
        [titleLabel, progressBar, spinner, cancelButton].forEach(card.addSubview)
        [card, titleLabel, progressBar, spinner, cancelButton].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
        }

        activateConstraints()
    }

    private func activateConstraints() {
        NSLayoutConstraint.activate([
            card.centerXAnchor.constraint(equalTo: centerXAnchor),
            card.centerYAnchor.constraint(equalTo: centerYAnchor),
            card.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor, constant: 32),
            card.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -32),
            card.widthAnchor.constraint(equalToConstant: 280),

            titleLabel.topAnchor.constraint(equalTo: card.topAnchor, constant: 22),
            titleLabel.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 20),
            titleLabel.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -20),

            progressBar.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 18),
            progressBar.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 20),
            progressBar.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -20),

            spinner.centerXAnchor.constraint(equalTo: card.centerXAnchor),
            spinner.centerYAnchor.constraint(equalTo: progressBar.centerYAnchor),

            cancelButton.topAnchor.constraint(equalTo: progressBar.bottomAnchor, constant: 20),
            cancelButton.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 20),
            cancelButton.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -20),
            cancelButton.heightAnchor.constraint(equalToConstant: 44),
            cancelButton.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -20)
        ])
    }

    @objc private func cancelTapped() {
        onCancel?()
    }
}
