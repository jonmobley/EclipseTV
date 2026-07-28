//
//  WebRemoteViewController.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import UIKit
import WebKit

/// Phone-side Safari-like browser for a page presented on AirPlay.
///
/// The phone stages a 9:16 (Vertical) or 16:9 (Landscape) panel using the same
/// logical viewport as the AirPlay web view, so layout matches. TV output
/// settings live in the nav menu; scroll/navigation sync externally.
final class WebRemoteViewController: UIViewController {

    // MARK: - Properties

    let page: WebPage
    var webView: WKWebView?
    /// Full-bleed black host behind the aspect-fitted web panel.
    var webStageView: UIView?
    /// Aspect-fitted panel (9:16 or 16:9) that hosts the web view.
    var webPanelView: UIView?
    /// Suppresses scroll sync while applying programmatic Top changes.
    var isSyncingScroll = false

    // MARK: - Subviews

    private let airPlayBanner: UILabel = {
        let label = UILabel()
        label.text = "Connect AirPlay to show on TV"
        label.textColor = .white
        label.font = .systemFont(ofSize: 13, weight: .semibold)
        label.textAlignment = .center
        label.backgroundColor = UIColor.black.withAlphaComponent(0.55)
        label.layer.cornerRadius = 10
        label.layer.masksToBounds = true
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    // MARK: - Init

    /// Creates a presenting browser for the given saved page.
    init(page: WebPage) {
        self.page = page
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        title = page.title
        navigationItem.largeTitleDisplayMode = .never
        navigationItem.rightBarButtonItems = [
            UIBarButtonItem(
                image: UIImage(systemName: "ellipsis.circle"),
                menu: makeDisplayMenu()
            ),
            UIBarButtonItem(
                barButtonSystemItem: .refresh,
                target: self,
                action: #selector(reloadTapped)
            )
        ]

        setupPreviewWebView()
        view.addSubview(airPlayBanner)

        NSLayoutConstraint.activate([
            airPlayBanner.topAnchor.constraint(
                equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 8),
            airPlayBanner.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            airPlayBanner.leadingAnchor.constraint(
                greaterThanOrEqualTo: view.leadingAnchor, constant: 24),
            airPlayBanner.trailingAnchor.constraint(
                lessThanOrEqualTo: view.trailingAnchor, constant: -24),
            airPlayBanner.heightAnchor.constraint(equalToConstant: 32),
            airPlayBanner.widthAnchor.constraint(greaterThanOrEqualToConstant: 240)
        ])

        updateAirPlayBanner()
        observePresentationChanges()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        ExternalDisplayManager.shared.refreshConnection()
        updateAirPlayBanner()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        layoutPhoneWebViewport()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        if isMovingFromParent || isBeingDismissed,
           ExternalDisplayManager.shared.isWebLive {
            ExternalDisplayManager.shared.stopWebAndRestoreLibrary()
        }
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    // MARK: - Actions

    @objc func reloadTapped() {
        webView?.reload()
        ExternalDisplayManager.shared.reloadWeb()
    }

    @objc func topTapped() {
        guard let webView = webView else { return }
        isSyncingScroll = true
        webView.scrollView.setContentOffset(.zero, animated: true)
        ExternalDisplayManager.shared.scrollWebToTop()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in
            self?.isSyncingScroll = false
        }
    }

    @objc func stopTapped() {
        ExternalDisplayManager.shared.stopWebAndRestoreLibrary()
        navigationController?.popViewController(animated: true)
    }

    @objc func externalDisplayChanged() {
        updateAirPlayBanner()
    }

    @objc func webEndedExternally() {
        navigationController?.popViewController(animated: true)
    }

    @objc func outputSettingsChanged() {
        navigationItem.rightBarButtonItems = [
            UIBarButtonItem(
                image: UIImage(systemName: "ellipsis.circle"),
                menu: makeDisplayMenu()
            ),
            UIBarButtonItem(
                barButtonSystemItem: .refresh,
                target: self,
                action: #selector(reloadTapped)
            )
        ]
        // Relayout + reload so the site reflows to the shared viewport.
        layoutPhoneWebViewport()
        webView?.reload()
        ExternalDisplayManager.shared.reloadWeb()
    }

    // MARK: - Display Menu

    private func makeDisplayMenu() -> UIMenu {
        let textSize = UIMenu(
            title: "Text Size",
            options: .singleSelection,
            children: WebTextSize.allCases.map { size in
                UIAction(
                    title: size.rawValue,
                    state: ExternalOutputSettings.webTextSize == size ? .on : .off
                ) { _ in
                    ExternalOutputSettings.webTextSize = size
                }
            }
        )

        let orientation = UIMenu(
            title: "Display Mode",
            options: .singleSelection,
            children: ExternalOutputOrientation.allCases.map { value in
                UIAction(
                    title: value.rawValue,
                    state: ExternalOutputSettings.orientation == value ? .on : .off
                ) { _ in
                    ExternalOutputSettings.orientation = value
                }
            }
        )

        var children: [UIMenuElement] = [
            UIAction(title: "Scroll to Top",
                     image: UIImage(systemName: "arrow.up.to.line")) { [weak self] _ in
                self?.topTapped()
            },
            textSize,
            orientation
        ]

        if ExternalOutputSettings.orientation == .portrait {
            children.append(UIMenu(
                title: "TV Rotation",
                options: .singleSelection,
                children: ExternalRotationDirection.allCases.map { value in
                    UIAction(
                        title: value.rawValue,
                        state: ExternalOutputSettings.rotationDirection == value ? .on : .off
                    ) { _ in
                        ExternalOutputSettings.rotationDirection = value
                    }
                }
            ))
        }

        children.append(UIAction(
            title: "Stop Presenting",
            image: UIImage(systemName: "xmark.circle"),
            attributes: .destructive
        ) { [weak self] _ in
            self?.stopTapped()
        })

        return UIMenu(children: children)
    }

    // MARK: - UI State

    private func updateAirPlayBanner() {
        airPlayBanner.isHidden = ExternalDisplayManager.shared.isConnected
    }

    private func observePresentationChanges() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(externalDisplayChanged),
            name: ExternalDisplayManager.didChangeNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(webEndedExternally),
            name: ExternalDisplayManager.webDidEndNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(outputSettingsChanged),
            name: ExternalOutputSettings.didChangeNotification,
            object: nil
        )
    }
}
