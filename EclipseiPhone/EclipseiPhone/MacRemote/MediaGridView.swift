//
//  MediaGridView.swift
//  EclipseRemote
//
//  Description: Media grid with optional LAN thumbnails and live badges.
//  Thread Safety: Main thread only — SwiftUI view.
//

import SwiftUI

// MARK: - MediaGridView

/// Title + thumbnail grid for presentation or library media.
///
/// Thread Safety: Main thread only.
struct MediaGridView: View {
    let items: [RemoteMediaEntry]
    @ObservedObject var thumbnails: RemoteThumbnailStore
    let onSelect: (RemoteMediaEntry) -> Void

    private let columns = [
        GridItem(.flexible(), spacing: 10),
        GridItem(.flexible(), spacing: 10)
    ]

    var body: some View {
        if items.isEmpty {
            ContentUnavailableView(
                "No media",
                systemImage: "square.grid.2x2",
                description: Text("Add cards on the Mac to control them here.")
            )
            .frame(minHeight: 160)
        } else {
            LazyVGrid(columns: columns, spacing: 10) {
                ForEach(items) { item in
                    Button {
                        onSelect(item)
                    } label: {
                        cell(for: item)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func cell(for item: RemoteMediaEntry) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            ZStack(alignment: .topTrailing) {
                thumbnail(for: item)
                    .frame(maxWidth: .infinity)
                    .frame(height: 88)
                    .clipped()
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

                if item.isLive || item.isOverlayActive {
                    Text(item.isLive ? "LIVE" : "ON")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.accentColor)
                        .clipShape(Capsule())
                        .padding(6)
                }
            }

            Text(item.title)
                .font(.subheadline.weight(.semibold))
                .lineLimit(2)
                .foregroundStyle(.primary)
            Text(item.type)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.secondary.opacity(item.isLive ? 0.22 : 0.12))
        )
    }

    @ViewBuilder
    private func thumbnail(for item: RemoteMediaEntry) -> some View {
        if let image = thumbnails.images[item.id] {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
        } else {
            ZStack {
                Color.secondary.opacity(0.18)
                Image(systemName: item.hasThumbnail ? "photo" : "rectangle.on.rectangle")
                    .foregroundStyle(.secondary)
            }
        }
    }
}
