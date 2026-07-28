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
        updateLeftBarButton()
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            barButtonSystemItem: .add, target: self, action: #selector(addTapped)
        )
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: cellReuseId)
        tableView.rowHeight = 56

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
        }
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(UIAlertAction(title: "Create", style: .default) { [weak self] _ in
            let name = alert.textFields?.first?.text ?? ""
            do {
                let playlist = try AudioPlaylistStore.shared.create(name: name)
                self?.openPlaylist(playlist)
            } catch {
                self?.presentError(error)
            }
        })
        present(alert, animated: true)
    }

    private func openPlaylist(_ playlist: AudioPlaylist) {
        let detail = AudioPlaylistDetailViewController(playlistId: playlist.id)
        navigationController?.pushViewController(detail, animated: true)
    }

    private func presentError(_ error: Error) {
        let alert = UIAlertController(
            title: "Couldn't Create Playlist",
            message: error.localizedDescription,
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        present(alert, animated: true)
    }

    private func formatDuration(_ seconds: TimeInterval) -> String {
        guard seconds.isFinite, seconds > 0 else { return "" }
        let total = Int(seconds.rounded())
        let m = total / 60
        let s = total % 60
        return String(format: "%d:%02d", m, s)
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
        cell.selectionStyle = .default

        switch Section(rawValue: indexPath.section)! {
        case .playlists:
            if playlistStore.playlists.isEmpty {
                config.text = "No playlists yet"
                config.secondaryText = "Tap + to create one"
                config.textProperties.color = .secondaryLabel
                cell.selectionStyle = .none
            } else {
                let playlist = playlistStore.playlists[indexPath.row]
                config.text = playlist.name
                let count = playlist.trackIds.count
                config.secondaryText = count == 1 ? "1 song" : "\(count) songs"
                config.image = UIImage(systemName: "music.note.list")
                cell.accessoryType = .disclosureIndicator
            }
        case .tracks:
            if trackStore.tracks.isEmpty {
                config.text = "No music yet"
                config.secondaryText = "Tap + to add a file"
                config.textProperties.color = .secondaryLabel
                cell.selectionStyle = .none
            } else {
                let track = trackStore.tracks[indexPath.row]
                config.text = track.title
                let duration = formatDuration(track.duration)
                if track.subtitle.isEmpty {
                    config.secondaryText = duration
                } else if duration.isEmpty {
                    config.secondaryText = track.subtitle
                } else {
                    config.secondaryText = "\(track.subtitle) · \(duration)"
                }
                config.image = UIImage(systemName: "music.note")
                if player.currentTrack?.id == track.id, player.isPlaying {
                    config.imageProperties.tintColor = .systemBlue
                }
            }
        }

        cell.contentConfiguration = config
        return cell
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
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
        case .playlists: return !playlistStore.playlists.isEmpty
        case .tracks: return !trackStore.tracks.isEmpty
        }
    }

    override func tableView(
        _ tableView: UITableView,
        trailingSwipeActionsConfigurationForRowAt indexPath: IndexPath
    ) -> UISwipeActionsConfiguration? {
        switch Section(rawValue: indexPath.section)! {
        case .playlists:
            guard !playlistStore.playlists.isEmpty else { return nil }
            let playlist = playlistStore.playlists[indexPath.row]
            let delete = UIContextualAction(style: .destructive, title: "Delete") { [weak self] _, _, done in
                self?.confirmDeletePlaylist(playlist, completion: done)
            }
            return UISwipeActionsConfiguration(actions: [delete])
        case .tracks:
            guard !trackStore.tracks.isEmpty else { return nil }
            let track = trackStore.tracks[indexPath.row]
            let delete = UIContextualAction(style: .destructive, title: "Delete") { [weak self] _, _, done in
                self?.confirmDeleteTrack(track, completion: done)
            }
            let add = UIContextualAction(style: .normal, title: "Add to…") { [weak self] _, _, done in
                self?.promptAddToPlaylist(trackId: track.id)
                done(true)
            }
            add.backgroundColor = .systemBlue
            return UISwipeActionsConfiguration(actions: [delete, add])
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
        guard Section(rawValue: indexPath.section) == .tracks,
              !trackStore.tracks.isEmpty else { return nil }
        let track = trackStore.tracks[indexPath.row]
        return UIContextMenuConfiguration(identifier: nil, previewProvider: nil) { [weak self] _ in
            let add = UIAction(
                title: "Add to Playlist",
                image: UIImage(systemName: "text.badge.plus")
            ) { _ in
                self?.promptAddToPlaylist(trackId: track.id)
            }
            let play = UIAction(
                title: "Play",
                image: UIImage(systemName: "play.fill")
            ) { _ in
                AudioPlayerController.shared.playAll(startingAt: track.id)
            }
            return UIMenu(children: [play, add])
        }
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
}
