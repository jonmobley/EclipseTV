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

    /// Creates a detail screen for `playlistId`.
    init(playlistId: UUID) {
        self.playlistId = playlistId
        super.init(style: .insetGrouped)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = playlist?.name ?? "Playlist"
        let play = UIBarButtonItem(
            image: UIImage(systemName: "play.fill"),
            style: .plain,
            target: self,
            action: #selector(playAllTapped)
        )
        navigationItem.rightBarButtonItems = [editButtonItem, play]
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: cellReuseId)
        tableView.rowHeight = 56

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
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    @objc private func reload() {
        title = playlist?.name ?? "Playlist"
        tableView.reloadData()
        if playlist == nil {
            navigationController?.popViewController(animated: true)
        }
    }

    @objc private func playAllTapped() {
        guard let playlist, !tracks.isEmpty else { return }
        AudioPlayerController.shared.playPlaylist(playlist)
    }

    // MARK: - Table

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        max(tracks.count, 1)
    }

    override func tableView(_ tableView: UITableView,
                            cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: cellReuseId, for: indexPath)
        var config = cell.defaultContentConfiguration()
        if tracks.isEmpty {
            config.text = "No songs yet"
            config.secondaryText = "Add tracks from the Music list"
            config.textProperties.color = .secondaryLabel
            cell.selectionStyle = .none
        } else {
            let track = tracks[indexPath.row]
            config.text = track.title
            config.secondaryText = track.subtitle.isEmpty ? nil : track.subtitle
            config.image = UIImage(systemName: "music.note")
            cell.selectionStyle = .default
        }
        cell.contentConfiguration = config
        return cell
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        guard let playlist, !tracks.isEmpty else { return }
        let track = tracks[indexPath.row]
        AudioPlayerController.shared.playPlaylist(playlist, startingAt: track.id)
    }

    override func tableView(_ tableView: UITableView,
                            canEditRowAt indexPath: IndexPath) -> Bool {
        !tracks.isEmpty
    }

    override func tableView(_ tableView: UITableView,
                            canMoveRowAt indexPath: IndexPath) -> Bool {
        !tracks.isEmpty
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
        commit editingStyle: UITableViewCell.EditingStyle,
        forRowAt indexPath: IndexPath
    ) {
        guard editingStyle == .delete, !tracks.isEmpty else { return }
        let track = tracks[indexPath.row]
        AudioPlaylistStore.shared.remove(trackId: track.id, fromPlaylistId: playlistId)
    }

    override func tableView(
        _ tableView: UITableView,
        trailingSwipeActionsConfigurationForRowAt indexPath: IndexPath
    ) -> UISwipeActionsConfiguration? {
        guard !tracks.isEmpty else { return nil }
        let track = tracks[indexPath.row]
        let remove = UIContextualAction(style: .destructive, title: "Remove") { _, _, done in
            AudioPlaylistStore.shared.remove(
                trackId: track.id, fromPlaylistId: self.playlistId
            )
            done(true)
        }
        return UISwipeActionsConfiguration(actions: [remove])
    }
}
