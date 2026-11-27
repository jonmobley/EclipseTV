//
//  HomeHeaderBar.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import UIKit

/// Top header for the home screen.
///
/// Compact: page dropdown · + New Show (Home) or Lock / Blackout / Settings / +
/// (Show). Regular-width and -height iPad replaces the dropdown with Home, Show,
/// and Library tabs; Home tab returns from Show, so the back chevron is
/// hidden. Compact Split View and iPhone keep the dropdown.
/// iCloud Sync status surfaces via `EclipseSyncStatusBanner`, not the header.
final class HomeHeaderBar: UIView {

    // MARK: - Subviews

    private let backButton = MinimumHitTargetButton(type: .system)
    private let leadingNavStack = UIStackView()
    private let menuPill = UIView()
    private let libraryButton = MinimumHitTargetButton(type: .system)
    private let navTabs = HomeHeaderNavTabs()
    /// The 52pt row of controls. The text tabs sit under it on an upright phone.
    private let rowGuide = UILayoutGuide()
    /// Home · Library · Show · Music, when the home screen pages (compact width).
    let tabStrip = HomeTabStripView()
    /// Fills the status-bar area above the bar so nothing scrolls through it.
    private let topBackdrop = UIView()
    private let searchButton = MinimumHitTargetButton(type: .system)
    /// The search field and Cancel, under the tabs while a page is being searched.
    private let searchRow = UIView()
    let searchField = UISearchTextField()
    private let cancelSearchButton = UIButton(type: .system)
    private let addMusicButton = MinimumHitTargetButton(type: .system)
    /// Library page "+": imports photos, videos and PDFs into the Library only.
    private let addLibraryButton = MinimumHitTargetButton(type: .system)
    private let trailingStack = UIStackView()
    private let lockButton = MinimumHitTargetButton(type: .system)
    private let freezeButton = MinimumHitTargetButton(type: .system)
    private let blackButton = MinimumHitTargetButton(type: .system)
    private let settingsButton = MinimumHitTargetButton(type: .system)
    private let addButton = MinimumHitTargetButton(type: .system)
    private let newShowButton = MinimumHitTargetButton(type: .system)
    private let doneButton = ArrangeDoneButton()
    private let selectActionsButton = MinimumHitTargetButton(type: .system)

    /// Invoked when the Settings control is tapped.
    var onOpenSettings: (() -> Void)?
    /// Invoked when Show-mode back returns to Home.
    var onGoBack: (() -> Void)?
    /// Invoked when the live-output Lock control is tapped.
    var onToggleLiveLock: (() -> Void)?
    /// Invoked when the Blackout control is tapped.
    var onPresentBlack: (() -> Void)?
    /// Header snowflake: hold the audience screen still.
    var onToggleFreeze: (() -> Void)?
    /// Blackout's long-press menu: Black or White.
    var onSelectBlankKind: ((OutputBlankKind) -> Void)?
    /// Invoked when New Show is tapped on Home.
    var onNewShow: (() -> Void)?
    /// Invoked when Done is tapped while arranging tiles.
    var onDoneArranging: (() -> Void)?
    /// Invoked when Done is tapped while multi-selecting tiles.
    var onDoneSelecting: (() -> Void)?
    /// Invoked by an iPad destination tab (Home, Show, Library, Music).
    var onSelectDestination: ((HomeHeaderDestination) -> Void)?
    /// Invoked when a text tab is tapped (compact width).
    var onSelectTab: ((HomeTab) -> Void)?
    /// Invoked by "Camera" on the tab row.
    /// Arranging, selecting or searching started or stopped (the Camera button
    /// steps aside meanwhile).
    var onOverlayStateChange: (() -> Void)?
    /// Invoked by the Search control (Library, Show and Music pages).
    var onBeginSearch: (() -> Void)?
    /// Invoked as the search text changes.
    var onSearchTextChanged: ((String) -> Void)?
    /// Invoked by Cancel beside the search field.
    var onCancelSearch: (() -> Void)?
    /// Invoked by the Music page's "+" control.
    var onAddMusic: (() -> Void)?

    /// Height of the row of controls, without the text tabs.
    static let rowHeight: CGFloat = 52

    /// Bar height: the row alone, or the row plus the text tabs under it. In phone
    /// landscape the tabs sit inside the row, where height is short and width is not.
    /// Searching never changes it: the search field takes the tabs' place.
    static func height(
        showsTabStrip: Bool,
        verticalSizeClass: UIUserInterfaceSizeClass
    ) -> CGFloat {
        guard showsTabStrip else { return rowHeight }
        let tabs = verticalSizeClass == .compact ? 0 : HomeTabStripView.height
        return rowHeight + tabs
    }

