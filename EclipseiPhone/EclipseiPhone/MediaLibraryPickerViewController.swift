//
//  MediaLibraryPickerViewController.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import UIKit

/// Sheet to pick an existing library image, video, or PDF to present.
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

    private enum Item: Hashable {
        case media(String)
        case pdf(UUID)
    }

    /// Called when the user taps an image or video.
    var onSelectMedia: ((LibraryItemDTO) -> Void)?
    /// Called when the user taps a saved PDF.
    var onSelectPDF: ((SavedPDF) -> Void)?

    private var filter: Filter = .all
    private var items: [Item] = []
    private var collectionView: UICollectionView!
    private let filterControl = UISegmentedControl(items: Filter.allCases.map(\.title))
    private let emptyLabel = UILabel()
    private var thumbRetryWork: DispatchWorkItem?

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        title = "Library"
        navigationItem.leftBarButtonItem = UIBarButtonItem(
            barButtonSystemItem: .done,
            target: self,
            action: #selector(doneTapped)
        )

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
            emptyLabel.centerYAnchor.constraint(equalTo: collectionView.centerYAnchor)
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
        reload()
    }

    deinit {
        thumbRetryWork?.cancel()
        NotificationCenter.default.removeObserver(self)
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        guard let layout = collectionView.collectionViewLayout
                as? UICollectionViewFlowLayout else { return }
        let inset = layout.sectionInset.left + layout.sectionInset.right
        let spacing = layout.minimumInteritemSpacing
        let width = collectionView.bounds.width - inset
        let side = floor((width - spacing * 2) / 3)
        let aspect = ExternalOutputSettings.orientation.gridCellHeightOverWidth
        layout.itemSize = CGSize(width: side, height: side * aspect)
    }

    // MARK: - Actions

    @objc private func doneTapped() {
        dismiss(animated: true)
    }

    @objc private func filterChanged() {
        filter = Filter(rawValue: filterControl.selectedSegmentIndex) ?? .all
        reload()
    }

    // MARK: - Data

    @objc private func reload() {
        let media = TVLibraryStore.shared.items
        let pdfs = PDFStore.shared.documents
        switch filter {
        case .all:
            items = media.map { .media($0.id) } + pdfs.map { .pdf($0.id) }
        case .image:
            items = media.filter { !$0.isVideo }.map { .media($0.id) }
        case .video:
            items = media.filter(\.isVideo).map { .media($0.id) }
        case .pdf:
            items = pdfs.map { .pdf($0.id) }
        }
        emptyLabel.isHidden = !items.isEmpty
        collectionView.reloadData()
        scheduleThumbnailRetry()
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
        switch items[indexPath.item] {
        case .media(let id):
            if let item = TVLibraryStore.shared.items.first(where: { $0.id == id }) {
                cell.configure(
                    with: item,
                    thumbnail: TVLibraryStore.shared.thumbnail(for: id),
                    isLive: id == TVLibraryStore.shared.currentId
                )
            }
        case .pdf(let id):
            if let doc = PDFStore.shared.documents.first(where: { $0.id == id }) {
                let live = ExternalDisplayManager.shared.isPDFLive
                    && ExternalDisplayManager.shared.livePDFDocumentId == id
                cell.configureSpecial(
                    title: doc.title,
                    systemImage: "doc.richtext",
                    thumbnail: PDFThumbnailStore.shared.image(for: id),
                    fillColor: .darkGray,
                    isLive: live
                )
            }
        }
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
        switch items[indexPath.item] {
        case .media(let id):
            guard let item = TVLibraryStore.shared.items.first(where: { $0.id == id }) else {
                return
            }
            onSelectMedia?(item)
        case .pdf(let id):
            guard let doc = PDFStore.shared.documents.first(where: { $0.id == id }) else {
                return
            }
            onSelectPDF?(doc)
        }
    }
}
