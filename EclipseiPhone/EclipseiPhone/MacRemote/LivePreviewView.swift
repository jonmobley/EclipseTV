//
//  LivePreviewView.swift
//  EclipseRemote
//
//  Description: Live program preview styled like the Show-page LiveHeaderView.
//  Thread Safety: Main thread only — SwiftUI view.
//

import SwiftUI
import UIKit

// MARK: - LivePreviewView

/// Live preview of the Mac program output at the show aspect.
///
/// Thread Safety: Main thread only.
struct LivePreviewView: View {
    @ObservedObject var session: RemoteSessionModel

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(.secondarySystemBackground))

            previewContent
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))

            if showLiveBadge {
                VStack {
                    HStack {
                        liveBadge
                        Spacer()
                    }
                    Spacer()
                }
                .padding(14)
            }
        }
        .aspectRatio(programAspect, contentMode: .fit)
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Color(uiColor: .separator), lineWidth: 1)
        )
        .accessibilityLabel(accessibilityText)
    }

    // MARK: - Private Helpers

    /// Mac program width ÷ height (Landscape / Vertical / custom).
    private var programAspect: CGFloat {
        let value = session.snapshot?.programAspect ?? (16.0 / 9.0)
        guard value > 0, value.isFinite else { return 16.0 / 9.0 }
        return CGFloat(value)
    }

    @ViewBuilder
    private var previewContent: some View {
        if session.snapshot?.isBlackout == true {
            ZStack {
                Color.black
                Image(systemName: "moon.fill")
                    .font(.system(size: 36, weight: .medium))
                    .foregroundStyle(.white.opacity(0.55))
            }
        } else if let image = liveThumbnail {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
                .overlay {
                    if session.snapshot?.isFrozen == true {
                        Color.cyan.opacity(0.18)
                    }
                }
        } else {
            idlePlaceholder
        }
    }

    private var idlePlaceholder: some View {
        VStack(spacing: 10) {
            Image(systemName: "tv")
                .font(.system(size: 44, weight: .regular))
                .foregroundStyle(Color(.tertiaryLabel))
            Text(placeholderText)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Color(.secondaryLabel))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 16)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var liveThumbnail: UIImage? {
        guard let id = thumbnailID else { return nil }
        return session.thumbnails.images[id]
    }

    private var thumbnailID: String? {
        if let item = liveItem, item.hasThumbnail { return item.id }
        return session.snapshot?.liveMediaID
    }

    private var liveItem: RemoteMediaEntry? {
        guard let id = session.snapshot?.liveMediaID else { return nil }
        let media = session.snapshot?.media ?? []
        let library = session.snapshot?.libraryMedia ?? []
        return media.first { $0.id == id } ?? library.first { $0.id == id }
    }

    private var showLiveBadge: Bool {
        session.snapshot?.liveMediaID != nil && session.snapshot?.isBlackout != true
    }

    private var placeholderText: String {
        if let liveItem { return liveItem.type }
        if session.snapshot?.liveMediaID != nil { return "Live media" }
        return "No media selected"
    }

    private var accessibilityText: String {
        if session.snapshot?.isBlackout == true { return "Blackout" }
        if showLiveBadge {
            return liveItem.map { "Live, \($0.title)" } ?? "Live"
        }
        return placeholderText
    }

    /// Matches Show-page `PaddedLabel` LIVE chrome (red fill, 6pt corners).
    private var liveBadge: some View {
        Text("LIVE")
            .font(.system(size: 13, weight: .bold))
            .foregroundStyle(.white)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color.red)
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
    }
}
