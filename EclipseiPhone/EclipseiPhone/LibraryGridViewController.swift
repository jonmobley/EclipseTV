// LibraryGridViewController.swift
import UIKit
import os

/// Two-column grid mirroring the Apple TV media library. Tapping an item asks the
/// Apple TV to make it live (fullscreen). Reads from `TVLibraryStore.shared`, which
/// is populated by `iPhoneConnectionManager`.
final class LibraryGridViewController: UIViewController {

    // MARK: - Properties

    let connectionManager: iPhoneConnectionManager
    let store = TVLibraryStore.shared
    private let logger = Logger(subsystem: "com.eclipseapp.ios", category: "LibraryGrid")

    /// Invoked when the user chooses to re-send a purged item from Photos. The host VC
    /// owns the picker flow and the `pendingRestoreId` handshake.
    var onRequestResend: ((String) -> Void)?

    private let sectionInset: CGFloat = 16
    private let interitemSpacing: CGFloat = 12
    private let headerInset: CGFloat = 16

    /// True while the user is dragging items to rearrange them.
    var isArranging = false
    /// Working copy of the library order used while arranging and until the Apple TV
    /// confirms the saved order with a fresh manifest. `nil` means show `store.items`.
    var arrangeItems: [LibraryItemDTO]?

    /// Long-press recognizer that drives interactive reordering; only active while
    /// arranging.
    lazy var reorderGesture: UILongPressGestureRecognizer = {
        let gesture = UILongPressGestureRecognizer(target: self, action: #selector(handleReorderGesture(_:)))
        gesture.isEnabled = false
        return gesture
    }()

    /// The order currently shown by the grid: the in-progress arrangement if any,
    /// otherwise the mirrored Apple TV order.
    var displayItems: [LibraryItemDTO] { arrangeItems ?? store.items }

    func displayItem(at index: Int) -> LibraryItemDTO? {
        let items = displayItems
        guard index >= 0 && index < items.count else { return nil }
        return items[index]
    }

    private let liveHeader: LiveHeaderView = {
        let header = LiveHeaderView()
        header.translatesAutoresizingMaskIntoConstraints = false
        return header
    }()

    lazy var collectionView: UICollectionView = {
        let layout = UICollectionViewFlowLayout()
        layout.minimumInteritemSpacing = interitemSpacing
        layout.minimumLineSpacing = interitemSpacing
        layout.sectionInset = UIEdgeInsets(top: sectionInset, left: sectionInset,
                                           bottom: sectionInset, right: sectionInset)
        let view = UICollectionView(frame: .zero, collectionViewLayout: layout)
        view.backgroundColor = .systemBackground
        view.alwaysBounceVertical = true
        view.register(LibraryThumbnailCell.self, forCellWithReuseIdentifier: LibraryThumbnailCell.reuseIdentifier)
        view.dataSource = self
        view.delegate = self
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    private let emptyLabel: UILabel = {
        let label = UILabel()
        label.text = "Nothing on Apple TV yet.\nSend a photo or video to get started."
        label.textColor = .secondaryLabel
        label.font = .systemFont(ofSize: 16)
        label.textAlignment = .center
        label.numberOfLines = 0
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    // MARK: - Init

    init(connectionManager: iPhoneConnectionManager) {
        self.connectionManager = connectionManager
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground

        liveHeader.onTogglePlayPause = { [weak self] in
            self?.connectionManager.sendPlaybackCommand(action: .toggle, position: nil)
        }
        liveHeader.onSkip = { [weak self] delta in
            self?.connectionManager.sendPlaybackCommand(action: .skip, position: delta)
        }
        liveHeader.onSeek = { [weak self] position in
            self?.connectionManager.sendPlaybackCommand(action: .seek, position: position)
        }

        collectionView.addGestureRecognizer(reorderGesture)

        view.addSubview(liveHeader)
        view.addSubview(collectionView)
        view.addSubview(emptyLabel)

        let safeArea = view.safeAreaLayoutGuide
        NSLayoutConstraint.activate([
            liveHeader.topAnchor.constraint(equalTo: safeArea.topAnchor, constant: headerInset),
            liveHeader.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: headerInset),
            liveHeader.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -headerInset),
            liveHeader.heightAnchor.constraint(equalTo: liveHeader.widthAnchor, multiplier: 9.0 / 16.0),

            collectionView.topAnchor.constraint(equalTo: liveHeader.bottomAnchor),
            collectionView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            collectionView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            collectionView.trailingAnchor.constraint(equalTo: view.trailingAnchor),

            emptyLabel.centerXAnchor.constraint(equalTo: collectionView.centerXAnchor),
            emptyLabel.centerYAnchor.constraint(equalTo: collectionView.centerYAnchor),
            emptyLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 40),
            emptyLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -40)
        ])
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        store.delegate = self
        collectionView.reloadData()
        updateEmptyState()
        refreshLiveHeader()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        if store.delegate === self {
            store.delegate = nil
        }
    }

    // MARK: - Helpers

    private func updateEmptyState() {
        if store.isEmpty {
            emptyLabel.text = store.isOnline
                ? "Nothing on Apple TV yet.\nSend a photo or video to get started."
                : "Not connected to Apple TV.\nNo saved library to show yet."
        }
        emptyLabel.isHidden = !store.isEmpty
    }

    /// Updates the fixed hero banner to reflect the currently live item (or a placeholder).
    private func refreshLiveHeader() {
        let liveItem = store.currentId.flatMap { id in
            store.items.first(where: { $0.id == id })
        }
        let thumbnail = liveItem.flatMap { store.thumbnail(for: $0.id) }
        liveHeader.configure(with: liveItem, thumbnail: thumbnail, isOnline: store.isOnline)
        liveHeader.updatePlayback(store.playback)
    }

    // MARK: - Per-item Options

    private func presentOptions(forItemId id: String) {
        guard let index = store.items.firstIndex(where: { $0.id == id }) else { return }
        let item = store.items[index]

        let sheet = UIAlertController(title: nil, message: nil, preferredStyle: .actionSheet)

        // Purged items can't play; only offer to re-send from Photos or remove them.
        if item.isAvailable == false {
            sheet.title = item.name
            sheet.message = "This item's file is no longer on the Apple TV."
            sheet.addAction(UIAlertAction(title: "Re-send from Photos", style: .default) { [weak self] _ in
                self?.onRequestResend?(id)
            })
            sheet.addAction(UIAlertAction(title: "Remove from Apple TV", style: .destructive) { [weak self] _ in
                self?.runCommand { self?.connectionManager.sendDeleteRequest(id: id) ?? false }
            })
            sheet.addAction(UIAlertAction(title: "Cancel", style: .cancel))
            if let popover = sheet.popoverPresentationController {
                let anchor = collectionView.cellForItem(at: IndexPath(item: index, section: 0)) ?? view
                popover.sourceView = anchor
                popover.sourceRect = anchor?.bounds ?? view.bounds
            }
            present(sheet, animated: true)
            return
        }

        sheet.addAction(UIAlertAction(title: "Make Live", style: .default) { [weak self] _ in
            self?.runCommand { self?.connectionManager.sendPlayRequest(id: id) ?? false }
        })

        if item.isVideo {
            let loopOn = item.isLooping ?? false
            sheet.addAction(UIAlertAction(title: loopOn ? "Turn Loop Off" : "Turn Loop On", style: .default) { [weak self] _ in
                self?.runCommand { self?.connectionManager.sendVideoSetting(id: id, isLooping: !loopOn, isMuted: nil) ?? false }
            })

            let muted = item.isMuted ?? false
            sheet.addAction(UIAlertAction(title: muted ? "Unmute" : "Mute", style: .default) { [weak self] _ in
                self?.runCommand { self?.connectionManager.sendVideoSetting(id: id, isLooping: nil, isMuted: !muted) ?? false }
            })
        }

        sheet.addAction(UIAlertAction(title: "Delete", style: .destructive) { [weak self] _ in
            self?.confirmDelete(id: id, name: item.name)
        })

        sheet.addAction(UIAlertAction(title: "Cancel", style: .cancel))

        // iPad requires a popover anchor.
        if let popover = sheet.popoverPresentationController {
            let indexPath = IndexPath(item: index, section: 0)
            let anchor = collectionView.cellForItem(at: indexPath) ?? view
            popover.sourceView = anchor
            popover.sourceRect = anchor?.bounds ?? view.bounds
        }

        present(sheet, animated: true)
    }

    private func confirmDelete(id: String, name: String) {
        let alert = UIAlertController(title: "Delete from Apple TV?",
                                      message: "This removes the item from your Apple TV library.",
                                      preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(UIAlertAction(title: "Delete", style: .destructive) { [weak self] _ in
            self?.runCommand { self?.connectionManager.sendDeleteRequest(id: id) ?? false }
        })
        present(alert, animated: true)
    }

    /// Runs a command closure; if it fails (not connected), surfaces a friendly alert.
    private func runCommand(_ command: () -> Bool) {
        if command() {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        } else {
            let alert = UIAlertController(title: "Not Connected",
                                          message: "Reconnect to your Apple TV and try again.",
                                          preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "OK", style: .default))
            present(alert, animated: true)
        }
    }

    private func itemSize(for width: CGFloat) -> CGSize {
        let columns: CGFloat = 2
        let totalSpacing = sectionInset * 2 + interitemSpacing * (columns - 1)
        let itemWidth = ((width - totalSpacing) / columns).rounded(.down)
        return CGSize(width: itemWidth, height: (itemWidth * 9 / 16).rounded(.down))
    }
}

