//
//  MediaGridView.swift
//  EclipseRemote
//
//  Description: Media grid styled like Show-page thumbnail tiles.
//  Thread Safety: Main thread only — SwiftUI view.
//

import SwiftUI

// MARK: - MediaGridView

/// Thumbnail grid for presentation or library media.
///
/// Thread Safety: Main thread only.
struct MediaGridView: View {
    let items: [RemoteMediaEntry]
    /// Mac program width ÷ height for card slots.
    var programAspect: CGFloat = 16.0 / 9.0
    @ObservedObject var thumbnails: RemoteThumbnailStore
    let onSelect: (RemoteMediaEntry) -> Void

    private let columns = [
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12)
    ]

    private var slotAspect: CGFloat {
        guard programAspect > 0, programAspect.isFinite else { return 16.0 / 9.0 }
        return programAspect
    }

    var body: some View {
        if items.isEmpty {
            ContentUnavailableView(
                "No media",
                systemImage: "square.grid.2x2",
                description: Text("Add cards on the Mac to control them here.")
            )
            .frame(minHeight: 160)
        } else {
            LazyVGrid(columns: columns, spacing: 12) {
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

    /// Full-bleed program-aspect tile with on-card caption.
    private func cell(for item: RemoteMediaEntry) -> some View {
        ZStack(alignment: .bottomLeading) {
            thumbnail(for: item)
                .frame(maxWidth: .infinity)
                .aspectRatio(slotAspect, contentMode: .fit)
                .clipped()

            LinearGradient(
                colors: [.clear, .black.opacity(0.72)],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: 56)
            .frame(maxHeight: .infinity, alignment: .bottom)

            VStack(alignment: .leading, spacing: 2) {
                Text(item.title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(2)
                Text(item.type)
                    .font(.system(size: 12, weight: .regular))
                    .foregroundStyle(.white.opacity(0.78))
                    .lineLimit(1)
            }
            .padding(10)

            if item.isLive || item.isOverlayActive {
                VStack {
                    HStack {
                        Text(item.isLive ? "LIVE" : "ON")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(item.isLive ? Color.red : Color.accentColor)
                            .clipShape(
                                RoundedRectangle(cornerRadius: 6, style: .continuous)
                            )
                        Spacer()
                    }
                    Spacer()
                }
                .padding(8)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(.secondarySystemBackground))
        )
        .accessibilityLabel(
            item.isLive ? "\(item.title), Live" : item.title
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
                Color(.secondarySystemBackground)
                Image(systemName: item.hasThumbnail ? "photo" : "rectangle.on.rectangle")
                    .font(.system(size: 28, weight: .medium))
                    .foregroundStyle(Color(.tertiaryLabel))
            }
        }
    }
}
