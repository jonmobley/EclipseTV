//
//  MediaLibraryPickerViewController.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import UIKit

/// Page to pick library images, videos, or PDFs — either to Preview, or to add
/// into an open Show (multi-select + Add).
final class MediaLibraryPickerViewController: UIViewController {

    /// Filter chips for the library grid.
    enum Filter: Int, CaseIterable {
        case all
        case image
        case video
        case pdf

        var title: String {
            switch self {
            case .all: return "All"
            case .image: return "Image"
            case .video: return "Video"
            case .pdf: return "PDF"
            }
        }
    }

    enum Item: Hashable {
        case media(String)
        case pdf(UUID)

        /// Show membership id (`LibraryItemDTO.id` or PDF uuid string).
        var membershipId: String {
            switch self {
            case .media(let id): return id
            case .pdf(let id): return id.uuidString
            }
        }
    }

    /// When set, taps toggle selection and **Add** appends to this Show (no live).
    var targetShowId: UUID?
    /// Called when the user confirms Add in Show mode.
    var onAddToShow: (([String], [UUID]) -> Void)?
    /// Crop an existing still or video (same flow as Show ⋯ Edit).
    var onRequestEdit: ((String) -> Void)?
    /// Replace a video’s poster frame.
    var onRequestVideoThumbnail: ((String) -> Void)?
    /// Persist loop / mute and sync to EclipseTV when linked.
    var onApplyVideoSetting: ((String, Bool?, Bool?) -> Void)?
    /// Deletes after the picker’s confirmation. Grid owns TV + local teardown.
    var onPerformDelete: ((String) -> Void)?
    /// Re-send a purged Apple TV item from Photos.
    var onRequestResend: ((String) -> Void)?
    /// True when EclipseTV is linked (TV-backed deletes need a live link).
    var onIsEclipseTVLinked: (() -> Bool)?
    /// Invoked when a TV-backed delete is blocked because EclipseTV is unlinked.
    var onRequestEclipseTVConnect: (() -> Void)?

    var filter: Filter = .all
    var items: [Item] = []
    var searchQuery = ""
    private var selected = Set<Item>()
    /// Item ids already on `targetShowId` (media id or PDF uuid string).
    var memberIds: Set<String> = []
    var collectionView: UICollectionView!
    private let filterControl = UISegmentedControl(items: Filter.allCases.map(\.title))
    let emptyLabel = UILabel()
    private var thumbRetryWork: DispatchWorkItem?
    var addButton: UIBarButtonItem?
    let searchBarButton: UIBarButtonItem = {
        let item = UIBarButtonItem(
            image: UIImage(systemName: "magnifyingglass"),
            style: .plain,
            target: nil,
            action: nil
        )
        item.accessibilityLabel = "Search"
        return item
    }()
    var searchController: UISearchController?

    var isAddToShowMode: Bool { targetShowId != nil }

    private var isNavRoot: Bool {
        navigationController?.viewControllers.first === self
    }

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        title = "Media Library"
        searchBarButton.target = self
        searchBarButton.action = #selector(searchTapped)
        if isAddToShowMode {
            let add = UIBarButtonItem(
                title: "Add",
                style: .done,
                target: self,
                action: #selector(addTapped)
            )
            add.isEnabled = false
            addButton = add
        }
        updateRightBarButtons(searchActive: false)

