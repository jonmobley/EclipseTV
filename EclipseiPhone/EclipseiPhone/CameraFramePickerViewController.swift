//
//  CameraFramePickerViewController.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import UIKit
import PhotosUI
import UniformTypeIdentifiers

/// Sheet to pick None / a stored PNG frame, or import/delete frames.
final class CameraFramePickerViewController: UIViewController {

    private enum Item: Hashable {
        case none
        case frame(UUID)
        case importFrames
    }

    private var items: [Item] = []
    private var dataSource: UICollectionViewDiffableDataSource<Int, Item>!
    private var collectionView: UICollectionView!

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        title = "Camera Frame"
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            barButtonSystemItem: .done,
            target: self,
            action: #selector(doneTapped)
        )

        let layout = UICollectionViewFlowLayout()
        layout.minimumInteritemSpacing = 12
        layout.minimumLineSpacing = 12
        layout.sectionInset = UIEdgeInsets(top: 16, left: 16, bottom: 16, right: 16)

        collectionView = UICollectionView(frame: .zero, collectionViewLayout: layout)
        collectionView.backgroundColor = .systemBackground
        collectionView.delegate = self
        collectionView.translatesAutoresizingMaskIntoConstraints = false
        collectionView.register(
            FramePickerCell.self,
            forCellWithReuseIdentifier: FramePickerCell.reuseId
        )
        view.addSubview(collectionView)
        NSLayoutConstraint.activate([
            collectionView.topAnchor.constraint(equalTo: view.topAnchor),
            collectionView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            collectionView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            collectionView.trailingAnchor.constraint(equalTo: view.trailingAnchor)
        ])

        dataSource = UICollectionViewDiffableDataSource(
            collectionView: collectionView
        ) { [weak self] collectionView, indexPath, item in
            let cell = collectionView.dequeueReusableCell(
                withReuseIdentifier: FramePickerCell.reuseId,
                for: indexPath
            ) as! FramePickerCell
            self?.configure(cell, with: item)
            return cell
        }

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(storeChanged),
            name: CameraFrameStore.didChangeNotification,
            object: nil
        )
        reload()
    }

    deinit {
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
        layout.itemSize = CGSize(width: side, height: side * 16 / 9 + 28)
    }

    // MARK: - Data

    private func reload() {
        let store = CameraFrameStore.shared
        items = [.none] + store.frames.map { .frame($0.id) } + [.importFrames]
        var snapshot = NSDiffableDataSourceSnapshot<Int, Item>()
        snapshot.appendSections([0])
        snapshot.appendItems(items)
        dataSource.apply(snapshot, animatingDifferences: true)
    }

    private func configure(_ cell: FramePickerCell, with item: Item) {
        let store = CameraFrameStore.shared
        switch item {
        case .none:
            cell.configure(
                title: "None",
                image: nil,
                systemImage: "circle.slash",
                selected: store.selectedId == nil
            )
        case .frame(let id):
            cell.configure(
                title: "Frame",
                image: store.image(for: id),
                systemImage: nil,
                selected: store.selectedId == id
            )
        case .importFrames:
            cell.configure(
                title: "Import",
                image: nil,
                systemImage: "square.and.arrow.down",
                selected: false
            )
        }
    }

    // MARK: - Actions

    @objc private func doneTapped() {
        dismiss(animated: true)
    }

    @objc private func storeChanged() {
        reload()
    }

    private var remainingFrameSlots: Int {
        max(0, CameraFrameStore.maxFrameCount - CameraFrameStore.shared.frames.count)
    }

    private func importFrames() {
        guard remainingFrameSlots > 0 else {
            let alert = UIAlertController(
                title: "Frame Library Full",
                message: "Remove a frame before importing more (max \(CameraFrameStore.maxFrameCount)).",
                preferredStyle: .alert
            )
            alert.addAction(UIAlertAction(title: "OK", style: .default))
            present(alert, animated: true)
            return
        }

        let sheet = UIAlertController(
            title: "Import Frames",
            message: "Select one or more images (up to \(remainingFrameSlots) more).",
            preferredStyle: .actionSheet
        )
        sheet.addAction(UIAlertAction(title: "Photo Library", style: .default) { [weak self] _ in
            self?.presentPhotoPicker()
        })
        sheet.addAction(UIAlertAction(title: "Files", style: .default) { [weak self] _ in
            self?.presentDocumentPicker()
        })
        sheet.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        if let pop = sheet.popoverPresentationController {
            pop.sourceView = view
            pop.sourceRect = CGRect(x: view.bounds.midX, y: view.bounds.midY, width: 1, height: 1)
        }
        present(sheet, animated: true)
    }

    private func presentPhotoPicker() {
        var config = PHPickerConfiguration()
        // 0 = unlimited in PHPicker; cap to remaining library slots.
        config.selectionLimit = remainingFrameSlots
        config.filter = .images
        let picker = PHPickerViewController(configuration: config)
        picker.delegate = self
        present(picker, animated: true)
    }

    private func presentDocumentPicker() {
        let picker = UIDocumentPickerViewController(
            forOpeningContentTypes: [.png, .jpeg, .webP, .image]
        )
        picker.allowsMultipleSelection = true
        picker.delegate = self
        present(picker, animated: true)
    }

    /// Imports images in order until the library is full.
    private func ingest(_ images: [UIImage]) {
        guard !images.isEmpty else { return }
        let store = CameraFrameStore.shared
        var added = 0
        var stoppedForCapacity = false
        for image in images {
            if store.frames.count >= CameraFrameStore.maxFrameCount {
                stoppedForCapacity = true
                break
            }
            if store.add(image) != nil {
                added += 1
            }
        }
        if added == 0 {
            let alert = UIAlertController(
                title: "Couldn't Import Frames",
                message: "Use PNG images with transparency when possible.",
                preferredStyle: .alert
            )
            alert.addAction(UIAlertAction(title: "OK", style: .default))
            present(alert, animated: true)
        } else if stoppedForCapacity {
            let alert = UIAlertController(
                title: "Library Full",
                message: "Imported \(added). Remove frames to import more (max \(CameraFrameStore.maxFrameCount)).",
                preferredStyle: .alert
            )
            alert.addAction(UIAlertAction(title: "OK", style: .default))
            present(alert, animated: true)
        }
    }

    private func confirmDelete(_ id: UUID) {
        let alert = UIAlertController(
            title: "Delete Frame?",
            message: "This removes the overlay from your library.",
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(UIAlertAction(title: "Delete", style: .destructive) { _ in
            CameraFrameStore.shared.remove(id)
        })
        present(alert, animated: true)
    }
}

