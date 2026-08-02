//
//  RemoteControlView.swift
//  EclipseRemote
//
//  Description: Live control surface — preview, blackout, media grid, transport.
//  Thread Safety: Main thread only — SwiftUI view.
//

import SwiftUI

// MARK: - RemoteControlView

/// Primary remote UI once paired with Eclipse on the LAN.
///
/// Layout mirrors the in-app Show page: header chrome → live preview → media grid.
/// Thread Safety: Main thread only.
struct RemoteControlView: View {
    @ObservedObject var session: RemoteSessionModel
    @State private var showLibrary = false

    var body: some View {
        VStack(spacing: 0) {
            headerBar
                .padding(.horizontal, 16)
                .padding(.vertical, 8)

            ScrollView {
                VStack(spacing: 12) {
                    LivePreviewView(session: session)
                    sourcePicker
                    MediaGridView(
                        items: showLibrary
                            ? (session.snapshot?.libraryMedia ?? [])
                            : (session.snapshot?.media ?? []),
                        thumbnails: session.thumbnails,
                        onSelect: { item in
                            let action: RemoteCommandAction = showLibrary
                                ? .selectLibraryMedia : .selectMedia
                            session.send(
                                RemoteCommand(action: action, mediaID: item.id)
                            )
                        }
                    )
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 20)
            }
        }
        .background(Color(.systemBackground))
        .safeAreaInset(edge: .bottom) {
            if session.snapshot?.showsSlideNavigation == true {
                transportBar
            }
        }
    }

    // MARK: - Header (Show-page chrome)

    /// Presentation menu pill + Blackout moon — same roles as Show header.
    private var headerBar: some View {
        HStack(spacing: 8) {
            presentationMenu
            Spacer(minLength: 8)
            blackoutButton
        }
        .frame(height: 36)
    }

    private var presentationMenu: some View {
        let presentations = session.snapshot?.presentations ?? []
        let currentName = presentations.first(where: \.isCurrent)?.name
            ?? session.snapshot?.presentationName
            ?? "Presentation"

        return Menu {
            ForEach(presentations) { entry in
                Button {
                    session.send(
                        RemoteCommand(
                            action: .switchPresentation,
                            presentationID: entry.id
                        )
                    )
                } label: {
                    if entry.isCurrent {
                        Label(entry.name, systemImage: "checkmark")
                    } else {
                        Text(entry.name)
                    }
                }
            }
            if !presentations.isEmpty {
                Divider()
            }
            Button("Disconnect", role: .destructive) {
                session.disconnect()
            }
        } label: {
            HStack(spacing: 4) {
                Text(currentName)
                    .font(.system(size: 17, weight: .semibold))
                    .lineLimit(1)
                    .foregroundStyle(.primary)
                Image(systemName: "chevron.down")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.primary)
            }
            .padding(.leading, 12)
            .padding(.trailing, 10)
            .frame(height: 36)
            .background(
                Capsule(style: .continuous)
                    .strokeBorder(Color(uiColor: .separator), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Presentation menu")
    }

    private var blackoutButton: some View {
        let isOn = session.snapshot?.isBlackout == true
        return Button {
            session.send(.blackout)
        } label: {
            Image(systemName: "moon.fill")
                .font(.system(size: 20, weight: .regular))
                .foregroundStyle(isOn ? Color.white : Color.primary)
                .frame(width: 36, height: 36)
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
        .accessibilityLabel("Blackout")
        .accessibilityValue(isOn ? "On" : "Off")
    }

    // MARK: - Source + transport

    private var sourcePicker: some View {
        Picker("Source", selection: $showLibrary) {
            Text("Presentation").tag(false)
            Text("Library").tag(true)
        }
        .pickerStyle(.segmented)
    }

    private var transportBar: some View {
        HStack(spacing: 12) {
            Button {
                session.send(.previous)
            } label: {
                Label("Prev", systemImage: "backward.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)

            Button {
                session.send(.next)
            } label: {
                Label("Next", systemImage: "forward.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(.bar)
    }
}
