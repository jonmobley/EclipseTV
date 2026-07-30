//
//  LivePreviewView.swift
//  EclipseRemote
//
//  Description: Live program preview for the native remote (web-parity cue).
//  Thread Safety: Main thread only — SwiftUI view.
//

import SwiftUI
import UIKit

// MARK: - LivePreviewView

/// 16:9 live preview of the Mac program output.
///
/// Thread Safety: Main thread only.
struct LivePreviewView: View {
    @ObservedObject var session: RemoteSessionModel

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.black)

            previewContent
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

            if showLiveBadge {
                VStack {
                    HStack {
                        liveBadge
                        Spacer()
                    }
                    Spacer()
                }
                .padding(10)
            }
        }
        .aspectRatio(16 / 9, contentMode: .fit)
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color.secondary.opacity(0.25), lineWidth: 1)
        )
    }

    // MARK: - Private Helpers

    @ViewBuilder
    private var previewContent: some View {
        if session.snapshot?.isBlackout == true {
            placeholder("Black")
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
            placeholder(placeholderText)
        }
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

    private var liveBadge: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(Color.red)
                .frame(width: 7, height: 7)
            Text("LIVE")
                .font(.caption2.weight(.bold))
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color.black.opacity(0.55))
        .clipShape(Capsule())
    }

    private func placeholder(_ text: String) -> some View {
        Text(text)
            .font(.subheadline.weight(.medium))
            .foregroundStyle(.white.opacity(0.7))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
