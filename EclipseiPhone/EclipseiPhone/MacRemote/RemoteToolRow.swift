//
//  RemoteToolRow.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import SwiftUI

// MARK: - RemoteHeaderToggle

/// Round header button that lights up while its state is on.
///
/// Used for Lock and Blackout so both read like the Show page header.
/// Thread Safety: Main thread only (SwiftUI view).
struct RemoteHeaderToggle: View {
    let systemImage: String
    let label: String
    let isOn: Bool
    let action: () -> Void

    private static let buttonSize: CGFloat = 44
    private static let iconSize: CGFloat = 20

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: Self.iconSize, weight: .regular))
                .foregroundStyle(isOn ? Color.white : Color.primary)
                .frame(width: Self.buttonSize, height: Self.buttonSize)
                .background(
                    Capsule(style: .continuous)
                        .fill(isOn ? Color.accentColor : Color.clear)
                )
                .overlay(
                    Capsule(style: .continuous)
                        .strokeBorder(
                            isOn ? Color.clear : Color(uiColor: .separator),
                            lineWidth: 1
                        )
                )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .accessibilityValue(isOn ? "On" : "Off")
    }
}

// MARK: - RemoteToolRow

/// Row of live tools under the remote's preview: Freeze, Screensaver,
/// Screenshot, Timer, Music and Record — the same tools the Mac's web remote offers.
///
/// Each button sends one `RemoteCommandAction`; lit states come from the
/// Mac's state snapshot, so the row always shows what the Mac is doing.
/// Thread Safety: Main thread only (SwiftUI view).
struct RemoteToolRow: View {
    @ObservedObject var session: RemoteSessionModel

    /// Countdown lengths offered in the Timer menu, in seconds (same as the web remote).
    private static let timerPresets: [Int] = [30, 60, 120, 180, 300, 600]

    var body: some View {
        let snapshot = session.snapshot
        HStack(spacing: 8) {
            tool("Freeze", "snowflake", isOn: snapshot?.isFrozen == true) {
                session.send(.freeze)
            }
            tool("Screensaver", "sparkles.tv", isOn: false) {
                session.send(.screensaver)
            }
            tool("Screenshot", "camera", isOn: false) {
                session.send(.screenshot)
            }
            timerMenu(state: snapshot?.timer)
            musicMenu(state: snapshot?.music)
            tool("Record", "record.circle", isOn: snapshot?.isRecording == true) {
                session.send(.record)
            }
        }
    }

    // MARK: - Buttons

    private func tool(
        _ title: String,
        _ systemImage: String,
        isOn: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            toolLabel(title, systemImage, isOn: isOn)
        }
        .buttonStyle(.plain)
        .accessibilityValue(isOn ? "On" : "Off")
    }

    private func toolLabel(_ title: String, _ systemImage: String, isOn: Bool) -> some View {
        VStack(spacing: 4) {
            Image(systemName: systemImage)
                .font(.system(size: 18, weight: .regular))
            Text(title)
                .font(.caption2)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .foregroundStyle(isOn ? Color.white : Color.primary)
        .frame(maxWidth: .infinity, minHeight: 52)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(isOn ? Color.accentColor : Color(uiColor: .secondarySystemBackground))
        )
    }

    // MARK: - Music

    /// Background-music controls; hidden entries mean the Mac did not send music state.
    private func musicMenu(state: RemoteMusicState?) -> some View {
        let playing = state?.isPlaying == true
        return Menu {
            if let title = state?.title, !title.isEmpty {
                Text(title)
            }
            Button(playing ? "Pause" : "Play") { session.send(.musicToggle) }
            Button("Next Track") { session.send(.musicNext) }
            Button("Previous Track") { session.send(.musicPrevious) }
            Button("Fade Out") { session.send(.musicFadeOut) }
            Button("Fade In") { session.send(.musicFadeIn) }
            Button(state?.busMuted == true ? "Unmute Music" : "Mute Music") {
                session.send(.musicToggleMute)
            }
        } label: {
            toolLabel("Music", "music.note", isOn: playing)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Music")
        .accessibilityValue(playing ? "Playing" : "Not playing")
    }

    // MARK: - Timer

    private func timerMenu(state: RemoteTimerState?) -> some View {
        let visible = state?.visible == true
        return Menu {
            Button(visible ? "Hide Timer" : "Show Timer") { session.send(.timerToggle) }
            if visible {
                Button(state?.live == true ? "Take Off Screen" : "Put on Screen") {
                    session.send(.timerLive)
                }
                Button(state?.running == true ? "Pause" : "Start") { session.send(.timerPlay) }
                Button("Reset") { session.send(.timerReset) }
                Menu {
                    ForEach(Self.timerPresets, id: \.self) { seconds in
                        Button(Self.durationText(seconds)) {
                            session.send(RemoteCommand(action: .timerDuration, value: seconds))
                        }
                    }
                } label: {
                    Text("Length")
                }
            }
        } label: {
            toolLabel(timerTitle(state), "timer", isOn: state?.live == true)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Timer")
    }

    private func timerTitle(_ state: RemoteTimerState?) -> String {
        guard let state, state.visible else { return "Timer" }
        return Self.durationText(state.remaining)
    }

    /// Formats seconds as "m:ss" (e.g. 90 → "1:30").
    static func durationText(_ seconds: Int) -> String {
        let clamped = max(0, seconds)
        return String(format: "%d:%02d", clamped / 60, clamped % 60)
    }
}
