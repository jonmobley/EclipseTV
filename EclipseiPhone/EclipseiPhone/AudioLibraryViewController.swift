//
//  AudioLibraryViewController.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import UIKit

/// Lists playlists and imported tracks for ambient music playback.
final class AudioLibraryViewController: UITableViewController {

    private enum Section: Int, CaseIterable {
        case playlists
        case tracks
    }

    private let trackStore = AudioStore.shared
    private let playlistStore = AudioPlaylistStore.shared
    private let player = AudioPlayerController.shared
    private let cellReuseId = "audioCell"
    /// When true, lives as the home Music page (swipe from Library) instead of a modal.
    private let isEmbedded: Bool
    private lazy var addBarButton = UIBarButtonItem(
        barButtonSystemItem: .add, target: self, action: #selector(addTapped)
    )

    var onAddMusic: (() -> Void)?
    /// Invoked by the embedded back control to return to the Library page.
    var onRequestClose: (() -> Void)?

    /// When false, hides the embedded Library back chevron (side-by-side home).
    var showsEmbeddedBackButton = true {
        didSet {
            guard showsEmbeddedBackButton != oldValue else { return }
            updateLeftBarButton()
        }
    }

    /// Extra bottom inset reserved for the home mini player.
    var miniPlayerBottomInset: CGFloat = 0 {
        didSet {
            guard miniPlayerBottomInset != oldValue else { return }
            tableView.contentInset.bottom = miniPlayerBottomInset
            tableView.verticalScrollIndicatorInsets.bottom = miniPlayerBottomInset
        }
    }

    // MARK: - Lifecycle

    /// - Parameter embedded: Home pager page (no Done); modal keeps a Done button.
    init(embedded: Bool = false) {
        self.isEmbedded = embedded
        super.init(style: .insetGrouped)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Music"
        navigationItem.largeTitleDisplayMode = .never
        updateLeftBarButton()
        updateRightBarButton()
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: cellReuseId)
        tableView.rowHeight = UITableView.automaticDimension
        tableView.estimatedRowHeight = 52
        editButtonItem.accessibilityHint = "Reorder tracks"

