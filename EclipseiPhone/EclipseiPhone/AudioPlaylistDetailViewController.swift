//
//  AudioPlaylistDetailViewController.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import UIKit

/// Shows and reorders tracks in a single playlist.
final class AudioPlaylistDetailViewController: UITableViewController {

    private let playlistId: UUID
    private let cellReuseId = "playlistTrackCell"

    private var playlist: AudioPlaylist? {
        AudioPlaylistStore.shared.playlist(id: playlistId)
    }

    private var tracks: [AudioTrack] {
        guard let playlist else { return [] }
        return playlist.trackIds.compactMap { AudioStore.shared.track(id: $0) }
    }

    /// Extra air under a large navigation title (phone). Inline titles skip this.
    private static let largeTitleSectionPadding: CGFloat = 28
    private static let inlineTitleSectionPadding: CGFloat = 8

    /// Creates a detail screen for `playlistId`.
    init(playlistId: UUID) {
        self.playlistId = playlistId
        super.init(style: .insetGrouped)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// Large titles on compact (phone) width; inline on the iPad Music sidebar.
    static func usesLargeTitle(horizontalSizeClass: UIUserInterfaceSizeClass) -> Bool {
        horizontalSizeClass == .compact
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: cellReuseId)
        tableView.rowHeight = UITableView.automaticDimension
        tableView.estimatedRowHeight = 52
        editButtonItem.accessibilityHint = "Reorder songs"
        applyTitleMetrics()
        updateChrome()
        registerForTraitChanges(
            [UITraitHorizontalSizeClass.self]
        ) { (self: Self, _: UITraitCollection) in
            self.applyTitleMetrics()
        }

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(reload),
            name: AudioPlaylistStore.didChangeNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(reload),
            name: AudioStore.didChangeNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(reload),
            name: AudioPlayerController.didChangeNotification,
            object: nil
        )
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        applyTitleMetrics()
    }

    /// Compact width keeps the large playlist name; regular width (iPad sidebar)
    /// uses an inline nav title so the type does not dominate the pane.
    private func applyTitleMetrics() {
        let large = Self.usesLargeTitle(
            horizontalSizeClass: traitCollection.horizontalSizeClass
        )
        navigationItem.largeTitleDisplayMode = large ? .always : .never
        navigationController?.navigationBar.prefersLargeTitles = large
        tableView.sectionHeaderTopPadding = large
            ? Self.largeTitleSectionPadding
            : Self.inlineTitleSectionPadding
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    @objc private func reload() {
        updateChrome()
        tableView.reloadData()
        if playlist == nil {
            navigationController?.popViewController(animated: true)
        }
    }

    /// Playlist name and trailing Play / Edit controls.
    private func updateChrome() {
        title = playlist?.name ?? "Playlist"
        let play = UIBarButtonItem(
            image: UIImage(systemName: "play.fill"),
            style: .plain,
            target: self,
            action: #selector(playAllTapped)
        )
        play.isEnabled = !tracks.isEmpty
        play.accessibilityLabel = "Play playlist"
        if tracks.isEmpty {
            if isEditing { setEditing(false, animated: false) }
            navigationItem.rightBarButtonItems = [play]
        } else if isEditing {
            navigationItem.rightBarButtonItems = [editButtonItem, play]
        } else {
            navigationItem.rightBarButtonItems = [editButtonItem, play]
        }
    }

    @objc private func playAllTapped() {
        guard let playlist, !tracks.isEmpty else { return }
        AudioPlayerController.shared.playPlaylist(playlist)
    }

    override func setEditing(_ editing: Bool, animated: Bool) {
        super.setEditing(editing, animated: animated)
        updateChrome()
        tableView.reloadData()
    }

    private func beginArranging() {
        guard tracks.count >= 2 else { return }
        setEditing(true, animated: true)
    }

    // MARK: - Table

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        max(tracks.count, 1)
    }

    override func tableView(_ tableView: UITableView,
                            cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: cellReuseId, for: indexPath)
        var config = cell.defaultContentConfiguration()
        cell.accessoryType = .none
        cell.accessoryView = nil
        cell.showsReorderControl = false
        if tracks.isEmpty {
            config.text = "No songs yet"
            config.secondaryText = "Add tracks from the Music list"
            config.textProperties.color = .secondaryLabel
            cell.selectionStyle = .none
        } else {
            let track = tracks[indexPath.row]
            let player = AudioPlayerController.shared
            let isCurrent = player.currentTrack?.id == track.id
            config.text = track.title
            config.secondaryText = track.subtitle.isEmpty ? nil : track.subtitle
            let symbol = isCurrent && player.isPlaying
                ? "speaker.wave.2.fill" : "music.note"
            config.image = UIImage(systemName: symbol)
            applyNowPlayingStyle(&config, isCurrent: isCurrent)
            cell.selectionStyle = isEditing ? .none : .default
            cell.showsReorderControl = isEditing && canMoveRow(at: indexPath)
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
        cell.contentConfiguration = config
        return cell
    }

    private func canMoveRow(at indexPath: IndexPath) -> Bool {
        tracks.count >= 2 && tracks.indices.contains(indexPath.row)
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        guard !isEditing, let playlist, !tracks.isEmpty else { return }
        let track = tracks[indexPath.row]
        let player = AudioPlayerController.shared
        if player.tapStopsPlayback(for: track.id) {
            player.stop()
        } else {
            player.playPlaylist(playlist, startingAt: track.id)
        }
    }

    override func tableView(_ tableView: UITableView,
                            canEditRowAt indexPath: IndexPath) -> Bool {
        !tracks.isEmpty
    }

    override func tableView(
        _ tableView: UITableView,
        editingStyleForRowAt indexPath: IndexPath
    ) -> UITableViewCell.EditingStyle {
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
        isEditing && canMoveRow(at: indexPath)
    }

    override func tableView(
        _ tableView: UITableView,
        moveRowAt sourceIndexPath: IndexPath,
        to destinationIndexPath: IndexPath
    ) {
        guard let playlist else { return }
        var ids = playlist.trackIds.filter { AudioStore.shared.track(id: $0) != nil }
        let item = ids.remove(at: sourceIndexPath.row)
        ids.insert(item, at: destinationIndexPath.row)
        AudioPlaylistStore.shared.reorder(trackIds: ids, inPlaylistId: playlistId)
    }

    override func tableView(
        _ tableView: UITableView,
        trailingSwipeActionsConfigurationForRowAt indexPath: IndexPath
    ) -> UISwipeActionsConfiguration? {
        guard !tracks.isEmpty, !isEditing else { return nil }
        let track = tracks[indexPath.row]
        if playlist?.isProtected == true, track.isProtected { return nil }
        let remove = UIContextualAction(style: .destructive, title: "Remove") { _, _, done in
            AudioPlaylistStore.shared.remove(
                trackId: track.id, fromPlaylistId: self.playlistId
            )
            done(true)
        }
        return UISwipeActionsConfiguration(actions: [remove])
    }

    override func tableView(
        _ tableView: UITableView,
        contextMenuConfigurationForRowAt indexPath: IndexPath,
        point: CGPoint
    ) -> UIContextMenuConfiguration? {
        guard !tracks.isEmpty, !isEditing else { return nil }
        let track = tracks[indexPath.row]
        return UIContextMenuConfiguration(identifier: nil, previewProvider: nil) {
            [weak self] _ in
            self?.trackMoreMenu(for: track)
        }
    }

    /// ⋯ menu: Arrange / Add to Playlist / Delete (remove from this playlist).
    private func trackMoreMenu(for track: AudioTrack) -> UIMenu {
        let arrange = UIAction(
            title: "Arrange",
            image: UIImage(systemName: "arrow.up.arrow.down"),
            attributes: tracks.count < 2 ? [.disabled] : []
        ) { [weak self] _ in
            self?.beginArranging()
        }
        let add = UIAction(
            title: "Add to Playlist",
            image: UIImage(systemName: "text.badge.plus")
        ) { [weak self] _ in
            self?.promptAddToPlaylist(trackId: track.id)
        }
        var children: [UIMenuElement] = [arrange, add]
        let canRemove = !(playlist?.isProtected == true && track.isProtected)
        if canRemove {
            let delete = UIAction(
                title: "Delete",
                image: UIImage(systemName: "trash"),
                attributes: .destructive
            ) { [weak self] _ in
                guard let self else { return }
                AudioPlaylistStore.shared.remove(
                    trackId: track.id, fromPlaylistId: self.playlistId
                )
            }
            children.append(delete)
        }
        return UIMenu(children: children)
    }

    private func promptAddToPlaylist(trackId: UUID) {
        let playlists = AudioPlaylistStore.shared.playlists
        guard !playlists.isEmpty else { return }
        let sheet = UIAlertController(
            title: "Add to Playlist", message: nil, preferredStyle: .actionSheet
        )
        for playlist in playlists {
            sheet.addAction(UIAlertAction(title: playlist.name, style: .default) { _ in
                AudioPlaylistStore.shared.add(
                    trackId: trackId, toPlaylistId: playlist.id
                )
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
