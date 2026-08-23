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
/// Stages a 9:16 (Vertical) or 16:9 (Landscape) panel matching the AirPlay
/// viewport. Vertical chrome: Back · host title · ⋯ · Close. Landscape hides the
/// URL bar and puts Back / ⋯ / Close in a trailing column beside the 16:9 card.
final class WebRemoteViewController: UIViewController {

    // MARK: - Properties

    let page: WebPage
    var webView: WKWebView?
    /// Full-bleed host behind the aspect-fitted web panel.
    var webStageView: UIView?
    /// Aspect-fitted panel (9:16 or 16:9) that hosts the web view.
    var webPanelView: UIView?
    /// Suppresses scroll sync while applying programmatic scroll changes.
    var isSyncingScroll = false
    /// True once the browser is on its way out, so the orientation is restored after the
    /// dismissal rather than while this screen still owns it.
    private var isLeaving = false

    var backButton: UIBarButtonItem!
    var bookmarksButton: UIBarButtonItem!
    var closeButton: UIBarButtonItem!
    /// Landscape overlay Back — the nav bar (and URL title) is hidden.
    var overlayBackButton: UIButton!
    /// Landscape overlay Close.
    var overlayCloseButton: UIButton!
    /// Landscape overlay ⋯ (Refresh / New / saved).
    var overlayBookmarksButton: UIButton!
    /// Vertical: stage sits under the URL nav bar.
    var verticalStageTopConstraint: NSLayoutConstraint?
    /// Landscape: stage is full-bleed so the 16:9 card can fill the height.
    var landscapeStageTopConstraint: NSLayoutConstraint?

    /// Landscape Display Mode overlays chrome; Vertical keeps the URL nav bar.
    var usesOverlayBrowserChrome: Bool {
        !ExternalOutputSettings.isVerticalMode
    }

    /// Opening-load history depth; recaptured until the user navigates.
    var sessionBackRoot = BrowserSessionBackRoot()

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
        view.backgroundColor = .black
        navigationItem.largeTitleDisplayMode = .never
        setupBrowserChrome()
        setupPreviewWebView()
        observePresentationChanges()
        applyBrowserChromeMode()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        requestDisplayModeSceneGeometry()
        applyBrowserChromeMode(animated: animated)
        ExternalDisplayManager.shared.refreshConnection()
        refreshBookmarksMenu()
    }

    /// Landscape Display Mode → landscape browser; Vertical → portrait.
    ///
    /// The card is the AirPlay viewport, so in Landscape the user turns the phone and
    /// reads, scrolls, and taps the same 16:9 frame the TV is showing.
    override var supportedInterfaceOrientations: UIInterfaceOrientationMask {
        ExternalOutputSettings.phoneOrientationMask
    }

    override var preferredInterfaceOrientationForPresentation: UIInterfaceOrientation {
        ExternalOutputSettings.preferredPhoneOrientation
    }

    override var shouldAutorotate: Bool { true }

    override func viewWillTransition(
        to size: CGSize,
        with coordinator: UIViewControllerTransitionCoordinator
    ) {
        super.viewWillTransition(to: size, with: coordinator)
        coordinator.animate(alongsideTransition: { [weak self] _ in
            self?.layoutPhoneWebViewport()
        }, completion: { [weak self] _ in
            self?.resyncExternalWeb()
        })
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        if usesOverlayBrowserChrome {
            navigationController?.setNavigationBarHidden(false, animated: animated)
        }
        guard isBeingDismissed || isMovingFromParent else { return }
        isLeaving = true
        // Park the warm session (home LiveHeader reclaims it if still live).
        WarmWebSessionPool.shared.relinquish(pageId: page.id, from: self)
        webView = nil
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        guard isLeaving else { return }
        // Landscape Display Mode turned the phone for this screen; put it back upright
        // so the grid behind it isn't left sideways.
        restoreUprightSceneGeometry()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        layoutPhoneWebViewport()
    }

    // Closing the phone browser does not stop AirPlay — the site stays live.

    /// Whether `url` is an empty / about: page (not a real site yet).
    func isBlankBrowserURL(_ url: URL) -> Bool {
        url.absoluteString == "about:blank" || url.scheme == "about"
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    // MARK: - Actions

    @objc func closeTapped() {
        if let nav = navigationController, nav.viewControllers.count > 1 {
            nav.popViewController(animated: true)
        } else {
            dismiss(animated: true)
        }
    }

    @objc func goBackTapped() {
        guard let webView else { return }
        guard sessionBackRoot.shouldGoBack(
            backListCount: webView.backForwardList.backList.count
        ) else { return }
        webView.goBack()
    }

    /// Snapshots back-list depth while the opening load (and its redirects) settle.
    func captureBrowserSessionRootIfNeeded() {
        guard let webView, let url = webView.url, !isBlankBrowserURL(url) else { return }
        sessionBackRoot.captureOpeningLoad(
            backListCount: webView.backForwardList.backList.count
        )
        updateBrowserChrome()
    }

    @objc func reloadTapped() {
        webView?.reload()
        ExternalDisplayManager.shared.reloadWeb()
    }

    @objc func webEndedExternally() {
        closeTapped()
    }

    @objc func outputSettingsChanged() {
        requestDisplayModeSceneGeometry()
        applyBrowserChromeMode()
        layoutPhoneWebViewport()
        webView?.reload()
        ExternalDisplayManager.shared.reloadWeb()
    }

    @objc func bookmarksStoreChanged() {
        refreshBookmarksMenu()
    }

    // MARK: - Observers

    private func observePresentationChanges() {
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
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(bookmarksStoreChanged),
            name: WebPageStore.didChangeNotification,
            object: nil
        )
    }
}
