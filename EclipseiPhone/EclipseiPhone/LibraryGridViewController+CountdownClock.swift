//
//  LibraryGridViewController+CountdownClock.swift
//  Eclipse
//
//  Countdown tile ⋯ menu entries for how the clock counts and looks: Reset,
//  Duration (Countdown only), Mode (Countdown / Count Up / To Time + Set Time…),
//  Caption and "Card Behind Numbers". Also what each tile's face shows.
//  Thread Safety: Main-actor UIKit.
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import UIKit

/// What a countdown tile's face shows right now.
struct CountdownTileFace: Equatable {
    /// `4:59`, `0:00`, or `to 6:30 PM`.
    let text: String
    /// Red digits: a spent clock.
    let isExpired: Bool
    /// An idle tile showing time held from an earlier run.
    let isHeld: Bool
}

extension LibraryGridViewController {

    /// Captions offered in the ⋯ menu, same as the Mac's built-in list.
    static let countdownCaptionPresets = [
        "Get ready", "Service starts in", "Doors open in", "Up next", "Starting soon"
    ]

    // MARK: - Tile Face

    /// Face for a tile: the running clock when live (the director's on an
    /// operator), else what a tap would show (length, held time, 0:00, target).
    func countdownTileFace(for item: ShowCountdown, isLive: Bool) -> CountdownTileFace {
        let clock = CountdownController.shared
        if isLive, let remote = remoteCountdownState {
            return CountdownTileFace(
                text: CountdownController.displayString(seconds: remote.remaining),
                isExpired: remote.isAtEnd,
                isHeld: false
            )
        }
        if isLive {
            return CountdownTileFace(
                text: clock.displayString, isExpired: clock.isAtEnd, isHeld: false
            )
        }
        let held = clock.heldRemaining(for: item)
        return CountdownTileFace(
            text: item.clock.idleFaceText(duration: item.duration, held: held),
            isExpired: false,
            isHeld: held != nil
        )
    }

