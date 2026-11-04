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
/// viewport. Vertical chrome: Back · host title · Refresh · ⊕ · ⋯ · Close in the nav
/// bar. Landscape hides the URL bar and puts the same buttons in a column beside the
/// 16:9 card (a row beneath it on an upright iPad). Every website of the open Show is
/// a tab in a strip above the card; the TV follows the active tab, except windows a
/// site opened, which stay on the phone until sent over.
final class WebRemoteViewController: UIViewController {

    // MARK: - Properties

    /// Website the browser opened on. Session tabs keep its Show tile live.
    let initialPage: WebPage
    /// Open tabs: the Show's websites, plus ⊕ tabs and windows sites opened.
    var tabs: BrowserTabList
    var activeTab: BrowserTab { tabs.active }
    /// Web view of the active tab while it is on the stage.
    var webView: WKWebView?
    /// Full-bleed host behind the aspect-fitted web panel.
    var webStageView: UIView?
    /// Aspect-fitted panel (9:16 or 16:9) that hosts the web view.
    var webPanelView: UIView?
    /// Suppresses scroll sync while applying programmatic scroll changes.
    var isSyncingScroll = false
    /// Follows same-document URL changes (pushState / hash routing) onto AirPlay.
    var webURLObservation: NSKeyValueObservation?
    /// True once the browser is on its way out, so the orientation is restored after the
    /// dismissal rather than while this screen still owns it.
    private var isLeaving = false
    /// True once the browser is on screen and holds the phone to the Display Mode
    /// orientation. Before that (and while closing) it accepts the phone as it is,
    /// so the grid behind it is never asked to lay out for a turn it would show.
    var holdsDisplayModeOrientation = false
    /// Set while Close waits for the phone to turn upright before dismissing.
    var isClosingAfterTurn = false
    private var didFinishClose = false

    var backButton: UIBarButtonItem!
    var refreshBarButton: UIBarButtonItem!
    var newTabBarButton: UIBarButtonItem!
    /// Shown only while the active tab is phone-only.
    var sendToTVBarButton: UIBarButtonItem!
    var bookmarksButton: UIBarButtonItem!
    var closeButton: UIBarButtonItem!
    /// Starts / stops the page scrolling by itself; long-press picks the speed.
    var autoScrollBarButton: UIBarButtonItem!
    /// Landscape overlay Auto Scroll.
    var overlayAutoScrollButton: UIButton!
    /// Page tap that pauses / resumes Auto Scroll; enabled only while it is on.
    var autoScrollTap: UITapGestureRecognizer?
    /// Floating speed slider over the page while Auto Scroll is on.
    var autoScrollSpeedBar: ScrollSpeedSlider?
    /// Drives the active tab's page down at the chosen speed.
    lazy var autoScroller: WebAutoScroller = {
        let scroller = WebAutoScroller(scrollView: { [weak self] in self?.webView?.scrollView })
        scroller.onChange = { [weak self] in self?.updateAutoScrollChrome() }
        return scroller
    }()
    /// Landscape overlay Back — shown only once there is history to go back to.
    var overlayBackButton: UIButton!
    var overlayRefreshButton: UIButton!
    var overlayNewTabButton: UIButton!
    /// Landscape overlay Send to TV, for a phone-only tab.
    var overlaySendToTVButton: UIButton!
    /// Landscape overlay Close.
    var overlayCloseButton: UIButton!
    /// Landscape overlay ⋯ (saved websites).
    var overlayBookmarksButton: UIButton!
    /// Tab chips above the card; hidden while there is a single tab.
    var tabStripView: BrowserTabStripView!
    /// Vertical: stage sits under the URL nav bar.
    var verticalStageTopConstraint: NSLayoutConstraint?
    /// Landscape: stage is full-bleed so the 16:9 card can fill the height.
    var landscapeStageTopConstraint: NSLayoutConstraint?

    /// Landscape Display Mode overlays chrome; Vertical keeps the URL nav bar.
    var usesOverlayBrowserChrome: Bool {
        !ExternalOutputSettings.isVerticalMode
    }

