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
    /// Q&A rooms: say the QR stops working when the room ends.
    private let showsLifetimeNote: Bool

    init(code: String, joinURL: URL, showsLifetimeNote: Bool = true) {
        self.code = code
        self.joinURL = joinURL
        self.showsLifetimeNote = showsLifetimeNote
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
        // Share sheet covers Save Image, Copy, Messages, AirDrop: the QR
        // picture and the link in one place.
        let share = UIBarButtonItem(
            systemItem: .action,
            primaryAction: UIAction { [weak self] _ in
                self?.shareQR()
            }
        )
        share.accessibilityLabel = "Save or Share QR Code"
        navigationItem.leftBarButtonItem = share

        let imageView = UIImageView(image: Self.qrImage(for: joinURL.absoluteString))
        imageView.isUserInteractionEnabled = true
        imageView.addInteraction(UIContextMenuInteraction(delegate: self))
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
        // A room gets a new code each time it starts, so a saved or printed
        // QR only works for this one.
        let lifetime = UILabel()
        lifetime.text = "Works until you end this Q&A."
        lifetime.font = .systemFont(ofSize: 13)
        lifetime.textColor = UIColor.white.withAlphaComponent(0.55)
        lifetime.textAlignment = .center
        lifetime.numberOfLines = 0
        lifetime.isHidden = !showsLifetimeNote

        let textStack = UIStackView(arrangedSubviews: [codeLabel, hint, lifetime])
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

    private func shareQR() {
        var items: [Any] = []
        if let png = Self.qrPNG(for: joinURL.absoluteString) {
            items.append(png)
        }
        items.append(joinURL)
        let activity = UIActivityViewController(
            activityItems: items, applicationActivities: nil
        )
        activity.popoverPresentationController?.barButtonItem =
            navigationItem.leftBarButtonItem
        present(activity, animated: true)
    }

    /// Print-ready QR picture (black on white with a quiet zone), as a
    /// bitmap-backed image so Save Image and AirDrop get a real PNG.
    static func qrPNG(for string: String, side: CGFloat = 1024) -> UIImage? {
        guard let ciImage = qrImage(for: string)?.ciImage,
              let cgImage = CIContext().createCGImage(ciImage, from: ciImage.extent)
        else { return nil }
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let renderer = UIGraphicsImageRenderer(
            size: CGSize(width: side, height: side), format: format
        )
        return renderer.image { context in
            UIColor.white.setFill()
            context.fill(CGRect(x: 0, y: 0, width: side, height: side))
            context.cgContext.interpolationQuality = .none
            let inset = side * 0.08
            // Draw upright: Core Graphics flips y.
            context.cgContext.translateBy(x: 0, y: side)
            context.cgContext.scaleBy(x: 1, y: -1)
            context.cgContext.draw(
                cgImage,
                in: CGRect(x: inset, y: inset, width: side - inset * 2, height: side - inset * 2)
            )
        }
    }

    /// Renders a high-contrast QR for `string`.
    static func qrImage(for string: String) -> UIImage? {
        let data = Data(string.utf8)
        guard let filter = CIFilter(name: "CIQRCodeGenerator") else { return nil }
        filter.setValue(data, forKey: "inputMessage")
        filter.setValue("M", forKey: "inputCorrectionLevel")
        guard let output = filter.outputImage else { return nil }
        let scaled = output.transformed(by: CGAffineTransform(scaleX: 10, y: 10))
        return UIImage(ciImage: scaled)
    }
}

// MARK: - Press and hold the QR

extension QuestPollJoinQRViewController: UIContextMenuInteractionDelegate {
    func contextMenuInteraction(
        _ interaction: UIContextMenuInteraction,
        configurationForMenuAtLocation location: CGPoint
    ) -> UIContextMenuConfiguration? {
        UIContextMenuConfiguration(actionProvider: { [weak self] _ in
            UIMenu(children: [
                UIAction(
                    title: "Save to Photos",
                    image: UIImage(systemName: "square.and.arrow.down")
                ) { _ in self?.saveQRToPhotos() },
                UIAction(
                    title: "Copy Link",
                    image: UIImage(systemName: "link")
                ) { _ in UIPasteboard.general.url = self?.joinURL },
                UIAction(
                    title: "Share…",
                    image: UIImage(systemName: "square.and.arrow.up")
                ) { _ in self?.shareQR() }
            ])
        })
    }

    private func saveQRToPhotos() {
        guard let png = Self.qrPNG(for: joinURL.absoluteString) else { return }
        UIImageWriteToSavedPhotosAlbum(png, nil, nil, nil)
        Haptics.impactLight()
    }
}
