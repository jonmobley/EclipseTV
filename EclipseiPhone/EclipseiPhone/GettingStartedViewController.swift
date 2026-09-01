//
//  GettingStartedViewController.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import UIKit

/// In-app overview guide aligned to the five cores: Shows, AirPlay, Camera, Music, EclipseTV.
final class GettingStartedViewController: UITableViewController {

    private struct Topic {
        let title: String
        let body: String
        let systemImage: String
        let tint: UIColor
    }

    private let topics: [Topic] = [
        Topic(
            title: "Welcome",
            body: """
            Eclipse is your presentation remote: build Shows, present with AirPlay, \
            optionally use Camera and ambient Music, and link EclipseTV only when you \
            want media sync with the TV app.
            """,
            systemImage: "sparkles",
            tint: .systemBlue
        ),
        Topic(
            title: "Shows",
            body: """
            A Show is a set of media you present together. Tap New Show, name it, and \
            open it to add images, videos, websites, or a slideshow. Your recent Shows \
            appear on Home — tap one to jump back in.
            """,
            systemImage: "rectangle.stack.fill",
            tint: .systemIndigo
        ),
        Topic(
            title: "Presenting",
            body: """
            Start AirPlay from Control Center — that’s enough to present. Tap any tile \
            in a Show to put it on screen; the live preview mirrors the audience. Link \
            EclipseTV from Settings → EclipseTV when you want the TV app in sync.
            """,
            systemImage: "airplayvideo",
            tint: .systemTeal
        ),
        Topic(
            title: "Camera",
            body: """
            Inside a Show, tap Camera to put a live feed on AirPlay. Use ⋯ Open \
            Controller for the phone viewfinder without changing what’s on screen. \
            Stills and clips you shoot stay on your phones (and can sync with \
            iCloud), and are never sent to the EclipseTV app library.
            """,
            systemImage: "camera.fill",
            tint: .systemGreen
        ),
        Topic(
            title: "Live Poll",
            body: """
            Add Live Poll from + inside a Show — link your QuestPoll host PIN once, \
            then pick a deck for each card. Tap a card for Practice (phone preview, \
            no room) or Start (creates the room on AirPlay, HDMI, or Practice Mode). \
            EclipseTV alone cannot show the poll. Starting another poll ends the \
            current room. The ribbon under the live preview cues Join, each question, \
            and results; audience phones scan the QR on the projector. Use ⋯ Edit on \
            QuestPoll to manage decks in the browser.
            """,
            systemImage: "chart.bar.fill",
            tint: .systemOrange
        ),
        Topic(
            title: "Countdown",
            body: """
            Add Countdown from + inside a Show as many times as you like — each \
            tile is its own timer. Tap one to put it on AirPlay or HDMI — EclipseTV \
            alone cannot show the clock. The ribbon under the live preview picks \
            0:30, 1:00, 2:00, 5:00, 10:00, or Custom. Tap the tile again to pause or \
            resume; ⋯ Reset restores the full duration.
            """,
            systemImage: "timer",
            tint: .systemRed
        ),
        Topic(
            title: "Music",
            body: """
            Tap Music in the bottom-right corner for quick access, swipe left from Home \
            when you can, or choose Music in the Home menu. The circle stays visible — \
            tap to open Music, or tap to stop while a track is playing. A button beside \
            the circle expands playback controls. Ambient audio pauses when a video \
            needs the speakers.
            """,
            systemImage: "music.note",
            tint: .systemPink
        ),
        Topic(
            title: "EclipseTV Link",
            body: """
            Linking EclipseTV (optional) syncs imported media with the Apple TV app and \
            enables multi-TV. AirPlay alone is enough for Shows. Use Settings → \
            EclipseTV to link with a pairing code.
            """,
            systemImage: "tv",
            tint: .systemCyan
        ),
        Topic(
            title: "Display Mode & Tools",
            body: """
            Landscape (16:9) is the default; Vertical is in Settings → Display Mode. \
            Inside a Show: header Blackout blanks the display, Background sets a \
            resting image, Screensaver loops a video, + adds media, and Live Poll \
            or Countdown run on AirPlay or HDMI.
            """,
            systemImage: "moon.fill",
            tint: .systemPurple
        ),
        Topic(
            title: "Tips",
            body: """
            On Home, long-press a Show for rename, share, or delete. Inside a Show, \
            tap a tile to put it on screen; long-press to arrange. Use ⋯ for Preview, \
            Loop, Mute, Thumbnail, cover, and remove. Getting Started is in Settings anytime.
            """,
            systemImage: "lightbulb.fill",
            tint: .systemYellow
        )
    ]

    // MARK: - Lifecycle

    init() {
        super.init(style: .insetGrouped)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Getting Started"
        navigationItem.largeTitleDisplayMode = .never
        // Presented as its own sheet: Done dismisses. Pushed from Settings:
        // the back button returns to Settings.
        if navigationController?.viewControllers.first === self {
            navigationItem.rightBarButtonItem = UIBarButtonItem(
                barButtonSystemItem: .done, target: self, action: #selector(doneTapped)
            )
        }
        tableView.register(
            GettingStartedTopicCell.self,
            forCellReuseIdentifier: GettingStartedTopicCell.reuseIdentifier
        )
        tableView.allowsSelection = false
        tableView.separatorStyle = .none
    }

    // MARK: - Table

    override func numberOfSections(in tableView: UITableView) -> Int {
        topics.count
    }

    override func tableView(
        _ tableView: UITableView, numberOfRowsInSection section: Int
    ) -> Int {
        1
    }

    override func tableView(
        _ tableView: UITableView, cellForRowAt indexPath: IndexPath
    ) -> UITableViewCell {
        guard let cell = tableView.dequeueReusableCell(
            withIdentifier: GettingStartedTopicCell.reuseIdentifier,
            for: indexPath
        ) as? GettingStartedTopicCell else {
            return UITableViewCell()
        }
        let topic = topics[indexPath.section]
        cell.configure(
            title: topic.title,
            body: topic.body,
            systemImage: topic.systemImage,
            tint: topic.tint
        )
        return cell
    }

    // MARK: - Private

    @objc private func doneTapped() {
        dismiss(animated: true)
    }
}