    /// Opening-load history depth of the active tab; recaptured until the user navigates.
    var sessionBackRoot: BrowserSessionBackRoot {
        get { activeTab.backRoot }
        set { activeTab.backRoot = newValue }
    }

    // MARK: - Init

    /// Creates a presenting browser for `page`, with a tab for every website of the Show.
    /// - Parameter showPages: The open Show's websites in Show order (may omit `page`).
    init(page: WebPage, showPages: [WebPage] = []) {
        initialPage = page
        tabs = BrowserTabList(pages: showPages, active: page)
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
        applyBrowserChromeMode(animated: animated)
        ExternalDisplayManager.shared.refreshConnection()
        refreshBookmarksMenu()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        // Turn only now that this screen covers the grid; turning during the
        // presentation re-laid the grid out sideways on a still-upright screen.
        guard !isClosingAfterTurn else { return }
        holdsDisplayModeOrientation = true
        requestDisplayModeSceneGeometry()
    }

    /// Landscape Display Mode → landscape browser; Vertical → portrait.
    ///
    /// The card is the AirPlay viewport, so in Landscape the user turns the phone and
    /// reads, scrolls, and taps the same 16:9 frame the TV is showing.
    override var supportedInterfaceOrientations: UIInterfaceOrientationMask {
        holdsDisplayModeOrientation
            ? ExternalOutputSettings.phoneOrientationMask
            : .allButUpsideDown
    }

    override var preferredInterfaceOrientationForPresentation: UIInterfaceOrientation {
        guard !holdsDisplayModeOrientation else {
            return ExternalOutputSettings.preferredPhoneOrientation
        }
        // Open in whatever way the phone is held; viewDidAppear turns it.
        let current = view.phoneInterfaceOrientation
        return current == .portraitUpsideDown ? .portrait : current
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
            guard let self else { return }
            if self.isClosingAfterTurn {
                self.finishClose()
                return
            }
            self.resyncExternalWeb()
        })
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        // Leaving with the whole stack: keep the bar hidden, or the vertical
        // Back / ⋯ / Close bar shows on the black cover while it slides away.
        if usesOverlayBrowserChrome, navigationController?.isBeingDismissed != true {
            navigationController?.setNavigationBarHidden(false, animated: animated)
        }
        guard isBeingDismissed || isMovingFromParent else { return }
        isLeaving = true
        autoScroller.stop()
        webURLObservation = nil
        // Park the warm sessions (home LiveHeader reclaims the live one).
        relinquishAllTabs()
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
        layoutAutoScrollSpeedBar()
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
        guard !isClosingAfterTurn else { return }
        let isPushed = (navigationController?.viewControllers.count ?? 0) > 1
        // A turned phone stands upright first, behind the black cover, so the grid
        // is uncovered already upright instead of sideways and then turning.
        if !isPushed,
           traitCollection.userInterfaceIdiom == .phone,
           view.bounds.width > view.bounds.height {
            isClosingAfterTurn = true
            holdsDisplayModeOrientation = false
            setNeedsUpdateOfSupportedInterfaceOrientations()
            restoreUprightSceneGeometry()
            // Fallback when the scene does not turn (e.g. iOS declines the request).
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in
                self?.finishClose()
            }
            return
        }
        finishClose()
    }

    /// Pops or dismisses the browser; runs once even when called twice.
    private func finishClose() {
        guard !didFinishClose else { return }
        didFinishClose = true
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
        if mirrorsActiveTab {
            ExternalDisplayManager.shared.reloadWeb()
        }
    }

    @objc func newTabTapped() {
        presentNewURLAlert()
    }

    @objc func sendToTVTapped() {
        sendActiveTabToTV()
    }

    @objc func webEndedExternally() {
        closeTapped()
    }

    @objc func outputSettingsChanged() {
        requestDisplayModeSceneGeometry()
        applyBrowserChromeMode()
        layoutPhoneWebViewport()
        webView?.reload()
        if mirrorsActiveTab {
            ExternalDisplayManager.shared.reloadWeb()
        }
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