    /// EclipseTV Multipeer link — read by output-status chrome.
    private(set) var connectionState: ConnectionDisplayState = .paused
    /// External/AirPlay display available — read by output-status chrome.
    private(set) var isAirPlayConnected = false
    private var isLiveLocked = false
    private var isBlackLive = false
    private var isFrozen = false
    private var blankKind = OutputBlankKind.current
    private var showsShowChrome = false
    private var isArranging = false
    private var isSelecting = false
    /// Tiles are being arranged or selected.
    var isEditingTiles: Bool { isArranging || isSelecting }
    /// Page the pager is on; picks the trailing controls when the tabs show.
    private var tabPage: HomeTab = .home
    /// False while Music is inside a playlist, which has its own "+".
    private var musicAddAvailable = true
    /// True while the search field is showing.
    private(set) var isSearching = false
    /// The tab row (search icon + text tabs, or the search field in their place)
    /// under the controls (upright) or inside that row (phone landscape).
    private var tabStripBelowConstraints: [NSLayoutConstraint] = []
    private var tabStripInlineConstraints: [NSLayoutConstraint] = []
    private var menuPillLeadingToBack: NSLayoutConstraint?
    private var menuPillLeadingToSafe: NSLayoutConstraint?

    // MARK: - Init

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupViews()
        setConnectionState(.paused)
        applyTrailingChrome()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Setup