    /// Second line under the name: a To Time date and/or "Then black" / "Then
    /// next" (never for Count Up, which does not end).
    func countdownEndHint(for item: ShowCountdown) -> String? {
        let end = item.clock.mode.expires ? item.endAction.tileHint : nil
        let parts = [item.clock.targetDayText, end].compactMap { $0 }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    // MARK: - Reset and Duration

    /// Reset, Duration (Countdown only) and When It Ends (not for Count Up).
    func countdownToolActions(for item: ShowCountdown) -> [UIMenuElement] {
        // Live here or on the director; both read the same predicate as the tile.
        let isLive = isShowGridItemLive(.countdown(item))
        let reset = UIAction(
            title: "Reset",
            image: UIImage(systemName: "arrow.counterclockwise")
        ) { [weak self] _ in
            // An idle tile has no clock to reset, but it may be holding a
            // remainder that Reset is the way to throw away.
            guard isLive else {
                CountdownController.shared.discardHeldTime(for: item.id)
                return
            }
            if self?.sendShowLiveCommandIfOperator(.countdownReset) == true { return }
            CountdownController.shared.reset()
        }
        var actions: [UIMenuElement] = [reset]
        if item.clock.mode == .countdown {
            actions.append(countdownDurationMenu(for: item, isLive: isLive))
        }
        if item.clock.mode.expires {
            actions.append(countdownEndActionMenu(for: item))
        }
        return actions
    }

    // MARK: - Mode, Caption, Plate

    /// Mode, Caption and Card Behind Numbers, as one inline group.
    func countdownClockMenu(for item: ShowCountdown) -> UIMenu {
        let plate = UIAction(
            title: "Card Behind Numbers",
            image: UIImage(systemName: "rectangle.fill"),
            state: item.clock.showsPlate ? .on : .off
        ) { _ in
            Self.updateClock(of: item.id) {
                $0.style = $0.showsPlate ? .simple : .card
            }
        }
        return UIMenu(options: .displayInline, children: [
            countdownModeMenu(for: item), countdownCaptionMenu(for: item), plate
        ])
    }

    // MARK: - Private

    private func countdownDurationMenu(for item: ShowCountdown, isLive: Bool) -> UIMenu {
        let selectedDuration = isLive ? selectedCountdownDuration : item.duration
        var durationActions: [UIMenuElement] = CountdownController.durationPresets.map {
            seconds in
            UIAction(
                title: CountdownController.displayString(seconds: seconds),
                state: seconds == selectedDuration ? .on : .off
            ) { [weak self] _ in
                self?.applyCountdownDuration(seconds, to: item.id)
            }
        }
        let isPreset = CountdownController.durationPresets.contains(selectedDuration)
        durationActions.append(UIAction(
            title: "Custom…",
            image: UIImage(systemName: "pencil"),
            state: isPreset ? .off : .on
        ) { [weak self] _ in
            self?.promptCustomCountdownDuration(for: item.id)
        })
        return UIMenu(
            title: "Duration",
            image: UIImage(systemName: "timer"),
            children: durationActions
        )
    }

    private func countdownModeMenu(for item: ShowCountdown) -> UIMenu {
        var children: [UIMenuElement] = CountdownMode.allCases.map { mode in
            let action = UIAction(
                title: mode.title,
                subtitle: mode.explanation,
                image: UIImage(systemName: mode.systemImage),
                state: item.clock.mode == mode ? .on : .off
            ) { [weak self] _ in
                self?.chooseCountdownMode(mode, for: item)
            }
            return action
        }
        if item.clock.mode == .timeOfDay {
            children.append(UIAction(
                title: "Set Time…",
                subtitle: item.clock.targetText(),
                image: UIImage(systemName: "clock.badge")
            ) { [weak self] _ in
                self?.presentCountdownTargetEditor(for: item)
            })
        }
        return UIMenu(
            title: "Mode",
            subtitle: item.clock.mode.title,
            image: UIImage(systemName: item.clock.mode.systemImage),
            children: children
        )
    }

    private func countdownCaptionMenu(for item: ShowCountdown) -> UIMenu {
        let current = item.clock.caption
        var options = Self.countdownCaptionPresets
        if !current.isEmpty, !options.contains(current) { options.append(current) }
        var children: [UIMenuElement] = [
            UIAction(title: "None", state: current.isEmpty ? .on : .off) { _ in
                Self.updateClock(of: item.id) { $0.caption = "" }
            }
        ]
        children += options.map { caption in
            UIAction(title: caption, state: caption == current ? .on : .off) { _ in
                Self.updateClock(of: item.id) { $0.caption = caption }
            }
        }
        children.append(UIAction(
            title: "Custom…", image: UIImage(systemName: "pencil")
        ) { [weak self] _ in
            self?.promptCountdownCaption(for: item)
        })
        return UIMenu(
            title: "Caption",
            subtitle: current.isEmpty ? "None" : current,
            image: UIImage(systemName: "textformat"),
            children: children
        )
    }

    /// Count Up and Countdown apply at once; To Time first asks for the time.
    private func chooseCountdownMode(_ mode: CountdownMode, for item: ShowCountdown) {
        guard mode == .timeOfDay else {
            Self.updateClock(of: item.id) { $0.mode = mode }
            return
        }
        presentCountdownTargetEditor(for: item)
    }

    private func presentCountdownTargetEditor(for item: ShowCountdown) {
        let current = CountdownStore.shared.countdown(id: item.id)?.clock ?? item.clock
        let editor = CountdownTargetTimeViewController(settings: current)
        editor.onDone = { settings in
            CountdownStore.shared.setClock(id: item.id, settings)
        }
        let nav = UINavigationController(rootViewController: editor)
        nav.modalPresentationStyle = .formSheet
        if let sheet = nav.sheetPresentationController {
            sheet.detents = [.medium(), .large()]
            sheet.prefersGrabberVisible = true
        }
        present(nav, animated: true)
    }

    private func promptCountdownCaption(for item: ShowCountdown) {
        let alert = UIAlertController(
            title: "Caption",
            message: "Short words shown above the clock.",
            preferredStyle: .alert
        )
        alert.addTextField { field in
            field.text = item.clock.caption
            field.placeholder = "Doors open in"
            field.autocapitalizationType = .sentences
            UserDisplayName.configureTextField(field)
        }
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(UIAlertAction(title: "Save", style: .default) { _ in
            let text = alert.textFields?.first?.text ?? ""
            Self.updateClock(of: item.id) {
                $0.caption = CountdownClockSettings.clampedCaption(text)
            }
        })
        alert.preferConfirmAction()
        present(alert, animated: true)
    }

    /// Edits the stored settings of countdown `id` (the live clock follows).
    private static func updateClock(of id: UUID, _ change: (inout CountdownClockSettings) -> Void) {
        guard var clock = CountdownStore.shared.countdown(id: id)?.clock else { return }
        change(&clock)
        CountdownStore.shared.setClock(id: id, clock)
    }
}