        filterControl.selectedSegmentIndex = Filter.all.rawValue
        filterControl.addTarget(self, action: #selector(filterChanged), for: .valueChanged)
        filterControl.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(filterControl)

        let layout = UICollectionViewFlowLayout()
        layout.minimumInteritemSpacing = 12
        layout.minimumLineSpacing = 12
        layout.sectionInset = UIEdgeInsets(top: 12, left: 16, bottom: 16, right: 16)

        collectionView = UICollectionView(frame: .zero, collectionViewLayout: layout)
        collectionView.backgroundColor = .systemBackground
        collectionView.delegate = self
        collectionView.dataSource = self
        collectionView.allowsMultipleSelection = isAddToShowMode
        collectionView.translatesAutoresizingMaskIntoConstraints = false
        collectionView.register(
            LibraryThumbnailCell.self,
            forCellWithReuseIdentifier: LibraryThumbnailCell.reuseIdentifier
        )
        view.addSubview(collectionView)

        emptyLabel.text = "No items"
        emptyLabel.textColor = .secondaryLabel
        emptyLabel.textAlignment = .center
        emptyLabel.font = .preferredFont(forTextStyle: .body)
        emptyLabel.numberOfLines = 0
        emptyLabel.translatesAutoresizingMaskIntoConstraints = false
        emptyLabel.isHidden = true
        view.addSubview(emptyLabel)

        NSLayoutConstraint.activate([
            filterControl.topAnchor.constraint(
                equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 8
            ),
            filterControl.leadingAnchor.constraint(
                equalTo: view.leadingAnchor, constant: 16
            ),
            filterControl.trailingAnchor.constraint(
                equalTo: view.trailingAnchor, constant: -16
            ),

            collectionView.topAnchor.constraint(
                equalTo: filterControl.bottomAnchor, constant: 8
            ),
            collectionView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            collectionView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            collectionView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            emptyLabel.centerXAnchor.constraint(equalTo: collectionView.centerXAnchor),
            emptyLabel.centerYAnchor.constraint(equalTo: collectionView.centerYAnchor),
            emptyLabel.leadingAnchor.constraint(
                greaterThanOrEqualTo: view.leadingAnchor, constant: 32
            ),
            emptyLabel.trailingAnchor.constraint(
                lessThanOrEqualTo: view.trailingAnchor, constant: -32
            )
        ])

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(reload),
            name: PDFStore.didChangeNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(reload),
            name: PDFThumbnailStore.didChangeNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(reload),
            name: ExternalOutputSettings.didChangeNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(reload),
            name: MediaTitleStore.didChangeNotification,
            object: nil
        )
        reload()
    }

    deinit {
        thumbRetryWork?.cancel()
        NotificationCenter.default.removeObserver(self)
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        navigationController?.setNavigationBarHidden(false, animated: animated)
        if isNavRoot {
            navigationItem.leftBarButtonItem = UIBarButtonItem(
                title: "Back",
                style: .plain,
                target: self,
                action: #selector(backTapped)
            )
        }
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        guard let layout = collectionView.collectionViewLayout
                as? UICollectionViewFlowLayout else { return }
        let inset = layout.sectionInset.left
        let spacing = layout.minimumInteritemSpacing
        let orientation = ExternalOutputSettings.orientation
        let columns = CGFloat(orientation.gridColumnCount(
            forWidth: collectionView.bounds.width,
            sectionInset: inset,
            spacing: spacing
        ))
        let totalSpacing = inset * 2 + spacing * (columns - 1)
        let side = max(
            ((collectionView.bounds.width - totalSpacing) / columns).rounded(.down),
            1
        )
        let aspect = orientation.gridCellHeightOverWidth
        layout.itemSize = CGSize(width: side, height: side * aspect)
    }

    // MARK: - Actions

    @objc private func backTapped() {
        closePicker()
    }

    /// Pops when pushed from Home; dismisses when this page is the presented root.
    private func closePicker(completion: (() -> Void)? = nil) {
        if let nav = navigationController, nav.viewControllers.first !== self {
            nav.popViewController(animated: true)
            if let completion {
                if let coordinator = nav.transitionCoordinator {
                    coordinator.animate(alongsideTransition: nil) { _ in
                        completion()
                    }
                } else {
                    completion()
                }
            }
            return
        }
        dismiss(animated: true, completion: completion)
    }

    @objc private func addTapped() {
        guard isAddToShowMode, !selected.isEmpty else { return }
        let selectedIds = selected.map(\.membershipId)
        if AlreadyInShowAlert.needsConfirmation(
            selectedIds: selectedIds,
            memberIds: memberIds
        ) {
            AlreadyInShowAlert.present(from: self) { [weak self] in
                self?.commitAddToShow()
            }
            return
        }
        commitAddToShow()
    }

    private func commitAddToShow() {
        var mediaIds: [String] = []
        var pdfIds: [UUID] = []
        for item in selected {
            switch item {
            case .media(let id): mediaIds.append(id)
            case .pdf(let id): pdfIds.append(id)
            }
        }
        let add = onAddToShow
        closePicker {
            add?(mediaIds, pdfIds)
        }
    }

    @objc private func filterChanged() {
        filter = Filter(rawValue: filterControl.selectedSegmentIndex) ?? .all
        selected.removeAll()
        updateAddButton()
        reload()
    }

    private func updateAddButton() {
        addButton?.isEnabled = !selected.isEmpty
        let count = selected.count
        addButton?.title = count > 0 ? "Add (\(count))" : "Add"
    }

    /// Toggles a tile in the Add-to-Show selection. Members stay selectable.
    private func toggleAddSelection(for item: Item, at indexPath: IndexPath) {
        if selected.contains(item) {
            selected.remove(item)
        } else {
            selected.insert(item)
        }
        updateAddButton()
        guard let cell = collectionView.cellForItem(at: indexPath)
                as? LibraryThumbnailCell else { return }
        let isSelected = selected.contains(item)
        cell.setPickerSelected(isSelected)
        cell.accessibilityTraits = isSelected ? [.selected] : []
    }

    // MARK: - Data

    @objc func reload() {
        let media = TVLibraryStore.shared.items
        let pdfs = PDFStore.shared.documents
        memberIds = {
            guard let showId = targetShowId,
                  let album = LocalAlbumStore.shared.album(id: showId)
            else { return [] }
            return Set(album.itemIds)
        }()
        items = displayedItems(from: media, pdfs: pdfs)
        selected = selected.filter { items.contains($0) }
        emptyLabel.isHidden = !items.isEmpty
        emptyLabel.text = emptyMessage()
        collectionView.reloadData()
        updateAddButton()
        scheduleThumbnailRetry()
    }

    /// Type filter, then title / filename search.
    func displayedItems(from media: [LibraryItemDTO], pdfs: [SavedPDF]) -> [Item] {
        let mediaItems = media.map { Item.media($0.id) }
        let pdfItems = pdfs.map { Item.pdf($0.id) }
        let typed: [Item]
        switch filter {
        case .all:
            typed = mediaItems + pdfItems
        case .image:
            typed = media.filter { !$0.isVideo }.map { .media($0.id) }
        case .video:
            typed = media.filter(\.isVideo).map { .media($0.id) }
        case .pdf:
            typed = pdfItems
        }
        return typed.filter { itemMatchesSearch($0, media: media, pdfs: pdfs) }
    }

    /// Overlay title, filename, or PDF title.
    func itemMatchesSearch(
        _ item: Item,
        media: [LibraryItemDTO],
        pdfs: [SavedPDF]
    ) -> Bool {
        switch item {
        case .media(let id):
            let name = media.first(where: { $0.id == id })?.name
            return LibrarySearch.matches(
                searchQuery,
                in: [MediaTitleStore.title(forId: id), name]
            )
        case .pdf(let id):
            let title = pdfs.first(where: { $0.id == id })?.title
            return LibrarySearch.matches(searchQuery, in: [title])
        }
    }

    /// Reloads once after disk thumbnails may have arrived (store uses a sole delegate).
    private func scheduleThumbnailRetry() {
        thumbRetryWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.collectionView.reloadData()
        }
        thumbRetryWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45, execute: work)
    }

    /// Empty copy; search misses vs Display Mode bucket.
    func emptyMessage() -> String {
        let needle = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        if !needle.isEmpty {
            return "No titles matching “\(needle)”"
        }
        let mode = ExternalOutputSettings.orientation.rawValue
        guard TVLibraryStore.shared.inactiveModeHasContent() else {
            return "No items in \(mode)"
        }
        let other = ExternalOutputSettings.isVerticalMode ? "Landscape" : "Vertical"
        return "No items in \(mode).\nSwitch Display Mode to see \(other) media."
    }
}

