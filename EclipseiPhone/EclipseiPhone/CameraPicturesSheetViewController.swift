//
//  CameraPicturesSheetViewController.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import UIKit

// MARK: - CameraPicturesSheetViewController

/// Camera-roll style sheet behind the camera's Pictures button: the Mac
/// show's Camera Kit and the phone's own frames and pictures in one place,
/// with + to add from Photos or the Eclipse Library.
///
/// Thread safety: main actor (UIKit).
final class CameraPicturesSheetViewController: UIViewController {

    // MARK: - Types

    /// What the sheet needs from the camera screen.
    struct Actions {
        var sections: () -> [CameraPicturesSection]
        var image: (CameraPictureEntry) -> UIImage?
        var isLive: (CameraPictureEntry) -> Bool
        var select: (CameraPictureEntry) -> Void
        var addMenu: () -> UIMenu?
        var editFrames: (() -> Void)?
    }

    // MARK: - Properties

    private let actions: Actions
    private var sections: [CameraPicturesSection] = []
    private let emptyLabel = UILabel()
    private lazy var collectionView = UICollectionView(frame: .zero, collectionViewLayout: makeLayout())
    private static let columns: CGFloat = 3
    private static let spacing: CGFloat = 10

    // MARK: - Initialization

    /// Creates the sheet.
    /// - Parameter actions: Camera screen callbacks.
    init(actions: Actions) {
        self.actions = actions
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Pictures"
        view.backgroundColor = .systemBackground
        setupCollection()
        setupEmptyLabel()
        observeStores()
        reload()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        collectionView.collectionViewLayout.invalidateLayout()
    }

    // MARK: - Public Interface

    /// Rebuilds sections and the bar buttons.
    @objc func reload() {
        sections = actions.sections()
        collectionView.reloadData()
        emptyLabel.isHidden = !sections.isEmpty
        navigationItem.rightBarButtonItem = actions.addMenu().map {
            UIBarButtonItem(systemItem: .add, menu: $0)
        }
        navigationItem.leftBarButtonItem = actions.editFrames.map { edit in
            UIBarButtonItem(title: "Edit Frames", primaryAction: UIAction { _ in edit() })
        }
    }

    // MARK: - Private Helpers

    private func setupCollection() {
        collectionView.backgroundColor = .clear
        collectionView.dataSource = self
        collectionView.delegate = self
        collectionView.register(CameraFrameRibbonCell.self, forCellWithReuseIdentifier: CameraFrameRibbonCell.reuseId)
        collectionView.register(
            CameraPicturesHeaderView.self,
            forSupplementaryViewOfKind: UICollectionView.elementKindSectionHeader,
            withReuseIdentifier: CameraPicturesHeaderView.reuseId
        )
        collectionView.frame = view.bounds
        collectionView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(collectionView)
    }

    private func setupEmptyLabel() {
        emptyLabel.text = "No frames or pictures yet. Tap + to add one."
        emptyLabel.textColor = .secondaryLabel
        emptyLabel.numberOfLines = 0
        emptyLabel.textAlignment = .center
        emptyLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(emptyLabel)
        NSLayoutConstraint.activate([
            emptyLabel.centerYAnchor.constraint(equalTo: view.safeAreaLayoutGuide.centerYAnchor),
            emptyLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 32),
            emptyLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -32)
        ])
    }

    private func observeStores() {
        let names: [Notification.Name] = [
            CameraKitStore.didChangeNotification,
            CameraFrameStore.didChangeNotification,
            CameraAlternateStillStore.didChangeNotification
        ]
        for name in names {
            NotificationCenter.default.addObserver(self, selector: #selector(reload), name: name, object: nil)
        }
    }

    private func makeLayout() -> UICollectionViewFlowLayout {
        let layout = UICollectionViewFlowLayout()
        layout.minimumLineSpacing = Self.spacing
        layout.minimumInteritemSpacing = Self.spacing
        layout.sectionInset = UIEdgeInsets(top: 6, left: 16, bottom: 18, right: 16)
        layout.headerReferenceSize = CGSize(width: 1, height: 30)
        return layout
    }
}

// MARK: - UICollectionViewDataSource & Delegate

extension CameraPicturesSheetViewController: UICollectionViewDataSource, UICollectionViewDelegateFlowLayout {

    func numberOfSections(in collectionView: UICollectionView) -> Int { sections.count }

    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        sections[section].entries.count
    }

    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        guard let cell = collectionView.dequeueReusableCell(
            withReuseIdentifier: CameraFrameRibbonCell.reuseId, for: indexPath
        ) as? CameraFrameRibbonCell else { return UICollectionViewCell() }
        let entry = sections[indexPath.section].entries[indexPath.item]
        cell.configure(image: actions.image(entry), isLive: actions.isLive(entry), isFrame: entry.isFrame)
        return cell
    }

    func collectionView(
        _ collectionView: UICollectionView,
        viewForSupplementaryElementOfKind kind: String,
        at indexPath: IndexPath
    ) -> UICollectionReusableView {
        let header = collectionView.dequeueReusableSupplementaryView(
            ofKind: kind, withReuseIdentifier: CameraPicturesHeaderView.reuseId, for: indexPath
        )
        (header as? CameraPicturesHeaderView)?.label.text = sections[indexPath.section].title
        return header
    }

    func collectionView(
        _ collectionView: UICollectionView,
        layout collectionViewLayout: UICollectionViewLayout,
        sizeForItemAt indexPath: IndexPath
    ) -> CGSize {
        let usable = collectionView.bounds.width - 32 - Self.spacing * (Self.columns - 1)
        let width = floor(max(1, usable) / Self.columns)
        return CGSize(width: width, height: width / ExternalOutputSettings.outputAspectRatio)
    }

    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        let entry = sections[indexPath.section].entries[indexPath.item]
        dismiss(animated: true) { [actions] in actions.select(entry) }
    }
}

// MARK: - CameraPicturesHeaderView

/// Section title in the Pictures sheet.
final class CameraPicturesHeaderView: UICollectionReusableView {
    static let reuseId = "CameraPicturesHeaderView"
    let label = UILabel()

    override init(frame: CGRect) {
        super.init(frame: frame)
        label.font = .preferredFont(forTextStyle: .headline)
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
            label.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -4)
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}
