//
//  AllShowsViewController.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import UIKit

/// Full list of Shows across both Display Modes (Home See All and Open Show).
/// Each row is the name, trailing recency, and a format glyph — no Landscape/Vertical copy.
final class AllShowsViewController: UIViewController, UIAdaptivePresentationControllerDelegate {

    /// Invoked when the user picks a Show to open.
    var onOpenShow: ((UUID) -> Void)?
    /// Invoked when the user taps New Show.
    var onCreateShow: (() -> Void)?
    /// Invoked when the sheet closes without opening or creating a Show.
    var onDismissWithoutOpening: (() -> Void)?

    private let tableView = UITableView(frame: .zero, style: .insetGrouped)
    private let filterBar = ShowFormatFilterBar()
    private let cellId = "ShowCell"
    private var albums: [LocalAlbum] = []
    private var observer: NSObjectProtocol?
    /// True once a row or New Show claimed the dismiss — skip the Home teardown.
    private var didSelectDestination = false
    private var formatFilter: ShowFormatFilter = .all

    /// Shows matching the active All / Horizontal / Vertical filter.
    private var displayedAlbums: [LocalAlbum] {
        ShowFormatFilter.albums(albums, matching: formatFilter)
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Shows"
        view.backgroundColor = .systemBackground
        navigationItem.leftBarButtonItem = UIBarButtonItem(
            systemItem: .close,
            primaryAction: UIAction { [weak self] _ in
                self?.doneTapped()
            }
        )
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            title: "New Show",
            style: .plain,
            target: self,
            action: #selector(newShowTapped)
        )
        configureFilterBar()
        configureTable()
        reload()
        observer = NotificationCenter.default.addObserver(
            forName: LocalAlbumStore.didChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.reload()
        }
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        // Closest VC that owns the sheet — swipe-to-dismiss reports here.
        navigationController?.presentationController?.delegate = self
    }

    deinit {
        if let observer {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    private func configureFilterBar() {
        filterBar.translatesAutoresizingMaskIntoConstraints = false
        filterBar.onSelect = { [weak self] filter in
            self?.formatFilter = filter
            self?.tableView.reloadData()
        }
        view.addSubview(filterBar)
    }

    private func configureTable() {
        tableView.translatesAutoresizingMaskIntoConstraints = false
        tableView.dataSource = self
        tableView.delegate = self
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: cellId)
        view.addSubview(tableView)
        NSLayoutConstraint.activate([
            filterBar.topAnchor.constraint(
                equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 8
            ),
            filterBar.leadingAnchor.constraint(
                equalTo: view.leadingAnchor, constant: 20
            ),
            filterBar.trailingAnchor.constraint(
                equalTo: view.trailingAnchor, constant: -20
            ),
            tableView.topAnchor.constraint(
                equalTo: filterBar.bottomAnchor, constant: 4
            ),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
    }

    private func reload() {
        albums = LocalAlbumStore.shared.albums
        tableView.reloadData()
    }

    @objc private func doneTapped() {
        let finished = onDismissWithoutOpening
        dismiss(animated: true) {
            finished?()
        }
    }

    @objc private func newShowTapped() {
        didSelectDestination = true
        let create = onCreateShow
        dismiss(animated: true) {
            create?()
        }
    }

    func presentationControllerDidDismiss(
        _ presentationController: UIPresentationController
    ) {
        guard !didSelectDestination else { return }
        onDismissWithoutOpening?()
    }
}

extension AllShowsViewController: UITableViewDataSource, UITableViewDelegate {
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        displayedAlbums.count
    }

    func tableView(
        _ tableView: UITableView,
        cellForRowAt indexPath: IndexPath
    ) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: cellId, for: indexPath)
        let album = displayedAlbums[indexPath.row]
        var content = cell.defaultContentConfiguration()
        content.text = album.name
        content.secondaryText = album.showListSubtitle
        content.prefersSideBySideTextAndSecondaryText = true
        content.textProperties.numberOfLines = 1
        content.secondaryTextProperties.numberOfLines = 1
        content.secondaryTextProperties.color = .secondaryLabel
        content.image = UIImage(systemName: album.showPickerIconName)
        content.imageProperties.tintColor = .secondaryLabel
        cell.contentConfiguration = content
        cell.accessoryType = .disclosureIndicator
        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        didSelectDestination = true
        let id = displayedAlbums[indexPath.row].id
        // Capture the handler — don't rely on `self` surviving dismiss completion.
        let open = onOpenShow
        dismiss(animated: true) {
            open?(id)
        }
    }
}