// MARK: - UICollectionViewDataSource

extension MediaLibraryPickerViewController: UICollectionViewDataSource {
    func collectionView(
        _ collectionView: UICollectionView,
        numberOfItemsInSection section: Int
    ) -> Int {
        items.count
    }

    func collectionView(
        _ collectionView: UICollectionView,
        cellForItemAt indexPath: IndexPath
    ) -> UICollectionViewCell {
        guard let cell = collectionView.dequeueReusableCell(
            withReuseIdentifier: LibraryThumbnailCell.reuseIdentifier,
            for: indexPath
        ) as? LibraryThumbnailCell else {
            return UICollectionViewCell()
        }
        guard items.indices.contains(indexPath.item) else { return cell }
        let item = items[indexPath.item]
        switch item {
        case .media(let id):
            if let libraryItem = TVLibraryStore.shared.items.first(where: { $0.id == id }) {
                cell.configure(
                    with: libraryItem,
                    thumbnail: TVLibraryStore.shared.thumbnail(for: id),
                    isLive: false
                )
                if !isAddToShowMode {
                    cell.setMoreMenu(mediaLibraryMenu(for: libraryItem))
                }
            }
        case .pdf(let id):
            if let doc = PDFStore.shared.documents.first(where: { $0.id == id }) {
                cell.configureSpecial(
                    title: doc.title,
                    systemImage: "doc.richtext",
                    thumbnail: PDFThumbnailStore.shared.image(for: id),
                    fillColor: .darkGray,
                    isLive: false,
                    titleNumberOfLines: 1,
                    typeIcon: .pdf
                )
                if !isAddToShowMode {
                    cell.setMoreMenu(pdfLibraryMenu(for: doc))
                }
            }
        }
        let isSelected = selected.contains(item)
        cell.setPickerSelected(isSelected)
        cell.accessibilityTraits = isSelected ? [.selected] : []
        return cell
    }
}

// MARK: - UICollectionViewDelegate

extension MediaLibraryPickerViewController: UICollectionViewDelegate {
    func collectionView(
        _ collectionView: UICollectionView,
        didSelectItemAt indexPath: IndexPath
    ) {
        guard items.indices.contains(indexPath.item) else { return }
        let item = items[indexPath.item]
        if isAddToShowMode {
            collectionView.deselectItem(at: indexPath, animated: false)
            toggleAddSelection(for: item, at: indexPath)
            return
        }
        switch item {
        case .media(let id):
            guard let libraryItem = TVLibraryStore.shared.items.first(where: { $0.id == id })
            else { return }
            previewMedia(libraryItem)
        case .pdf(let id):
            guard let doc = PDFStore.shared.documents.first(where: { $0.id == id }) else {
                return
            }
            previewPDF(doc)
        }
    }

    func collectionView(
        _ collectionView: UICollectionView,
        contextMenuConfigurationForItemAt indexPath: IndexPath,
        point: CGPoint
    ) -> UIContextMenuConfiguration? {
        guard !isAddToShowMode, items.indices.contains(indexPath.item) else { return nil }
        let item = items[indexPath.item]
        return UIContextMenuConfiguration(identifier: nil, previewProvider: nil) {
            [weak self] _ in
            self?.libraryContextMenu(for: item)
        }
    }
}