        let names: [Notification.Name] = [
            AudioStore.didChangeNotification,
            AudioPlaylistStore.didChangeNotification,
            AudioPlayerController.didChangeNotification
        ]
        for name in names {
            NotificationCenter.default.addObserver(
                self, selector: #selector(reload), name: name, object: nil
            )
        }
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        tableView.reloadData()
    }

    /// Configures Done (modal) or Library back (embedded pager) / none (split).
    private func updateLeftBarButton() {
        if isEmbedded {
            guard showsEmbeddedBackButton else {
                navigationItem.leftBarButtonItem = nil
                return
            }
            let back = UIBarButtonItem(
                image: UIImage(systemName: "chevron.left"),
                style: .plain,
                target: self,
                action: #selector(closeTapped)
            )
            back.accessibilityLabel = "Back to Home"
            navigationItem.leftBarButtonItem = back
        } else {
            navigationItem.leftBarButtonItem = UIBarButtonItem(
                barButtonSystemItem: .done, target: self, action: #selector(doneTapped)
            )
        }
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    // MARK: - Actions

    @objc private func doneTapped() {
        dismiss(animated: true)
    }

    @objc private func closeTapped() {
        onRequestClose?()
    }

    @objc private func reload() {
        guard isViewLoaded, tableView.window != nil else { return }
        tableView.reloadData()
    }

    @objc private func addTapped() {
        let sheet = UIAlertController(title: nil, message: nil, preferredStyle: .actionSheet)
        sheet.addAction(UIAlertAction(title: "Add Music", style: .default) { [weak self] _ in
            self?.onAddMusic?()
        })
        sheet.addAction(UIAlertAction(title: "New Playlist", style: .default) { [weak self] _ in
            self?.promptNewPlaylist()
        })
        sheet.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        if let popover = sheet.popoverPresentationController {
            popover.barButtonItem = navigationItem.rightBarButtonItem
        }
        present(sheet, animated: true)
    }

    private func promptNewPlaylist() {
        let alert = UIAlertController(
            title: "New Playlist", message: nil, preferredStyle: .alert
        )
        alert.addTextField {
            $0.placeholder = "Name"
            $0.autocapitalizationType = .words
            UserDisplayName.configureTextField($0)
        }
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(UIAlertAction(title: "Create", style: .default) { [weak self] _ in
            let name = alert.textFields?.first?.text ?? ""
            do {
                let playlist = try AudioPlaylistStore.shared.create(name: name)
                self?.openPlaylist(playlist)
            } catch {
                self?.presentError(error, title: "Couldn't Create Playlist")
            }
        })
        present(alert, animated: true)
    }

    private func openPlaylist(_ playlist: AudioPlaylist) {
        let detail = AudioPlaylistDetailViewController(playlistId: playlist.id)
        navigationController?.pushViewController(detail, animated: true)
    }

    private func presentError(_ error: Error, title: String = "Couldn't Save") {
        let alert = UIAlertController(
            title: title,
            message: error.localizedDescription,
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        present(alert, animated: true)
    }

    override func setEditing(_ editing: Bool, animated: Bool) {
        super.setEditing(editing, animated: animated)
        updateRightBarButton()
        tableView.reloadData()
    }

    private func updateRightBarButton() {
        navigationItem.rightBarButtonItem = isEditing ? editButtonItem : addBarButton
    }

    private func beginArrangingTracks() {
        guard trackStore.tracks.count >= 2 else { return }
        setEditing(true, animated: true)
    }

    // MARK: - Table

    override func numberOfSections(in tableView: UITableView) -> Int {
        Section.allCases.count
    }

    override func tableView(_ tableView: UITableView,
                            numberOfRowsInSection section: Int) -> Int {
        switch Section(rawValue: section)! {
        case .playlists:
            return max(playlistStore.playlists.count, 1)
        case .tracks:
            return max(trackStore.tracks.count, 1)
        }
    }

    override func tableView(_ tableView: UITableView,
                            titleForHeaderInSection section: Int) -> String? {
        switch Section(rawValue: section)! {
        case .playlists: return "Playlists"
        case .tracks: return "Tracks"
        }
    }

    override func tableView(_ tableView: UITableView,
                            cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: cellReuseId, for: indexPath)
        var config = cell.defaultContentConfiguration()
        cell.accessoryType = .none
        cell.accessoryView = nil
        cell.selectionStyle = .default
        cell.showsReorderControl = false

        switch Section(rawValue: indexPath.section)! {
        case .playlists:
            if playlistStore.playlists.isEmpty {
                config.text = "No playlists yet"
                config.textProperties.color = .secondaryLabel
                cell.selectionStyle = .none
            } else {
                let playlist = playlistStore.playlists[indexPath.row]
                let isCurrent = player.playlistId == playlist.id
                config.text = playlist.name
                config.secondaryText = nil
                config.image = UIImage(systemName: "music.note.list")
                applyNowPlayingStyle(&config, isCurrent: isCurrent)
                if !isEditing {
                    cell.accessoryView = AudioMusicRowViews.playlistAccessory(
                        songCount: playlist.trackIds.count
                    )
                }
            }
        case .tracks:
            if trackStore.tracks.isEmpty {
                config.text = "No music yet"
                config.textProperties.color = .secondaryLabel
                cell.selectionStyle = .none
            } else {
                let track = trackStore.tracks[indexPath.row]
                let isCurrent = player.currentTrack?.id == track.id
                config.text = track.title
                config.secondaryText = track.subtitle.isEmpty ? nil : track.subtitle
                let symbol = isCurrent && player.isPlaying
                    ? "speaker.wave.2.fill" : "music.note"
                config.image = UIImage(systemName: symbol)
                applyNowPlayingStyle(&config, isCurrent: isCurrent)
                cell.showsReorderControl = isEditing
                if isEditing {
                    cell.accessoryView = AudioMusicRowViews.durationAccessory(
                        duration: track.duration
                    )
                } else {
                    cell.accessoryView = AudioMusicRowViews.trackAccessory(
                        duration: track.duration,
                        menu: trackMoreMenu(for: track)
                    )
                }
            }
        }

        cell.contentConfiguration = config
        return cell
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        guard !isEditing else { return }
        switch Section(rawValue: indexPath.section)! {
        case .playlists:
            guard !playlistStore.playlists.isEmpty else { return }
            openPlaylist(playlistStore.playlists[indexPath.row])
        case .tracks:
            guard !trackStore.tracks.isEmpty else { return }
            let track = trackStore.tracks[indexPath.row]
            player.playAll(startingAt: track.id)
        }
    }

    override func tableView(_ tableView: UITableView,
                            canEditRowAt indexPath: IndexPath) -> Bool {
        switch Section(rawValue: indexPath.section)! {
        case .playlists:
            guard !isEditing else { return false }
            guard !playlistStore.playlists.isEmpty else { return false }
            return !playlistStore.playlists[indexPath.row].isProtected
        case .tracks:
            guard !trackStore.tracks.isEmpty else { return false }
            return true
        }
    }

    override func tableView(
        _ tableView: UITableView,
        editingStyleForRowAt indexPath: IndexPath
    ) -> UITableViewCell.EditingStyle {
        // Arrange is reorder-only; delete stays on ⋯ / swipe.
        .none
    }

    override func tableView(
        _ tableView: UITableView,
        shouldIndentWhileEditingRowAt indexPath: IndexPath
    ) -> Bool {
        false
    }

    override func tableView(_ tableView: UITableView,
                            canMoveRowAt indexPath: IndexPath) -> Bool {
        isEditing
            && Section(rawValue: indexPath.section) == .tracks
            && trackStore.tracks.count >= 2
    }

    override func tableView(
        _ tableView: UITableView,
        moveRowAt sourceIndexPath: IndexPath,
        to destinationIndexPath: IndexPath
    ) {
        guard Section(rawValue: sourceIndexPath.section) == .tracks,
              Section(rawValue: destinationIndexPath.section) == .tracks
        else { return }
        var ids = trackStore.tracks.map(\.id)
        let moved = ids.remove(at: sourceIndexPath.row)
        ids.insert(moved, at: destinationIndexPath.row)
        trackStore.reorder(trackIds: ids)
    }

    override func tableView(
        _ tableView: UITableView,
        targetIndexPathForMoveFromRowAt sourceIndexPath: IndexPath,
        toProposedIndexPath proposedIndexPath: IndexPath
    ) -> IndexPath {
        guard Section(rawValue: proposedIndexPath.section) == .tracks else {
            return IndexPath(
                row: sourceIndexPath.row,
                section: Section.tracks.rawValue
            )
        }
        return proposedIndexPath
    }

    override func tableView(
        _ tableView: UITableView,
        trailingSwipeActionsConfigurationForRowAt indexPath: IndexPath
    ) -> UISwipeActionsConfiguration? {
        switch Section(rawValue: indexPath.section)! {
        case .playlists:
            guard !playlistStore.playlists.isEmpty else { return nil }
            let playlist = playlistStore.playlists[indexPath.row]
            guard !playlist.isProtected else { return nil }
            let delete = UIContextualAction(style: .destructive, title: "Delete") { [weak self] _, _, done in
                self?.confirmDeletePlaylist(playlist, completion: done)
            }
            return UISwipeActionsConfiguration(actions: [delete])
        case .tracks:
            guard !trackStore.tracks.isEmpty else { return nil }
            let track = trackStore.tracks[indexPath.row]
            var actions: [UIContextualAction] = []
            if !track.isProtected {
                let delete = UIContextualAction(style: .destructive, title: "Delete") { [weak self] _, _, done in
                    self?.confirmDeleteTrack(track, completion: done)
                }
                actions.append(delete)
            }
            let add = UIContextualAction(style: .normal, title: "Add to…") { [weak self] _, _, done in
                self?.promptAddToPlaylist(trackId: track.id)
                done(true)
            }
            add.backgroundColor = .systemBlue
            actions.append(add)
            return UISwipeActionsConfiguration(actions: actions)
        }
    }

    private func confirmDeletePlaylist(
        _ playlist: AudioPlaylist,
        completion: @escaping (Bool) -> Void
    ) {
        let alert = UIAlertController(
            title: "Delete Playlist?",
            message: "“\(playlist.name)” will be removed. Tracks stay in Music.",
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel) { _ in
            completion(false)
        })
        alert.addAction(UIAlertAction(title: "Delete", style: .destructive) { _ in
            AudioPlaylistStore.shared.delete(id: playlist.id)
            completion(true)
        })
        present(alert, animated: true)
    }

    private func confirmDeleteTrack(
        _ track: AudioTrack,
        completion: @escaping (Bool) -> Void
    ) {
        let alert = UIAlertController(
            title: "Delete Track?",
            message: "“\(track.title)” will be removed from Music.",
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel) { _ in
            completion(false)
        })
        alert.addAction(UIAlertAction(title: "Delete", style: .destructive) { _ in
            AudioStore.shared.remove(id: track.id)
            completion(true)
        })
        present(alert, animated: true)
    }

    override func tableView(
        _ tableView: UITableView,
        contextMenuConfigurationForRowAt indexPath: IndexPath,
        point: CGPoint
    ) -> UIContextMenuConfiguration? {
        switch Section(rawValue: indexPath.section)! {
        case .playlists:
            guard !playlistStore.playlists.isEmpty else { return nil }
            let playlist = playlistStore.playlists[indexPath.row]
            return UIContextMenuConfiguration(identifier: nil, previewProvider: nil) {
                [weak self] _ in
                let open = UIAction(
                    title: "Open",
                    image: UIImage(systemName: "music.note.list")
                ) { _ in
                    self?.openPlaylist(playlist)
                }
                var children: [UIMenuElement] = [open]
                if !playlist.isProtected {
                    let rename = UIAction(
                        title: "Rename",
                        image: UIImage(systemName: "pencil")
                    ) { _ in
                        self?.promptRenamePlaylist(playlist)
                    }
                    let delete = UIAction(
                        title: "Delete",
                        image: UIImage(systemName: "trash"),
                        attributes: .destructive
                    ) { _ in
                        self?.confirmDeletePlaylist(playlist) { _ in }
                    }
                    children.append(contentsOf: [rename, delete])
                }
                return UIMenu(children: children)
            }
        case .tracks:
            guard !trackStore.tracks.isEmpty, !isEditing else { return nil }
            let track = trackStore.tracks[indexPath.row]
            return UIContextMenuConfiguration(identifier: nil, previewProvider: nil) {
                [weak self] _ in
                self?.trackMoreMenu(for: track)
            }
        }
    }

    /// ⋯ / long-press menu for a library track (Play is row tap, not listed here).
    private func trackMoreMenu(for track: AudioTrack) -> UIMenu {
        let arrange = UIAction(
            title: "Arrange",
            image: UIImage(systemName: "arrow.up.arrow.down"),
            attributes: trackStore.tracks.count < 2 ? [.disabled] : []
        ) { [weak self] _ in
            self?.beginArrangingTracks()
        }
        let add = UIAction(
            title: "Add to Playlist",
            image: UIImage(systemName: "text.badge.plus")
        ) { [weak self] _ in
            self?.promptAddToPlaylist(trackId: track.id)
        }
        var children: [UIMenuElement] = [arrange, add]
        if !track.isProtected {
            let rename = UIAction(
                title: "Rename",
                image: UIImage(systemName: "pencil")
            ) { [weak self] _ in
                self?.promptRenameTrack(track)
            }
            let delete = UIAction(
                title: "Delete",
                image: UIImage(systemName: "trash"),
                attributes: .destructive
            ) { [weak self] _ in
                self?.confirmDeleteTrack(track) { _ in }
            }
            children.append(contentsOf: [rename, delete])
        }
        return UIMenu(children: children)
    }

    private func promptRenameTrack(_ track: AudioTrack) {
        let alert = UIAlertController(
            title: "Rename", message: nil, preferredStyle: .alert
        )
        alert.addTextField {
            $0.text = track.title
            $0.autocapitalizationType = .words
            $0.clearButtonMode = .whileEditing
            UserDisplayName.configureTextField($0)
        }
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(UIAlertAction(title: "Save", style: .default) { [weak self] _ in
            let name = alert.textFields?.first?.text ?? ""
            do {
                try AudioStore.shared.rename(id: track.id, to: name)
            } catch {
                self?.presentError(error, title: "Couldn't Rename")
            }
        })
        present(alert, animated: true)
    }

    private func promptRenamePlaylist(_ playlist: AudioPlaylist) {
        let alert = UIAlertController(
            title: "Rename Playlist", message: nil, preferredStyle: .alert
        )
        alert.addTextField {
            $0.text = playlist.name
            $0.autocapitalizationType = .words
            $0.clearButtonMode = .whileEditing
            UserDisplayName.configureTextField($0)
        }
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(UIAlertAction(title: "Save", style: .default) { [weak self] _ in
            let name = alert.textFields?.first?.text ?? ""
            do {
                try AudioPlaylistStore.shared.rename(id: playlist.id, to: name)
            } catch {
                self?.presentError(error, title: "Couldn't Rename")
            }
        })
        present(alert, animated: true)
    }

    private func promptAddToPlaylist(trackId: UUID) {
        let playlists = playlistStore.playlists
        guard !playlists.isEmpty else {
            promptNewPlaylist()
            return
        }
        let sheet = UIAlertController(
            title: "Add to Playlist", message: nil, preferredStyle: .actionSheet
        )
        for playlist in playlists {
            sheet.addAction(UIAlertAction(title: playlist.name, style: .default) { _ in
                AudioPlaylistStore.shared.add(trackId: trackId, toPlaylistId: playlist.id)
            })
        }
        sheet.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        if let popover = sheet.popoverPresentationController {
            popover.sourceView = tableView
            popover.sourceRect = CGRect(
                x: tableView.bounds.midX, y: tableView.bounds.midY, width: 1, height: 1
            )
            popover.permittedArrowDirections = []
        }
        present(sheet, animated: true)
    }

    /// Blues + semibold for the active playlist / track row.
    private func applyNowPlayingStyle(
        _ config: inout UIListContentConfiguration,
        isCurrent: Bool
    ) {
        let body = UIFont.preferredFont(forTextStyle: .body)
        if isCurrent {
            config.textProperties.color = .systemBlue
            config.textProperties.font = .systemFont(ofSize: body.pointSize, weight: .semibold)
            config.secondaryTextProperties.color = UIColor.systemBlue.withAlphaComponent(0.7)
            config.imageProperties.tintColor = .systemBlue
        } else {
            config.textProperties.color = .label
            config.textProperties.font = body
            config.secondaryTextProperties.color = .secondaryLabel
            config.imageProperties.tintColor = .secondaryLabel
        }
    }
}
