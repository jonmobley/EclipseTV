//
//  CameraFramePickerViewController.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import UIKit
import PhotosUI
import UniformTypeIdentifiers

/// Drawer to choose which frames appear on the camera overlay ribbon.
///
/// Tapping a frame pins or unpins it as a thumbnail option. It does not make
/// the overlay live — that happens on the camera ribbon. Add and delete stay
/// here.
final class CameraFramePickerViewController: UIViewController {

    private enum Item: Hashable {
        case frame(UUID)
        case addFrames
    }

    private var items: [Item] = []
    private var dataSource: UICollectionViewDiffableDataSource<Int, Item>!
    private var collectionView: UICollectionView!

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        title = "Camera Frames"
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
            CameraFramePickerCell.self,
            forCellWithReuseIdentifier: CameraFramePickerCell.reuseId
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
            guard let cell = collectionView.dequeueReusableCell(
                withReuseIdentifier: CameraFramePickerCell.reuseId,
                for: indexPath
            ) as? CameraFramePickerCell else {
                return UICollectionViewCell()
            }
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
        // Thumbnail aspect matches the active Display Mode card.
        let aspect = orientation.gridCellHeightOverWidth
        layout.itemSize = CGSize(width: side, height: side * aspect + 28)
    }

    // MARK: - Data

    private func reload() {
        let store = CameraFrameStore.shared
        items = store.frames.map { .frame($0.id) } + [.addFrames]
        let previous = Set(dataSource.snapshot().itemIdentifiers)
        var snapshot = NSDiffableDataSourceSnapshot<Int, Item>()
        snapshot.appendSections([0])
        snapshot.appendItems(items)
        let toReload = items.filter { previous.contains($0) }
        if !toReload.isEmpty {
            snapshot.reloadItems(toReload)
        }
        dataSource.apply(snapshot, animatingDifferences: true)
    }

    private func configure(_ cell: CameraFramePickerCell, with item: Item) {
        let store = CameraFrameStore.shared
        switch item {
        case .frame(let id):
            cell.configureFrame(
                image: store.image(for: id),
                selected: store.isEnabled(id),
                moreMenu: frameMoreMenu(for: id)
            )
        case .addFrames:
            cell.configureAdd(menu: addFramesMenu())
        }
    }

    /// Show-style ⋯ menu: rotate and delete.
    private func frameMoreMenu(for id: UUID) -> UIMenu {
        let rotateRight = UIAction(
            title: "Rotate Right",
            image: UIImage(systemName: "rotate.right")
        ) { _ in
            CameraFrameStore.shared.rotateClockwise(id)
        }
        let rotateLeft = UIAction(
            title: "Rotate Left",
            image: UIImage(systemName: "rotate.left")
        ) { _ in
            CameraFrameStore.shared.rotateCounterclockwise(id)
        }
        let delete = UIAction(
            title: "Delete",
            image: UIImage(systemName: "trash"),
            attributes: .destructive
        ) { [weak self] _ in
            self?.confirmDelete(id)
        }
        return UIMenu(children: [rotateRight, rotateLeft, delete])
    }

    /// Pull-down on the Add tile (Photo Library / Files).
    private func addFramesMenu() -> UIMenu {
        let photos = UIAction(
            title: "Photo Library",
            image: UIImage(systemName: "photo.on.rectangle")
        ) { [weak self] _ in
            self?.addFramesFromPhotoLibrary()
        }
        let files = UIAction(
            title: "Files",
            image: UIImage(systemName: "folder")
        ) { [weak self] _ in
            self?.addFramesFromFiles()
        }
        return UIMenu(children: [photos, files])
    }

    // MARK: - Actions

    @objc private func doneTapped() {
        dismiss(animated: true)
    }

    @objc private func storeChanged() {
        reload()
    }

    private var remainingFrameSlots: Int {
        CameraFrameStore.shared.remainingSlots
    }

    /// Capacity gate shared by Add menu actions.
    @discardableResult
    private func ensureFrameCapacity() -> Bool {
        guard remainingFrameSlots > 0 else {
            let mode = ExternalOutputSettings.orientation.rawValue
            let alert = UIAlertController(
                title: "Frame Library Full",
                message: "Remove a \(mode) frame before adding more "
                    + "(max \(CameraFrameStore.maxFrameCount) per mode).",
                preferredStyle: .alert
            )
            alert.addAction(UIAlertAction(title: "OK", style: .default))
            present(alert, animated: true)
            return false
        }
        return true
    }

    private func addFramesFromPhotoLibrary() {
        guard ensureFrameCapacity() else { return }
        presentPhotoPicker()
    }

    private func addFramesFromFiles() {
        guard ensureFrameCapacity() else { return }
        presentDocumentPicker()
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
            if store.remainingSlots == 0 {
                stoppedForCapacity = true
                break
            }
            if store.add(image) != nil {
                added += 1
            }
        }
        if added == 0 {
            let alert = UIAlertController(
                title: "Couldn't Add Frames",
                message: "Use PNG images with transparency when possible.",
                preferredStyle: .alert
            )
            alert.addAction(UIAlertAction(title: "OK", style: .default))
            present(alert, animated: true)
        } else if stoppedForCapacity {
            let mode = ExternalOutputSettings.orientation.rawValue
            let alert = UIAlertController(
                title: "Library Full",
                message: "Added \(added). Remove \(mode) frames to add more "
                    + "(max \(CameraFrameStore.maxFrameCount) per mode).",
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
        case .frame(let id):
            CameraFrameStore.shared.toggleEnabled(id)
        case .addFrames:
            // Add tile uses a primary pull-down menu; ignore selection.
            break
        }
    }

    func collectionView(
        _ collectionView: UICollectionView,
        contextMenuConfigurationForItemAt indexPath: IndexPath,
        point: CGPoint
    ) -> UIContextMenuConfiguration? {
        // Keep long-press as a duplicate of the ⋯ menu for power users.
        guard let item = dataSource.itemIdentifier(for: indexPath),
              case .frame(let id) = item else { return nil }
        return UIContextMenuConfiguration(identifier: nil, previewProvider: nil) { [weak self] _ in
            self?.frameMoreMenu(for: id)
        }
    }
}

// MARK: - Pickers

extension CameraFramePickerViewController: PHPickerViewControllerDelegate {
    func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
        // Load after dismiss so capacity alerts aren't presented on a dismissing picker.
        picker.dismiss(animated: true) { [weak self] in
            self?.importPickedFrameImages(results)
        }
    }

    private func importPickedFrameImages(_ results: [PHPickerResult]) {
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