// MARK: - UICollectionViewDataSource

extension LibraryGridViewController: UICollectionViewDataSource {
    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        return displayItems.count
    }

    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(
            withReuseIdentifier: LibraryThumbnailCell.reuseIdentifier, for: indexPath) as! LibraryThumbnailCell

        guard let item = displayItem(at: indexPath.item) else { return cell }
        cell.configure(with: item,
                       thumbnail: store.thumbnail(for: item.id),
                       isLive: item.id == store.currentId)
        return cell
    }
}

// MARK: - UICollectionViewDelegateFlowLayout

extension LibraryGridViewController: UICollectionViewDelegateFlowLayout {
    func collectionView(_ collectionView: UICollectionView,
                        layout collectionViewLayout: UICollectionViewLayout,
                        sizeForItemAt indexPath: IndexPath) -> CGSize {
        return itemSize(for: collectionView.bounds.width)
    }

    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        // While arranging, taps are reserved for drag-to-reorder.
        guard !isArranging else { return }
        guard let item = displayItem(at: indexPath.item) else { return }

        // A purged item can't be made live; surface its re-send / remove options instead.
        if item.isAvailable == false {
            presentOptions(forItemId: item.id)
            return
        }

        if connectionManager.sendPlayRequest(id: item.id) {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            // Optimistically reflect the new live item; the Apple TV will confirm.
            store.updateCurrentId(item.id)
        } else {
            let alert = UIAlertController(title: "Not Connected",
                                          message: "Reconnect to your Apple TV and try again.",
                                          preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "OK", style: .default))
            present(alert, animated: true)
        }
    }

    /// Long-pressing a thumbnail surfaces its options (the per-item actions that used
    /// to live behind the on-cell ellipsis button). Disabled while arranging, where the
    /// long press drives reordering instead.
    func collectionView(_ collectionView: UICollectionView,
                        contextMenuConfigurationForItemAt indexPath: IndexPath,
                        point: CGPoint) -> UIContextMenuConfiguration? {
        guard !isArranging, let item = displayItem(at: indexPath.item) else { return nil }
        return UIContextMenuConfiguration(identifier: nil, previewProvider: nil) { [weak self] _ in
            self?.optionsMenu(for: item)
        }
    }

    /// Builds the per-item options menu shown via long-press context menu.
    private func optionsMenu(for item: LibraryItemDTO) -> UIMenu {
        let id = item.id

        if item.isAvailable == false {
            let resend = UIAction(title: "Re-send from Photos",
                                  image: UIImage(systemName: "arrow.up.circle")) { [weak self] _ in
                self?.onRequestResend?(id)
            }
            let remove = UIAction(title: "Remove from Apple TV",
                                  image: UIImage(systemName: "trash"),
                                  attributes: .destructive) { [weak self] _ in
                self?.runCommand { self?.connectionManager.sendDeleteRequest(id: id) ?? false }
            }
            return UIMenu(title: item.name, children: [resend, remove])
        }

        // Tapping a thumbnail already makes it live, so that action is omitted here.
        var actions: [UIMenuElement] = []

        if item.isVideo {
            let loopOn = item.isLooping ?? false
            actions.append(UIAction(title: loopOn ? "Turn Loop Off" : "Turn Loop On",
                                    image: UIImage(systemName: "repeat")) { [weak self] _ in
                self?.runCommand { self?.connectionManager.sendVideoSetting(id: id, isLooping: !loopOn, isMuted: nil) ?? false }
            })

            let muted = item.isMuted ?? false
            actions.append(UIAction(title: muted ? "Unmute" : "Mute",
                                    image: UIImage(systemName: muted ? "speaker.slash" : "speaker.wave.2")) { [weak self] _ in
                self?.runCommand { self?.connectionManager.sendVideoSetting(id: id, isLooping: nil, isMuted: !muted) ?? false }
            })
        }

        let delete = UIAction(title: "Delete",
                              image: UIImage(systemName: "trash"),
                              attributes: .destructive) { [weak self] _ in
            self?.confirmDelete(id: id, name: item.name)
        }

        // Group the toggles (videos only) above the destructive Delete, omitting the
        // empty group for photos.
        var children: [UIMenuElement] = []
        if !actions.isEmpty {
            children.append(UIMenu(title: "", options: .displayInline, children: actions))
        }
        children.append(delete)
        return UIMenu(title: item.name, children: children)
    }
}