// MARK: - Collection

extension CameraFramePickerViewController: UICollectionViewDelegate {
    func collectionView(
        _ collectionView: UICollectionView,
        didSelectItemAt indexPath: IndexPath
    ) {
        collectionView.deselectItem(at: indexPath, animated: true)
        guard let item = dataSource.itemIdentifier(for: indexPath) else { return }
        switch item {
        case .none:
            CameraFrameStore.shared.select(nil)
        case .frame(let id):
            CameraFrameStore.shared.select(id)
        case .importFrames:
            importFrames()
        }
    }

    func collectionView(
        _ collectionView: UICollectionView,
        contextMenuConfigurationForItemAt indexPath: IndexPath,
        point: CGPoint
    ) -> UIContextMenuConfiguration? {
        guard let item = dataSource.itemIdentifier(for: indexPath),
              case .frame(let id) = item else { return nil }
        return UIContextMenuConfiguration(identifier: nil, previewProvider: nil) { [weak self] _ in
            let delete = UIAction(
                title: "Delete",
                image: UIImage(systemName: "trash"),
                attributes: .destructive
            ) { _ in
                self?.confirmDelete(id)
            }
            return UIMenu(children: [delete])
        }
    }
}

// MARK: - Pickers

extension CameraFramePickerViewController: PHPickerViewControllerDelegate {
    func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
        picker.dismiss(animated: true)
        guard !results.isEmpty else { return }

        let group = DispatchGroup()
        let lock = NSLock()
        var images: [UIImage] = []

        for result in results {
            let provider = result.itemProvider
            guard provider.canLoadObject(ofClass: UIImage.self) else { continue }
            group.enter()
            provider.loadObject(ofClass: UIImage.self) { object, _ in
                defer { group.leave() }
                guard let image = object as? UIImage else { return }
                lock.lock()
                images.append(image)
                lock.unlock()
            }
        }

        group.notify(queue: .main) { [weak self] in
            self?.ingest(images)
        }
    }
}

extension CameraFramePickerViewController: UIDocumentPickerDelegate {
    func documentPicker(
        _ controller: UIDocumentPickerViewController,
        didPickDocumentsAt urls: [URL]
    ) {
        var images: [UIImage] = []
        for url in urls {
            let access = url.startAccessingSecurityScopedResource()
            defer { if access { url.stopAccessingSecurityScopedResource() } }
            if let image = UIImage(contentsOfFile: url.path) {
                images.append(image)
            }
        }
        ingest(images)
    }
}

// MARK: - Cell

private final class FramePickerCell: UICollectionViewCell {
    static let reuseId = "FramePickerCell"

    private let imageView = UIImageView()
    private let iconView = UIImageView()
    private let titleLabel = UILabel()

    override init(frame: CGRect) {
        super.init(frame: frame)
        imageView.contentMode = .scaleAspectFit
        imageView.backgroundColor = UIColor(white: 0.12, alpha: 1)
        imageView.layer.cornerRadius = 10
        imageView.clipsToBounds = true
        imageView.translatesAutoresizingMaskIntoConstraints = false

        iconView.contentMode = .scaleAspectFit
        iconView.tintColor = .white
        iconView.translatesAutoresizingMaskIntoConstraints = false

        titleLabel.font = .systemFont(ofSize: 13, weight: .medium)
        titleLabel.textAlignment = .center
        titleLabel.translatesAutoresizingMaskIntoConstraints = false

        contentView.addSubview(imageView)
        imageView.addSubview(iconView)
        contentView.addSubview(titleLabel)

        NSLayoutConstraint.activate([
            imageView.topAnchor.constraint(equalTo: contentView.topAnchor),
            imageView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            imageView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            imageView.heightAnchor.constraint(
                equalTo: imageView.widthAnchor, multiplier: 16.0 / 9.0
            ),

            iconView.centerXAnchor.constraint(equalTo: imageView.centerXAnchor),
            iconView.centerYAnchor.constraint(equalTo: imageView.centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 28),
            iconView.heightAnchor.constraint(equalToConstant: 28),

            titleLabel.topAnchor.constraint(equalTo: imageView.bottomAnchor, constant: 6),
            titleLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            titleLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            titleLabel.bottomAnchor.constraint(
                lessThanOrEqualTo: contentView.bottomAnchor
            )
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(
        title: String,
        image: UIImage?,
        systemImage: String?,
        selected: Bool
    ) {
        titleLabel.text = title
        imageView.image = image
        if let systemImage {
            iconView.image = UIImage(systemName: systemImage)
            iconView.isHidden = false
        } else {
            iconView.image = nil
            iconView.isHidden = true
        }
        contentView.layer.borderWidth = selected ? 3 : 0
        contentView.layer.borderColor = UIColor.systemRed.cgColor
        contentView.layer.cornerRadius = 12
    }
}