    private func setupViews() {
        addLayoutGuide(rowGuide)
        topBackdrop.backgroundColor = .systemBackground
        topBackdrop.isUserInteractionEnabled = false
        topBackdrop.isHidden = true
        topBackdrop.translatesAutoresizingMaskIntoConstraints = false
        addSubview(topBackdrop)

        let symbol = UIImage.SymbolConfiguration(pointSize: 17, weight: .semibold)
        backButton.configuration = Self.barIconConfig(
            systemName: "chevron.left",
            symbolConfig: symbol
        )
        backButton.accessibilityLabel = "Back"
        backButton.accessibilityHint = "Returns to Home"
        backButton.isHidden = true
        backButton.addTarget(self, action: #selector(backTapped), for: .touchUpInside)
        backButton.translatesAutoresizingMaskIntoConstraints = false
        addSubview(backButton)

        menuPill.backgroundColor = .clear
        menuPill.layer.cornerRadius = 18
        menuPill.layer.cornerCurve = .continuous
        menuPill.layer.borderWidth = 1
        menuPill.layer.borderColor = UIColor.separator.cgColor
        menuPill.translatesAutoresizingMaskIntoConstraints = false
        navTabs.translatesAutoresizingMaskIntoConstraints = false
        navTabs.onSelect = { [weak self] destination in
            self?.onSelectDestination?(destination)
        }
        leadingNavStack.axis = .horizontal
        leadingNavStack.alignment = .center
        leadingNavStack.spacing = 0
        leadingNavStack.translatesAutoresizingMaskIntoConstraints = false
        leadingNavStack.addArrangedSubview(menuPill)
        leadingNavStack.addArrangedSubview(navTabs)
        addSubview(leadingNavStack)
        registerForTraitChanges([UITraitUserInterfaceStyle.self]) {
            (view: Self, _: UITraitCollection) in
            view.menuPill.layer.borderColor = UIColor.separator.cgColor
            view.applyLockButtonAppearance()
            view.applyBlackButtonAppearance()
            view.applyNewShowButtonAppearance()
        }
        registerForTraitChanges([
            UITraitHorizontalSizeClass.self,
            UITraitVerticalSizeClass.self
        ]) { (view: Self, _: UITraitCollection) in
            view.applySizeClassChrome()
        }

        var libraryConfig = UIButton.Configuration.plain()
        libraryConfig.title = "Home"
        libraryConfig.image = UIImage(
            systemName: "chevron.down",
            withConfiguration: UIImage.SymbolConfiguration(pointSize: 10, weight: .semibold)
        )
        libraryConfig.imagePlacement = .trailing
        libraryConfig.imagePadding = 4
        libraryConfig.baseForegroundColor = .label
        libraryConfig.contentInsets = NSDirectionalEdgeInsets(
            top: 6, leading: 12, bottom: 6, trailing: 10
        )
        libraryConfig.titleLineBreakMode = .byTruncatingTail
        libraryConfig.titleTextAttributesTransformer =
            UIConfigurationTextAttributesTransformer { incoming in
                var outgoing = incoming
                outgoing.font = .systemFont(ofSize: 17, weight: .semibold)
                return outgoing
            }
        libraryButton.configuration = libraryConfig
        libraryButton.showsMenuAsPrimaryAction = true
        libraryButton.accessibilityLabel = "Home menu"
        libraryButton.accessibilityHint =
            "Open Show, New Show, Camera Mode, Settings, and Recent Shows"
        libraryButton.translatesAutoresizingMaskIntoConstraints = false
        libraryButton.setContentCompressionResistancePriority(
            .defaultLow, for: .horizontal
        )
        leadingNavStack.setContentCompressionResistancePriority(
            .defaultLow, for: .horizontal
        )
        navTabs.setContentCompressionResistancePriority(
            .defaultLow, for: .horizontal
        )
        menuPill.addSubview(libraryButton)

        lockButton.translatesAutoresizingMaskIntoConstraints = false
        lockButton.accessibilityLabel = "Lock live output"
        lockButton.accessibilityHint =
            "When on, the current live output stays fixed; media, Screensaver, and Background open in Preview"
        lockButton.addTarget(self, action: #selector(lockTapped), for: .touchUpInside)
        applyLockButtonAppearance()

        blackButton.translatesAutoresizingMaskIntoConstraints = false
        blackButton.accessibilityHint =
            "Toggles a black or white screen on the live output — AirPlay, EclipseTV, "
            + "or the preview on this iPhone. Touch and hold to choose Black or White."
        blackButton.addTarget(self, action: #selector(blackTapped), for: .touchUpInside)
        // Long press picks Black or White; a tap still toggles Blackout.
        blackButton.showsMenuAsPrimaryAction = false
        applyBlackButtonAppearance()

        freezeButton.translatesAutoresizingMaskIntoConstraints = false
        freezeButton.accessibilityLabel = "Freeze"
        freezeButton.accessibilityHint =
            "Holds the audience screen still; media, Screensaver, and Background open in Preview"
        freezeButton.addTarget(self, action: #selector(freezeTapped), for: .touchUpInside)
        applyFreezeButtonAppearance()

        // Plain SF Symbols, like UIBarButtonItem — not icons in stroked circles.
        let symbolConfig = UIImage.SymbolConfiguration(pointSize: 20, weight: .regular)
        settingsButton.configuration = Self.barIconConfig(
            systemName: "gearshape.fill",
            symbolConfig: symbolConfig
        )
        settingsButton.translatesAutoresizingMaskIntoConstraints = false
        settingsButton.accessibilityLabel = "Settings"
        settingsButton.accessibilityHint = "Open Settings; edit the open Show there"
        settingsButton.addTarget(self, action: #selector(settingsTapped), for: .touchUpInside)

        addButton.configuration = Self.barIconConfig(
            systemName: "plus",
            symbolConfig: symbolConfig,
            foreground: .accent
        )
        addButton.translatesAutoresizingMaskIntoConstraints = false
        addButton.accessibilityLabel = "Add"
        addButton.showsMenuAsPrimaryAction = true

        searchButton.configuration = Self.barIconConfig(
            systemName: "magnifyingglass",
            symbolConfig: symbolConfig
        )
        searchButton.translatesAutoresizingMaskIntoConstraints = false
        searchButton.accessibilityLabel = "Search"
        searchButton.accessibilityHint = "Searches this page by name"
        searchButton.accessibilityIdentifier = "home.search.button"
        searchButton.isHidden = true
        // First on the tab row, left of Home (owner's call 2026-11-26).
        addSubview(searchButton)
        searchButton.addAction(UIAction { [weak self] _ in
            self?.onBeginSearch?()
        }, for: .touchUpInside)

        searchRow.isHidden = true
        searchRow.translatesAutoresizingMaskIntoConstraints = false
        addSubview(searchRow)
        searchField.translatesAutoresizingMaskIntoConstraints = false
        searchField.autocapitalizationType = .none
        searchField.autocorrectionType = .no
        searchField.returnKeyType = .search
        searchField.accessibilityIdentifier = "home.search.field"
        searchField.addAction(UIAction { [weak self] _ in
            guard let self else { return }
            self.onSearchTextChanged?(self.searchField.text ?? "")
        }, for: .editingChanged)
        // Return keeps the results and puts the keyboard away.
        searchField.addAction(UIAction { [weak self] _ in
            self?.searchField.resignFirstResponder()
        }, for: .editingDidEndOnExit)
        searchRow.addSubview(searchField)
        cancelSearchButton.setTitle("Cancel", for: .normal)
        cancelSearchButton.titleLabel?.font = .systemFont(ofSize: 16, weight: .regular)
        cancelSearchButton.translatesAutoresizingMaskIntoConstraints = false
        cancelSearchButton.setContentCompressionResistancePriority(.required, for: .horizontal)
        cancelSearchButton.setContentHuggingPriority(.required, for: .horizontal)
        cancelSearchButton.accessibilityLabel = "Cancel search"
        cancelSearchButton.addAction(UIAction { [weak self] _ in
            self?.onCancelSearch?()
        }, for: .touchUpInside)
        searchRow.addSubview(cancelSearchButton)

        addMusicButton.configuration = Self.barIconConfig(
            systemName: "plus",
            symbolConfig: symbolConfig,
            foreground: .accent
        )
        addMusicButton.translatesAutoresizingMaskIntoConstraints = false
        addMusicButton.accessibilityLabel = "Add Music"
        addMusicButton.accessibilityHint = "Adds music or makes a playlist"
        addMusicButton.isHidden = true
        addMusicButton.addAction(UIAction { [weak self] _ in
            self?.onAddMusic?()
        }, for: .touchUpInside)

        addLibraryButton.configuration = Self.barIconConfig(
            systemName: "plus",
            symbolConfig: symbolConfig,
            foreground: .accent
        )
        addLibraryButton.translatesAutoresizingMaskIntoConstraints = false
        addLibraryButton.accessibilityLabel = "Add to Library"
        addLibraryButton.accessibilityHint = "Adds photos, videos or PDFs to the Library"
        addLibraryButton.accessibilityIdentifier = "home.library.add"
        addLibraryButton.showsMenuAsPrimaryAction = true
        addLibraryButton.isHidden = true

        tabStrip.translatesAutoresizingMaskIntoConstraints = false
        tabStrip.isHidden = true
        tabStrip.onSelect = { [weak self] tab in
            self?.onSelectTab?(tab)
        }
        addSubview(tabStrip)

        newShowButton.translatesAutoresizingMaskIntoConstraints = false
        newShowButton.accessibilityLabel = "New Show"
        newShowButton.addTarget(self, action: #selector(newShowTapped), for: .touchUpInside)
        applyNewShowButtonAppearance()

        doneButton.isHidden = true
        doneButton.translatesAutoresizingMaskIntoConstraints = false
        doneButton.onTap = { [weak self] in
            guard let self else { return }
            if self.isSelecting {
                self.onDoneSelecting?()
            } else {
                self.onDoneArranging?()
            }
        }

        var selectConfig = UIButton.Configuration.filled()
        selectConfig.title = "Actions"
        selectConfig.baseBackgroundColor = .secondarySystemBackground
        selectConfig.baseForegroundColor = .label
        selectConfig.background.cornerRadius = 18
        selectConfig.contentInsets = NSDirectionalEdgeInsets(
            top: 7, leading: 14, bottom: 7, trailing: 14
        )
        selectConfig.titleTextAttributesTransformer =
            UIConfigurationTextAttributesTransformer { incoming in
                var outgoing = incoming
                outgoing.font = .systemFont(ofSize: 16, weight: .semibold)
                return outgoing
            }
        selectActionsButton.configuration = selectConfig
        selectActionsButton.showsMenuAsPrimaryAction = true
        selectActionsButton.isHidden = true
        selectActionsButton.translatesAutoresizingMaskIntoConstraints = false
        selectActionsButton.accessibilityLabel = "Selection actions"

        trailingStack.axis = .horizontal
        trailingStack.alignment = .center
        trailingStack.spacing = 6
        trailingStack.translatesAutoresizingMaskIntoConstraints = false
        // Search is on the tab row; Camera is the round button bottom-left.
        for button in [
            lockButton, freezeButton, blackButton, settingsButton,
            addButton, addMusicButton, addLibraryButton,
            newShowButton, selectActionsButton, doneButton
        ] {
            trailingStack.addArrangedSubview(button)
        }
        addSubview(trailingStack)

        let leadingSafe = leadingNavStack.leadingAnchor.constraint(
            equalTo: leadingAnchor, constant: 16
        )
        let leadingBack = leadingNavStack.leadingAnchor.constraint(
            equalTo: backButton.trailingAnchor, constant: 4
        )
        leadingBack.isActive = false
        menuPillLeadingToSafe = leadingSafe
        menuPillLeadingToBack = leadingBack

        // Search icon, then the tabs. The search field, while up, covers the same
        // span, so the bar never grows.
        let searchToTabs = tabStrip.leadingAnchor.constraint(
            equalTo: searchButton.trailingAnchor, constant: 8
        )
        tabStripBelowConstraints = [
            tabStrip.topAnchor.constraint(equalTo: rowGuide.bottomAnchor),
            searchButton.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            searchButton.centerYAnchor.constraint(equalTo: tabStrip.centerYAnchor),
            searchToTabs,
            tabStrip.trailingAnchor.constraint(
                lessThanOrEqualTo: trailingAnchor, constant: -12
            ),
            searchRow.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            searchRow.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            searchRow.centerYAnchor.constraint(equalTo: tabStrip.centerYAnchor)
        ]
        tabStripInlineConstraints = [
            tabStrip.centerYAnchor.constraint(equalTo: rowGuide.centerYAnchor),
            searchButton.leadingAnchor.constraint(
                equalTo: leadingNavStack.trailingAnchor, constant: 8
            ),
            searchButton.centerYAnchor.constraint(equalTo: rowGuide.centerYAnchor),
            tabStrip.leadingAnchor.constraint(
                equalTo: searchButton.trailingAnchor, constant: 8
            ),
            tabStrip.trailingAnchor.constraint(
                lessThanOrEqualTo: trailingStack.leadingAnchor, constant: -8
            ),
            searchRow.leadingAnchor.constraint(
                equalTo: leadingNavStack.trailingAnchor, constant: 16
            ),
            searchRow.trailingAnchor.constraint(
                equalTo: trailingStack.leadingAnchor, constant: -8
            ),
            searchRow.centerYAnchor.constraint(equalTo: rowGuide.centerYAnchor)
        ]
        tabStrip.setContentCompressionResistancePriority(.required, for: .horizontal)

        NSLayoutConstraint.activate([
            rowGuide.topAnchor.constraint(equalTo: topAnchor),
            rowGuide.leadingAnchor.constraint(equalTo: leadingAnchor),
            rowGuide.trailingAnchor.constraint(equalTo: trailingAnchor),
            rowGuide.heightAnchor.constraint(equalToConstant: Self.rowHeight),

            // Up through the status bar and out to the screen edges (the bar itself
            // stops at the safe area in landscape).
            topBackdrop.bottomAnchor.constraint(equalTo: bottomAnchor),
            topBackdrop.heightAnchor.constraint(equalToConstant: 400),
            topBackdrop.leadingAnchor.constraint(equalTo: leadingAnchor, constant: -120),
            topBackdrop.trailingAnchor.constraint(equalTo: trailingAnchor, constant: 120),

            searchButton.widthAnchor.constraint(equalToConstant: 36),
            searchButton.heightAnchor.constraint(equalToConstant: 36),

            searchRow.heightAnchor.constraint(equalToConstant: 36),
            searchField.leadingAnchor.constraint(equalTo: searchRow.leadingAnchor),
            searchField.topAnchor.constraint(equalTo: searchRow.topAnchor),
            searchField.bottomAnchor.constraint(equalTo: searchRow.bottomAnchor),
            cancelSearchButton.leadingAnchor.constraint(
                equalTo: searchField.trailingAnchor, constant: 10
            ),
            cancelSearchButton.trailingAnchor.constraint(equalTo: searchRow.trailingAnchor),
            cancelSearchButton.centerYAnchor.constraint(equalTo: searchRow.centerYAnchor),
            addMusicButton.widthAnchor.constraint(equalToConstant: 36),
            addMusicButton.heightAnchor.constraint(equalToConstant: 36),
            // Without a set size this menu button grew past its icon and sat the
            // "+" in from the right edge on the Library page.
            addLibraryButton.widthAnchor.constraint(equalToConstant: 36),
            addLibraryButton.heightAnchor.constraint(equalToConstant: 36),

            backButton.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            backButton.centerYAnchor.constraint(equalTo: rowGuide.centerYAnchor),
            backButton.widthAnchor.constraint(equalToConstant: 36),
            backButton.heightAnchor.constraint(equalToConstant: 36),

            leadingSafe,
            leadingNavStack.centerYAnchor.constraint(equalTo: rowGuide.centerYAnchor),
            leadingNavStack.heightAnchor.constraint(equalToConstant: 44),

            menuPill.heightAnchor.constraint(equalToConstant: 36),

            libraryButton.leadingAnchor.constraint(equalTo: menuPill.leadingAnchor),
            libraryButton.trailingAnchor.constraint(equalTo: menuPill.trailingAnchor),
            libraryButton.topAnchor.constraint(equalTo: menuPill.topAnchor),
            libraryButton.bottomAnchor.constraint(equalTo: menuPill.bottomAnchor),

            trailingStack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            trailingStack.centerYAnchor.constraint(equalTo: rowGuide.centerYAnchor),

            addButton.widthAnchor.constraint(equalToConstant: 36),
            addButton.heightAnchor.constraint(equalToConstant: 36),
            settingsButton.widthAnchor.constraint(equalToConstant: 36),
            settingsButton.heightAnchor.constraint(equalToConstant: 36),
            lockButton.widthAnchor.constraint(equalToConstant: 36),
            lockButton.heightAnchor.constraint(equalToConstant: 36),
            freezeButton.widthAnchor.constraint(equalToConstant: 36),
            freezeButton.heightAnchor.constraint(equalToConstant: 36),
            blackButton.widthAnchor.constraint(equalToConstant: 36),
            blackButton.heightAnchor.constraint(equalToConstant: 36),
            newShowButton.heightAnchor.constraint(equalToConstant: 36),
            selectActionsButton.heightAnchor.constraint(equalToConstant: 36),
            doneButton.heightAnchor.constraint(equalToConstant: 36),

            leadingNavStack.trailingAnchor.constraint(
                lessThanOrEqualTo: trailingStack.leadingAnchor, constant: -8
            )
        ])
        for button in [
            backButton, lockButton, freezeButton, blackButton, settingsButton,
            addButton, addMusicButton, addLibraryButton, newShowButton
        ] {
            button.setContentCompressionResistancePriority(.required, for: .horizontal)
        }
        backButton.setContentHuggingPriority(.required, for: .horizontal)
        lockButton.setContentHuggingPriority(.required, for: .horizontal)
        freezeButton.setContentHuggingPriority(.required, for: .horizontal)
        blackButton.setContentHuggingPriority(.required, for: .horizontal)
        applySizeClassChrome()
    }

    /// Toolbar-style icon button (plain SF Symbol, no stroked circle chrome).
    static func barIconConfig(
        systemName: String,
        symbolConfig: UIImage.SymbolConfiguration,
        foreground: UIColor = .label
    ) -> UIButton.Configuration {
        var config = UIButton.Configuration.plain()
        config.image = UIImage(systemName: systemName, withConfiguration: symbolConfig)
        config.baseForegroundColor = foreground
        config.contentInsets = NSDirectionalEdgeInsets(
            top: 6, leading: 6, bottom: 6, trailing: 6
        )
        return config
    }

    // MARK: - Menus

    /// Sets the dropdown title (`"Home"` on Home, show name in Show mode).
    /// - Parameter subtitle: Optional second line (e.g. "Live on iPad").
    func setCenterTitle(_ title: String, subtitle: String? = nil) {
        guard var config = libraryButton.configuration else { return }
        config.title = title
        config.subtitle = subtitle
        config.titleLineBreakMode = .byTruncatingTail
        config.subtitleLineBreakMode = .byTruncatingTail
        libraryButton.configuration = config
        if let subtitle {
            libraryButton.accessibilityLabel = "\(title) menu, \(subtitle)"
        } else {
            libraryButton.accessibilityLabel = "\(title) menu"
        }
    }

    /// Attaches the page dropdown (Home, Open Show, New Show, Library, Music, Recents).
    func setLibraryMenu(_ menu: UIMenu) {
        libraryButton.menu = menu
    }

    /// Updates iPad destination-tab selection (Home vs Show, Music pin).
    func setNavSelection(_ selection: HomeHeaderNavSelection) {
        navTabs.apply(selection)
        applySizeClassChrome()
    }

    /// Turns the text tabs on (the home screen pages) or off (iPad tabs, drawer).
    ///
    /// On also means: no back chevron (the Home tab returns), a solid backdrop so
    /// pages never scroll through the bar, and page-specific trailing controls.
    var showsTabStrip = false {
        didSet {
            guard showsTabStrip != oldValue else { return }
            applySizeClassChrome()
        }
    }

    /// The page the pager is nearest; picks the trailing controls.
    func setTabPage(_ page: HomeTab) {
        guard tabPage != page else { return }
        tabPage = page
        applyTrailingChrome()
    }

    /// Hides the Music "+" while a playlist (with its own bar) is open.
    func setMusicAddAvailable(_ available: Bool) {
        guard musicAddAvailable != available else { return }
        musicAddAvailable = available
        applyTrailingChrome()
    }

    /// Swaps the tab row for the search field and puts the cursor in it. The
    /// tabs come back when the search ends.
    func beginSearch(placeholder: String) {
        searchField.placeholder = placeholder
        searchField.text = ""
        isSearching = true
        applyTabRowContent(animated: true)
        applyTrailingChrome()
        searchField.becomeFirstResponder()
        onOverlayStateChange?()
    }

    /// Hides the search field, clears it and brings the tabs back.
    func endSearch() {
        guard isSearching else { return }
        isSearching = false
        searchField.text = ""
        searchField.resignFirstResponder()
        applyTabRowContent(animated: true)
        applyTrailingChrome()
        onOverlayStateChange?()
    }

    /// Tabs and search icon, or the search field, in the tab row.
    private func applyTabRowContent(animated: Bool) {
        let searching = isSearching && showsTabStrip
        let tabsShown = showsTabStrip && !searching
        if searching { searchRow.isHidden = false }
        if tabsShown { tabStrip.isHidden = false }
        let apply = {
            self.searchRow.alpha = searching ? 1 : 0
            self.tabStrip.alpha = tabsShown ? 1 : 0
            self.applySearchButtonAppearance()
        }
        let finish = { (_: Bool) in
            self.searchRow.isHidden = !(self.isSearching && self.showsTabStrip)
            self.tabStrip.isHidden = !self.showsTabStrip || self.isSearching
        }
        if animated, window != nil, !UIAccessibility.isReduceMotionEnabled {
            UIView.animate(
                withDuration: 0.18,
                delay: 0,
                options: [.beginFromCurrentState, .curveEaseInOut],
                animations: apply,
                completion: finish
            )
        } else {
            apply()
            finish(true)
        }
    }

    /// The Music "+" control, for anchoring its sheet on iPad.
    var addMusicAnchor: UIView { addMusicButton }

    /// Attaches the system add menu to the "+" control (primary action).
    func setAddMenu(_ menu: UIMenu) {
        addButton.menu = menu
    }

    /// Attaches the Library page's add menu to its "+" control.
    func setLibraryAddMenu(_ menu: UIMenu) {
        addLibraryButton.menu = menu
    }

    // MARK: - Actions

    @objc private func backTapped() {
        onGoBack?()
    }

    @objc private func lockTapped() {
        onToggleLiveLock?()
    }

    @objc private func blackTapped() {
        onPresentBlack?()
    }

    @objc private func freezeTapped() {
        onToggleFreeze?()
    }

    @objc private func settingsTapped() {
        onOpenSettings?()
    }

    @objc private func newShowTapped() {
        onNewShow?()
    }

    // MARK: - State

    /// Show-mode trailing chrome (Settings, +, Lock / Blackout when live).
    func setShowModeChrome(_ showMode: Bool) {
        guard showsShowChrome != showMode else { return }
        showsShowChrome = showMode
        applySizeClassChrome()
        libraryButton.accessibilityHint = showMode
            ? "Open Show, New Show, Camera Mode, and Recent Shows"
            : "Open Show, New Show, Camera Mode, Settings, and Recent Shows"
    }

    /// Lock + Blackout: every open Show. With a display or EclipseTV they act on
    /// the audience; with nothing connected Practice Mode (always on since
    /// 2026-11-25) makes the hero the output, so they rehearse there. Home has none.
    var showsLiveOutputChrome: Bool {
        showsShowChrome
    }

    /// Reflects whether live output is locked (amber lock control).
    func setLiveLocked(_ locked: Bool) {
        guard isLiveLocked != locked else { return }
        isLiveLocked = locked
        UIView.animate(withDuration: 0.22, delay: 0, options: .curveEaseInOut) {
            self.applyLockButtonAppearance()
            self.layoutIfNeeded()
        }
    }

    /// Reflects whether blackout is the live AirPlay source.
    func setBlackLive(_ live: Bool) {
        guard isBlackLive != live else { return }
        isBlackLive = live
        UIView.animate(withDuration: 0.22, delay: 0, options: .curveEaseInOut) {
            self.applyBlackButtonAppearance()
            self.layoutIfNeeded()
        }
    }

    /// Reflects whether Freeze holds the audience screen (blue snowflake).
    func setFrozen(_ frozen: Bool) {
        guard isFrozen != frozen else { return }
        isFrozen = frozen
        UIView.animate(withDuration: 0.22, delay: 0, options: .curveEaseInOut) {
            self.applyFreezeButtonAppearance()
            self.layoutIfNeeded()
        }
    }

    /// Reflects Blackout's colour (VoiceOver name and the long-press menu tick).
    func setBlankKind(_ kind: OutputBlankKind) {
        guard blankKind != kind else { return }
        blankKind = kind
        applyBlackButtonAppearance()
    }

    /// Enters or leaves arrange mode, where Done replaces the trailing controls.
    func setArranging(_ arranging: Bool) {
        isArranging = arranging
        if arranging { isSelecting = false }
        applyEditingChrome()
    }

    /// Enters or leaves Show multi-select; `actionsMenu` is shown when items are checked.
    func setSelecting(_ selecting: Bool, actionsMenu: UIMenu?) {
        isSelecting = selecting
        if selecting { isArranging = false }
        selectActionsButton.menu = actionsMenu
        selectActionsButton.isHidden = !selecting || actionsMenu == nil
        selectActionsButton.accessibilityLabel = "Selection actions"
        applyEditingChrome()
    }

    private func applyEditingChrome() {
        let editing = isArranging || isSelecting
        libraryButton.isEnabled = !editing
        menuPill.alpha = editing ? 0.45 : 1
        navTabs.isUserInteractionEnabled = !editing
        navTabs.alpha = editing ? 0.45 : 1
        tabStrip.setEnabled(!editing)
        applySizeClassChrome()
        onOverlayStateChange?()
        doneButton.accessibilityLabel = isSelecting
            ? "Done selecting"
            : "Done arranging"
        doneButton.accessibilityHint = isSelecting
            ? "Leaves select mode"
            : "Saves the new order"
    }

    /// Show mode: chevron left of the dropdown. Hidden on Home, while editing,
    /// and on iPad tabs (Home is the return control).
    private func applyBackButtonChrome() {
        let show = showsShowChrome && !isArranging && !isSelecting
            && !showsDestinationTabs && !showsTabStrip
        backButton.isHidden = !show
        backButton.isEnabled = show
        menuPillLeadingToSafe?.isActive = !show
        menuPillLeadingToBack?.isActive = show
    }

    /// Compact dropdown vs iPad destination tabs, plus trailing/back that
    /// depend on that choice.
    private func applySizeClassChrome() {
        applyTabStripPlacement()
        applyLeadingNavChrome()
        applyTrailingChrome()
        applyBackButtonChrome()
    }

    /// Text tabs under the row (upright) or inside it (phone landscape).
    private func applyTabStripPlacement() {
        applyTabRowContent(animated: false)
        topBackdrop.isHidden = !showsTabStrip
        backgroundColor = showsTabStrip ? .systemBackground : .clear
        let inline = traitCollection.verticalSizeClass == .compact
        NSLayoutConstraint.deactivate(tabStripBelowConstraints + tabStripInlineConstraints)
        guard showsTabStrip else { return }
        NSLayoutConstraint.activate(
            inline ? tabStripInlineConstraints : tabStripBelowConstraints
        )
    }

    /// Compact dropdown vs iPad destination tabs.
    private func applyLeadingNavChrome() {
        let tabs = showsDestinationTabs
        menuPill.isHidden = tabs
        navTabs.isHidden = !tabs
    }

    /// iPad full-width header shows Home / Show / Library tabs.
    var showsDestinationTabs: Bool {
        destinationTabsOverride ?? HomeHeaderNavLayout.showsDestinationTabs(
            horizontalSizeClass: traitCollection.horizontalSizeClass,
            verticalSizeClass: traitCollection.verticalSizeClass
        )
    }

    /// Testing only. Forces tab vs dropdown chrome; `nil` follows size class.
    var destinationTabsOverride: Bool? {
        didSet { applySizeClassChrome() }
    }

    private func applyTrailingChrome() {
        let editing = isArranging || isSelecting
        doneButton.isHidden = !editing
        if !isSelecting {
            selectActionsButton.isHidden = true
            selectActionsButton.menu = nil
        }
        // Library and Music get their own control; Home and Show keep theirs.
        let onLibrary = showsTabStrip && tabPage == .library
        let onMusic = showsTabStrip && tabPage == .music
        applySearchButtonAppearance()
        addMusicButton.isHidden = editing || !onMusic || !musicAddAvailable
        addLibraryButton.isHidden = editing || !onLibrary
        if editing || onLibrary || onMusic {
            lockButton.isHidden = true
            freezeButton.isHidden = true
            blackButton.isHidden = true
            settingsButton.isHidden = true
            addButton.isHidden = true
            newShowButton.isHidden = true
            return
        }
        lockButton.isHidden = !showsLiveOutputChrome
        freezeButton.isHidden = !showsLiveOutputChrome
        blackButton.isHidden = !showsLiveOutputChrome
        // With the text tabs, Settings is in the dropdown, not an icon here.
        settingsButton.isHidden = showsTabStrip || !(showsShowChrome || showsDestinationTabs)
        addButton.isHidden = !showsShowChrome
        newShowButton.isHidden = showsShowChrome
    }

    /// Whether the page in front has something to search: Library, Music's list
    /// and an open Show.
    var isSearchAvailable: Bool {
        guard showsTabStrip, !isArranging, !isSelecting else { return false }
        switch tabPage {
        case .library: return true
        case .music: return musicAddAvailable
        case .show: return showsShowChrome
        case .home: return false
        }
    }

    /// The search icon keeps its place left of Home on every page, so the tabs
    /// never shift sideways: dimmed and inactive where there is nothing to search,
    /// and out of the way while its field is up.
    private func applySearchButtonAppearance() {
        searchButton.isHidden = !showsTabStrip
        let available = isSearchAvailable
        searchButton.isEnabled = available
        searchButton.alpha = isSearching ? 0 : (available ? 1 : 0.3)
        searchButton.accessibilityElementsHidden = isSearching
    }

    /// Reflects EclipseTV (Multipeer) state. Combined with `setPresenting` for AirPlay.
    func setConnectionState(_ state: ConnectionDisplayState) {
        connectionState = state
        applyTrailingChrome()
        setAddEnabled(true)
    }

    /// Updates whether an external display is available for presentation.
    func setPresenting(_ presenting: Bool) {
        isAirPlayConnected = presenting
        applyTrailingChrome()
    }

    /// Enables or disables the "+" button (e.g. dimmed during a transfer).
    func setAddEnabled(_ enabled: Bool) {
        addButton.isEnabled = enabled
        addButton.alpha = enabled ? 1.0 : 0.4
    }

    /// The "+" button, exposed so callers can anchor popovers (iPad action sheets) to it.
    var addAnchor: UIView { addButton }

    /// The page title control, for anchoring Show-related popovers.
    var libraryAnchor: UIView { showsDestinationTabs ? navTabs : libraryButton }

    /// New Show control, for anchoring popovers when "+" is hidden on Home.
    var newShowAnchor: UIView { newShowButton }

    private func applyLockButtonAppearance() {
        let symbolConfig = UIImage.SymbolConfiguration(pointSize: 20, weight: .regular)
        // Same lock glyph both ways — amber fill already marks the active state.
        let name = "lock.fill"
        if isLiveLocked {
            var config = UIButton.Configuration.filled()
            config.image = UIImage(systemName: name, withConfiguration: symbolConfig)
            config.baseForegroundColor = .white
            config.baseBackgroundColor = .systemOrange
            config.cornerStyle = .capsule
            config.contentInsets = NSDirectionalEdgeInsets(
                top: 6, leading: 6, bottom: 6, trailing: 6
            )
            lockButton.configuration = config
        } else {
            lockButton.configuration = Self.barIconConfig(
                systemName: name,
                symbolConfig: symbolConfig
            )
        }
        lockButton.accessibilityValue = isLiveLocked ? "On" : "Off"
    }

    private func applyBlackButtonAppearance() {
        let symbolConfig = UIImage.SymbolConfiguration(pointSize: 20, weight: .regular)
        // Always fill — matches lock / settings; active state is the blue capsule.
        let name = "moon.fill"
        if isBlackLive {
            var config = UIButton.Configuration.filled()
            config.image = UIImage(systemName: name, withConfiguration: symbolConfig)
            config.baseForegroundColor = .white
            config.baseBackgroundColor = .accent
            config.cornerStyle = .capsule
            config.contentInsets = NSDirectionalEdgeInsets(
                top: 6, leading: 6, bottom: 6, trailing: 6
            )
            blackButton.configuration = config
        } else {
            blackButton.configuration = Self.barIconConfig(
                systemName: name,
                symbolConfig: symbolConfig
            )
        }
        blackButton.accessibilityValue = isBlackLive ? "On" : "Off"
        blackButton.accessibilityLabel = blankKind.title
        blackButton.menu = blankKindMenu()
    }

    /// Long-press menu on Blackout: Black or White, the current one ticked.
    private func blankKindMenu() -> UIMenu {
        let actions = OutputBlankKind.allCases.map { kind in
            UIAction(
                title: kind.title,
                image: UIImage(systemName: kind.systemImage),
                state: kind == blankKind ? .on : .off
            ) { [weak self] _ in
                self?.onSelectBlankKind?(kind)
            }
        }
        return UIMenu(title: "Blackout Color", children: actions)
    }

    private func applyFreezeButtonAppearance() {
        let symbolConfig = UIImage.SymbolConfiguration(pointSize: 20, weight: .regular)
        // Same snowflake both ways, as on the Mac; the blue capsule marks "on".
        let name = "snowflake"
        if isFrozen {
            var config = UIButton.Configuration.filled()
            config.image = UIImage(systemName: name, withConfiguration: symbolConfig)
            config.baseForegroundColor = .white
            config.baseBackgroundColor = .accent
            config.cornerStyle = .capsule
            config.contentInsets = NSDirectionalEdgeInsets(
                top: 6, leading: 6, bottom: 6, trailing: 6
            )
            freezeButton.configuration = config
        } else {
            freezeButton.configuration = Self.barIconConfig(
                systemName: name,
                symbolConfig: symbolConfig
            )
        }
        freezeButton.accessibilityValue = isFrozen ? "On" : "Off"
    }

    private func applyNewShowButtonAppearance() {
        var config = UIButton.Configuration.filled()
        config.title = "+ New Show"
        config.baseForegroundColor = .white
        config.baseBackgroundColor = .accent
        config.cornerStyle = .capsule
        config.contentInsets = NSDirectionalEdgeInsets(
            top: 7, leading: 14, bottom: 7, trailing: 14
        )
        config.titleTextAttributesTransformer =
            UIConfigurationTextAttributesTransformer { incoming in
                var outgoing = incoming
                outgoing.font = .systemFont(ofSize: 15, weight: .semibold)
                return outgoing
            }
        newShowButton.configuration = config
    }
}
