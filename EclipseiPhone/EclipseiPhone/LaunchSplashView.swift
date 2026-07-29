//
//  LaunchSplashView.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import UIKit

/// Full-screen splash matching `LaunchScreen.storyboard`; fades out over the main UI.
final class LaunchSplashView: UIView {

    // MARK: - Constants

    private static let logoSide: CGFloat = 200
    private static let holdDuration: TimeInterval = 0.55
    private static let fadeDuration: TimeInterval = 0.45

    // MARK: - Subviews

    private let logoView: UIImageView = {
        let view = UIImageView(image: UIImage(named: "EclipseLogo"))
        view.contentMode = .scaleAspectFit
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    // MARK: - Init

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .black
        isUserInteractionEnabled = true
        addSubview(logoView)
        NSLayoutConstraint.activate([
            logoView.centerXAnchor.constraint(equalTo: centerXAnchor),
            logoView.centerYAnchor.constraint(equalTo: centerYAnchor),
            logoView.widthAnchor.constraint(equalToConstant: Self.logoSide),
            logoView.heightAnchor.constraint(equalToConstant: Self.logoSide),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Presentation

    /// Adds a splash over `window` that holds briefly, then fades away.
    static func present(over window: UIWindow) {
        let splash = LaunchSplashView(frame: window.bounds)
        splash.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        window.addSubview(splash)

        DispatchQueue.main.asyncAfter(deadline: .now() + holdDuration) {
            UIView.animate(
                withDuration: fadeDuration,
                delay: 0,
                options: [.curveEaseOut, .allowUserInteraction]
            ) {
                splash.alpha = 0
            } completion: { _ in
                splash.removeFromSuperview()
            }
        }
    }
}
