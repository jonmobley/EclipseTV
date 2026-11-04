//
//  QuestPollJoinQRViewController.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import UIKit

/// Full-size join QR for a live QuestPoll room.
final class QuestPollJoinQRViewController: UIViewController {

    private let code: String
    private let joinURL: URL

    init(code: String, joinURL: URL) {
        self.code = code
        self.joinURL = joinURL
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Join"
        view.backgroundColor = .black
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            systemItem: .close,
            primaryAction: UIAction { [weak self] _ in
                self?.dismiss(animated: true)
            }
        )
        // Share sheet covers Copy, Messages, AirDrop — one place for the link.
        let share = UIBarButtonItem(
            systemItem: .action,
            primaryAction: UIAction { [weak self] _ in
                self?.shareLink()
            }
        )
        share.accessibilityLabel = "Share Join Link"
        navigationItem.leftBarButtonItem = share

        let imageView = UIImageView(image: Self.qrImage(for: joinURL.absoluteString))
        imageView.contentMode = .scaleAspectFit
        imageView.backgroundColor = .white
        imageView.layer.cornerRadius = CornerRadii.card
        imageView.layer.masksToBounds = true
        imageView.translatesAutoresizingMaskIntoConstraints = false

        let codeLabel = UILabel()
        codeLabel.text = code
        codeLabel.font = .monospacedSystemFont(ofSize: 28, weight: .bold)
        codeLabel.textColor = .white
        codeLabel.textAlignment = .center
        codeLabel.translatesAutoresizingMaskIntoConstraints = false

        let hint = UILabel()
        hint.text = joinURL.absoluteString
        hint.font = .systemFont(ofSize: 13, weight: .medium)
        hint.textColor = UIColor.white.withAlphaComponent(0.55)
        hint.textAlignment = .center
        hint.numberOfLines = 2
        hint.translatesAutoresizingMaskIntoConstraints = false

        // Code + link read as one block; the QR sits above it in portrait and
        // beside it in landscape, where 240pt plus the text was taller than the screen.
        let textStack = UIStackView(arrangedSubviews: [codeLabel, hint])
        textStack.axis = .vertical
        textStack.spacing = 8
        textStack.alignment = .fill

        let contentStack = UIStackView(arrangedSubviews: [imageView, textStack])
        contentStack.alignment = .center
        contentStack.translatesAutoresizingMaskIntoConstraints = false
        self.contentStack = contentStack
        view.addSubview(contentStack)

        let safe = view.safeAreaLayoutGuide
        // Full 240pt when it fits; otherwise the QR shrinks to the safe height.
        let preferredSide = imageView.widthAnchor.constraint(equalToConstant: 240)
        preferredSide.priority = .defaultHigh
        NSLayoutConstraint.activate([
            imageView.widthAnchor.constraint(equalTo: imageView.heightAnchor),
            imageView.widthAnchor.constraint(lessThanOrEqualToConstant: 240),
            imageView.heightAnchor.constraint(
                lessThanOrEqualTo: safe.heightAnchor, constant: -32
            ),
            preferredSide,
            textStack.widthAnchor.constraint(lessThanOrEqualToConstant: 360),
            contentStack.centerXAnchor.constraint(equalTo: safe.centerXAnchor),
            contentStack.centerYAnchor.constraint(equalTo: safe.centerYAnchor),
            contentStack.leadingAnchor.constraint(
                greaterThanOrEqualTo: safe.leadingAnchor, constant: 20
            ),
            contentStack.trailingAnchor.constraint(
                lessThanOrEqualTo: safe.trailingAnchor, constant: -20
            )
        ])
        applyContentAxis()
        registerForTraitChanges([UITraitVerticalSizeClass.self]) {
            (self: Self, _: UITraitCollection) in
            self.applyContentAxis()
        }
    }

    private var contentStack: UIStackView?

    /// Stacks the QR over the code, or side by side when the screen is short.
    private func applyContentAxis() {
        guard let contentStack else { return }
        let isShort = traitCollection.verticalSizeClass == .compact
        contentStack.axis = isShort ? .horizontal : .vertical
        contentStack.spacing = isShort ? 32 : 20
    }

    private func shareLink() {
        let activity = UIActivityViewController(
            activityItems: [joinURL], applicationActivities: nil
        )
        activity.popoverPresentationController?.barButtonItem =
            navigationItem.leftBarButtonItem
        present(activity, animated: true)
    }

    /// Renders a high-contrast QR for `string`.
    private static func qrImage(for string: String) -> UIImage? {
        let data = Data(string.utf8)
        guard let filter = CIFilter(name: "CIQRCodeGenerator") else { return nil }
        filter.setValue(data, forKey: "inputMessage")
        filter.setValue("M", forKey: "inputCorrectionLevel")
        guard let output = filter.outputImage else { return nil }
        let scaled = output.transformed(by: CGAffineTransform(scaleX: 10, y: 10))
        return UIImage(ciImage: scaled)
    }
}
