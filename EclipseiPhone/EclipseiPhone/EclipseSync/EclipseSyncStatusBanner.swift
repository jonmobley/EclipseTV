//
//  EclipseSyncStatusBanner.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import UIKit

/// Decides whether the sync banner earns its space.
///
/// It shows on Home only, and a × dismissal is remembered per message, so the same
/// reminder does not return every launch while a different problem (quota, outage)
/// still does.
enum EclipseSyncBannerVisibility {

    static let dismissedMessageKey = "EclipseTV.syncBanner.dismissedMessage"

    static func shouldShow(text: String?, isOnHome: Bool, dismissedText: String?) -> Bool {
        guard let text, isOnHome else { return false }
        return text != dismissedText
    }
}

/// Compact banner for iCloud account / quota pauses, with a × to dismiss it.
/// Hidden when sync is healthy and while a Show is open.
final class EclipseSyncStatusBanner: UIView {

    private let label = UILabel()
    private let dismissButton = UIButton(type: .system)
    private var observer: NSObjectProtocol?
    private let defaults: UserDefaults

    /// True while the grid shows Home; the banner stays hidden inside a Show.
    var isOnHome = true {
        didSet { reload() }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        super.init(frame: .zero)
        // Opaque base under the orange tint: the banner floats over the grid, and a
        // see-through one let tiles scrolling beneath show through the text.
        backgroundColor = .systemBackground
        layer.cornerRadius = 10
        clipsToBounds = true
        isHidden = true

        let tint = UIView()
        tint.backgroundColor = UIColor.systemOrange.withAlphaComponent(0.15)
        tint.isUserInteractionEnabled = false
        tint.frame = bounds
        tint.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        addSubview(tint)

        label.font = .preferredFont(forTextStyle: .footnote)
        label.adjustsFontForContentSizeCategory = true
        label.textColor = .label
        label.numberOfLines = 0
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)

        var config = UIButton.Configuration.plain()
        config.image = UIImage(
            systemName: "xmark",
            withConfiguration: UIImage.SymbolConfiguration(pointSize: 12, weight: .semibold)
        )
        config.baseForegroundColor = .secondaryLabel
        config.contentInsets = NSDirectionalEdgeInsets(top: 8, leading: 8, bottom: 8, trailing: 10)
        dismissButton.configuration = config
        dismissButton.accessibilityLabel = "Dismiss"
        dismissButton.setContentHuggingPriority(.required, for: .horizontal)
        dismissButton.translatesAutoresizingMaskIntoConstraints = false
        dismissButton.addAction(UIAction { [weak self] _ in self?.dismissTapped() }, for: .touchUpInside)
        addSubview(dismissButton)

        NSLayoutConstraint.activate([
            label.topAnchor.constraint(equalTo: topAnchor, constant: 8),
            label.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -8),
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            label.trailingAnchor.constraint(equalTo: dismissButton.leadingAnchor, constant: -4),
            dismissButton.trailingAnchor.constraint(equalTo: trailingAnchor),
            dismissButton.centerYAnchor.constraint(equalTo: centerYAnchor),
            dismissButton.widthAnchor.constraint(greaterThanOrEqualToConstant: 36),
            dismissButton.heightAnchor.constraint(greaterThanOrEqualToConstant: 36)
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
        let text = EclipseSyncController.shared.statusBannerText
        let show = EclipseSyncBannerVisibility.shouldShow(
            text: text,
            isOnHome: isOnHome,
            dismissedText: defaults.string(forKey: EclipseSyncBannerVisibility.dismissedMessageKey)
        )
        label.text = show ? text : nil
        isHidden = !show
    }

    /// Hides the banner and remembers this message as seen.
    private func dismissTapped() {
        defaults.set(label.text, forKey: EclipseSyncBannerVisibility.dismissedMessageKey)
        reload()
    }
}
