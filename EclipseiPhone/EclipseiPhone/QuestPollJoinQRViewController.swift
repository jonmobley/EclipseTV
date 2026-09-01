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
        title = "Join QR"
        view.backgroundColor = .black
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            systemItem: .close,
            primaryAction: UIAction { [weak self] _ in
                self?.dismiss(animated: true)
            }
        )

        let imageView = UIImageView(image: Self.qrImage(for: joinURL.absoluteString))
        imageView.contentMode = .scaleAspectFit
        imageView.backgroundColor = .white
        imageView.layer.cornerRadius = 16
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

        view.addSubview(imageView)
        view.addSubview(codeLabel)
        view.addSubview(hint)
        NSLayoutConstraint.activate([
            imageView.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            imageView.centerYAnchor.constraint(
                equalTo: view.centerYAnchor, constant: -40
            ),
            imageView.widthAnchor.constraint(equalToConstant: 240),
            imageView.heightAnchor.constraint(equalToConstant: 240),
            codeLabel.topAnchor.constraint(
                equalTo: imageView.bottomAnchor, constant: 20
            ),
            codeLabel.leadingAnchor.constraint(
                equalTo: view.leadingAnchor, constant: 20
            ),
            codeLabel.trailingAnchor.constraint(
                equalTo: view.trailingAnchor, constant: -20
            ),
            hint.topAnchor.constraint(equalTo: codeLabel.bottomAnchor, constant: 8),
            hint.leadingAnchor.constraint(
                equalTo: view.leadingAnchor, constant: 20
            ),
            hint.trailingAnchor.constraint(
                equalTo: view.trailingAnchor, constant: -20
            )
        ])
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