// MARK: - TVLibraryStoreDelegate

extension LibraryGridViewController: TVLibraryStoreDelegate {
    func libraryStoreDidUpdateItems(_ store: TVLibraryStore) {
        // While actively dragging, keep the working order; it reconciles on finish.
        guard !isArranging else { return }
        // A fresh manifest from the TV confirms any just-saved arrangement.
        arrangeItems = nil
        collectionView.reloadData()
        updateEmptyState()
        refreshLiveHeader()
    }

    func libraryStoreDidUpdateCurrent(_ store: TVLibraryStore) {
        refreshLiveHeader()
        guard !isArranging else { return }
        collectionView.reloadData()
    }

    func libraryStore(_ store: TVLibraryStore, didUpdateThumbnailFor id: String) {
        if id == store.currentId {
            refreshLiveHeader()
        }
        guard !isArranging,
              let index = displayItems.firstIndex(where: { $0.id == id }) else { return }
        let indexPath = IndexPath(item: index, section: 0)
        if collectionView.indexPathsForVisibleItems.contains(indexPath) {
            collectionView.reloadItems(at: [indexPath])
        }
    }

    func libraryStoreDidChangeConnection(_ store: TVLibraryStore) {
        updateEmptyState()
        refreshLiveHeader()
    }

    func libraryStoreDidUpdatePlayback(_ store: TVLibraryStore) {
        liveHeader.updatePlayback(store.playback)
    }
}
