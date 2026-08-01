//
//  EclipseSyncStatusBanner.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import UIKit

/// Compact banner for iCloud account / quota pauses. Hidden when sync is healthy.
final class EclipseSyncStatusBanner: UIView {

    private let label = UILabel()
    private var observer: NSObjectProtocol?

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = UIColor.systemOrange.withAlphaComponent(0.15)
        layer.cornerRadius = 10
        clipsToBounds = true
        isHidden = true

        label.font = .preferredFont(forTextStyle: .footnote)
        label.adjustsFontForContentSizeCategory = true
        label.textColor = .label
        label.numberOfLines = 0
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)
        NSLayoutConstraint.activate([
            label.topAnchor.constraint(equalTo: topAnchor, constant: 8),
            label.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -8),
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12)
        ])

        observer = NotificationCenter.default.addObserver(
            forName: EclipseSyncController.statusDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.reload()
        }
        reload()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        if let observer {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    /// Refreshes visibility and copy from `EclipseSyncController`.
    func reload() {
        if let text = EclipseSyncController.shared.statusBannerText {
            label.text = text
            isHidden = false
        } else {
            label.text = nil
            isHidden = true
        }
    }
}
