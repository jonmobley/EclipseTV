//
//  AlbumsViewController.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

// AlbumsViewController.swift
import UIKit

/// Browses joined cloud albums on the phone: one section per album (header = album
/// name), thumbnails from the manifest's HTTPS URLs. Read-only — tapping an item
/// presents on AirPlay and opens a phone preview. Works with or without Apple TV.
final class AlbumsViewController: UIViewController {

    private let store = AlbumBrowserStore.shared
    private let headerKind = UICollectionView.elementKindSectionHeader
    private let headerReuseId = "AlbumSectionHeader"

    private var collectionView: UICollectionView!
    private let emptyLabel = UILabel()
    private let refreshControl = UIRefreshControl()
    private var settingsObserver: NSObjectProtocol?

    /// Invoked when the user enters/changes the join code, so the parent can push it
    /// to a connected Apple TV. Local browsing updates regardless.
    var onCodeEntered: ((String) -> Void)?

    /// Invoked when a joined item becomes live on the external display.
    var onBecameLive: (() -> Void)?

    /// Invoked after the user leaves the joined presentation (code cleared).
    var onLeftPresentation: (() -> Void)?

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Join"
        view.backgroundColor = .systemBackground
        setupNavigationItems()
        setupCollectionView()
        setupEmptyLabel()
        updateEmptyState()
        settingsObserver = NotificationCenter.default.addObserver(
            forName: ExternalOutputSettings.didChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.collectionView.collectionViewLayout.invalidateLayout()
        }
    }

    deinit {
        if let settingsObserver {
            NotificationCenter.default.removeObserver(settingsObserver)
        }
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        navigationController?.setNavigationBarHidden(false, animated: animated)
        if store.hasAccountConfigured {
            refresh()
        }
    }

    // MARK: - Setup

    private func setupNavigationItems() {
        navigationItem.leftBarButtonItem = UIBarButtonItem(
            barButtonSystemItem: .close, target: self, action: #selector(closeTapped))
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            image: UIImage(systemName: "ellipsis.circle"),
            menu: makeOverflowMenu()
        )
    }

    private func makeOverflowMenu() -> UIMenu {
        let joinTitle = store.hasAccountConfigured ? "Change Join Code…" : "Enter Join Code…"
        let join = UIAction(title: joinTitle, image: UIImage(systemName: "number")) { [weak self] _ in
            self?.changeCodeTapped()
        }
        var actions: [UIMenuElement] = [join]
        if store.hasAccountConfigured {
            let leave = UIAction(
                title: "Leave Presentation",
                image: UIImage(systemName: "rectangle.portrait.and.arrow.right"),
                attributes: .destructive
            ) { [weak self] _ in
                self?.leavePresentation()
            }
            actions.append(leave)
        }
        return UIMenu(children: actions)
    }

    private func refreshOverflowMenu() {
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            image: UIImage(systemName: "ellipsis.circle"),
            menu: makeOverflowMenu()
        )
    }

    private func setupCollectionView() {
        let layout = UICollectionViewFlowLayout()
        layout.minimumInteritemSpacing = 12
        layout.minimumLineSpacing = 12
        layout.sectionInset = UIEdgeInsets(top: 8, left: 16, bottom: 24, right: 16)
        layout.headerReferenceSize = CGSize(width: view.bounds.width, height: 44)

        collectionView = UICollectionView(frame: view.bounds, collectionViewLayout: layout)
        collectionView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        collectionView.backgroundColor = .systemBackground
        collectionView.alwaysBounceVertical = true
        collectionView.dataSource = self
        collectionView.delegate = self
        collectionView.register(AlbumThumbnailCell.self, forCellWithReuseIdentifier: AlbumThumbnailCell.reuseIdentifier)
        collectionView.register(AlbumSectionHeaderView.self,
                                forSupplementaryViewOfKind: headerKind, withReuseIdentifier: headerReuseId)
        refreshControl.addTarget(self, action: #selector(refresh), for: .valueChanged)
        collectionView.refreshControl = refreshControl
        view.addSubview(collectionView)
    }

    private func setupEmptyLabel() {
        emptyLabel.numberOfLines = 0
        emptyLabel.textAlignment = .center
        emptyLabel.textColor = .secondaryLabel
        emptyLabel.font = .systemFont(ofSize: 16)
        emptyLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(emptyLabel)
        NSLayoutConstraint.activate([
            emptyLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            emptyLabel.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            emptyLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 40),
            emptyLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -40)
        ])
    }

    // MARK: - Data

    @objc private func refresh() {
        guard store.hasAccountConfigured else {
            refreshControl.endRefreshing()
            updateEmptyState()
            return
        }
        Task { [weak self] in
            guard let self = self else { return }
            defer { self.refreshControl.endRefreshing() }
            do {
                _ = try await self.store.refresh()
                self.collectionView.reloadData()
                self.updateEmptyState()
            } catch {
                self.collectionView.reloadData()
                self.updateEmptyState(message: error.localizedDescription)
            }
        }
    }

    private func updateEmptyState(message: String? = nil) {
        let isEmpty = store.albums.allSatisfy { $0.items.isEmpty }
        collectionView.isHidden = isEmpty
        emptyLabel.isHidden = !isEmpty
        if let message = message {
            emptyLabel.text = message
        } else if !store.hasAccountConfigured {
            emptyLabel.text = "Enter your \(AlbumConfig.codeLength)-digit join code to open a shared presentation.\n\nTap the menu button above."
        } else {
            emptyLabel.text = "No content yet for this join code."
        }
    }

    private func cellSize() -> CGSize {
        let orientation = ExternalOutputSettings.orientation
        let spacing: CGFloat = 12
        let inset: CGFloat = 16
        let columns = CGFloat(orientation.gridColumnCount(
            forWidth: collectionView.bounds.width,
            sectionInset: inset,
            spacing: spacing
        ))
        let available = collectionView.bounds.width - (inset * 2) - (spacing * (columns - 1))
        let width = floor(available / columns)
        return CGSize(width: width, height: width * orientation.gridCellHeightOverWidth)
    }

    // MARK: - Actions

    @objc private func closeTapped() {
        // Keep joined AirPlay sticky; do not restore the prior library item.
        dismiss(animated: true)
    }

    private func changeCodeTapped() {
        let alert = UIAlertController(
            title: store.hasAccountConfigured ? "Change Join Code" : "Enter Join Code",
            message: "Type your \(AlbumConfig.codeLength)-digit join code.",
            preferredStyle: .alert)
        alert.addTextField { field in
            field.placeholder = String(repeating: "0", count: AlbumConfig.codeLength)
            field.keyboardType = .numberPad
            field.textContentType = .oneTimeCode
            field.text = self.store.accountCode
        }
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(UIAlertAction(title: "Join", style: .default) { [weak self, weak alert] _ in
            guard let self = self else { return }
            let raw = alert?.textFields?.first?.text ?? ""
            guard self.store.setAccountCode(raw) else {
                self.presentInvalidCodeAlert()
                return
            }
            self.onCodeEntered?(AlbumConfig.normalize(raw))
            self.refreshOverflowMenu()
            self.collectionView.reloadData()
            self.refresh()
        })
        present(alert, animated: true)
    }

    private func leavePresentation() {
        let alert = UIAlertController(
            title: "Leave Presentation?",
            message: "This removes the join code from this iPhone. A connected Apple TV keeps its copy until changed there.",
            preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(UIAlertAction(title: "Leave", style: .destructive) { [weak self] _ in
            guard let self else { return }
            self.store.clearAccount()
            self.refreshOverflowMenu()
            self.collectionView.reloadData()
            self.updateEmptyState()
            self.onLeftPresentation?()
        })
        present(alert, animated: true)
    }

    private func presentInvalidCodeAlert() {
        let alert = UIAlertController(
            title: "Invalid Code",
            message: "Enter your \(AlbumConfig.codeLength)-digit join code.",
            preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        present(alert, animated: true)
    }
}

// MARK: - Data Source & Delegate

extension AlbumsViewController: UICollectionViewDataSource, UICollectionViewDelegateFlowLayout {

    func numberOfSections(in collectionView: UICollectionView) -> Int {
        store.albums.count
    }

    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        store.albums[safe: section]?.items.count ?? 0
    }

    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        guard let cell = collectionView.dequeueReusableCell(
            withReuseIdentifier: AlbumThumbnailCell.reuseIdentifier,
            for: indexPath) as? AlbumThumbnailCell else {
            return UICollectionViewCell()
        }
        if let item = store.albums[safe: indexPath.section]?.items[safe: indexPath.item] {
            cell.configure(with: item, cellSize: cellSize())
        }
        return cell
    }

    func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout,
                        sizeForItemAt indexPath: IndexPath) -> CGSize {
        cellSize()
    }

    func collectionView(_ collectionView: UICollectionView,
                        viewForSupplementaryElementOfKind kind: String,
                        at indexPath: IndexPath) -> UICollectionReusableView {
        guard let header = collectionView.dequeueReusableSupplementaryView(
            ofKind: kind, withReuseIdentifier: headerReuseId, for: indexPath
        ) as? AlbumSectionHeaderView else {
            return UICollectionReusableView()
        }
        header.titleLabel.text = store.albums[safe: indexPath.section]?.resolvedName
        return header
    }

    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        collectionView.deselectItem(at: indexPath, animated: true)
        guard let item = store.albums[safe: indexPath.section]?.items[safe: indexPath.item] else { return }
        if let url = item.remoteURL {
            let source: PresentationSource = item.isVideo
                ? .video(url, isLooping: false, isMuted: false)
                : .image(url)
            if item.isVideo {
                AudioPlayerController.shared.stop()
            }
            ExternalDisplayManager.shared.presentJoined(source)
            onBecameLive?()
        }
        let preview = AlbumItemPreviewViewController(item: item)
        preview.modalPresentationStyle = .overFullScreen
        present(preview, animated: true)
    }
}

/// Simple shelf-style section header showing the album name.
final class AlbumSectionHeaderView: UICollectionReusableView {
    let titleLabel = UILabel()

    override init(frame: CGRect) {
        super.init(frame: frame)
        titleLabel.font = .systemFont(ofSize: 20, weight: .bold)
        titleLabel.textColor = .label
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(titleLabel)
        NSLayoutConstraint.activate([
            titleLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -16),
            titleLabel.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -6)
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

/// Bounds-checked array access used throughout the album browser.
extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
