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
/// Thread Safety: Main thread only.
struct RemoteControlView: View {
    @ObservedObject var session: RemoteSessionModel
    @State private var showLibrary = false

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                LivePreviewView(session: session)
                presentationAndBlackoutRow
                sourcePicker
                MediaGridView(
                    items: showLibrary
                        ? (session.snapshot?.libraryMedia ?? [])
                        : (session.snapshot?.media ?? []),
                    thumbnails: session.thumbnails,
                    onSelect: { item in
                        let action: RemoteCommandAction = showLibrary
                            ? .selectLibraryMedia : .selectMedia
                        session.send(RemoteCommand(action: action, mediaID: item.id))
                    }
                )
            }
            .padding()
        }
        .safeAreaInset(edge: .bottom) {
            if session.snapshot?.showsSlideNavigation == true {
                transportBar
            }
        }
    }

    // MARK: - Sections

    /// Presentation menu on the left, Blackout on the right.
    private var presentationAndBlackoutRow: some View {
        HStack(spacing: 10) {
            presentationMenu
                .frame(maxWidth: .infinity, alignment: .leading)

            Button {
                session.send(.blackout)
            } label: {
                Text("Blackout")
                    .font(.subheadline.weight(.semibold))
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .background(
                        session.snapshot?.isBlackout == true
                            ? Color.accentColor
                            : Color.secondary.opacity(0.15)
                    )
                    .foregroundStyle(
                        session.snapshot?.isBlackout == true ? Color.white : Color.primary
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            .buttonStyle(.plain)
        }
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
                        RemoteCommand(action: .switchPresentation, presentationID: entry.id)
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
            HStack(spacing: 6) {
                Text(currentName)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                    .foregroundStyle(.primary)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(Color.secondary.opacity(0.15))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
    }

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
            .buttonStyle(.borderedProminent)

            Button {
                session.send(.next)
            } label: {
                Label("Next", systemImage: "forward.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
        }
        .padding()
        .background(.ultraThinMaterial)
    }
}
