//
//  RemoteThumbnailStore.swift
//  EclipseRemote
//
//  Description: Fetches and caches media PNG thumbnails from the Mac remote.
//  Thread Safety: Main actor — UI-facing ObservableObject.
//

import Foundation
import UIKit

// MARK: - RemoteThumbnailStore

/// Loads `/thumb/{id}` images for the media grid and caches them in memory.
///
/// Thread Safety: Main actor only.
@MainActor
final class RemoteThumbnailStore: ObservableObject {

    // MARK: - Properties

    @Published private(set) var images: [String: UIImage] = [:]

    private var inflight: Set<String> = []
    private weak var client: RemoteAPIClient?
    private var token: String?

    // MARK: - Public Interface

    /// Binds the store to the active remote session credentials.
    /// - Parameters:
    ///   - client: API client for the Mac origin.
    ///   - token: Bearer session token.
    func configure(client: RemoteAPIClient, token: String) {
        self.client = client
        self.token = token
    }

    /// Drops cache and credentials on disconnect.
    func reset() {
        images.removeAll()
        inflight.removeAll()
        client = nil
        token = nil
    }

    /// Prefetches thumbnails for entries that advertise `hasThumbnail`.
    /// - Parameter items: Media rows from the latest snapshot.
    func prefetch(items: [RemoteMediaEntry]) {
        for item in items where item.hasThumbnail {
            loadIfNeeded(id: item.id)
        }
    }

    // MARK: - Private Helpers

    private func loadIfNeeded(id: String) {
        guard images[id] == nil, !inflight.contains(id),
              let client, let token else { return }
        inflight.insert(id)
        Task { [weak self] in
            defer {
                Task { @MainActor in self?.inflight.remove(id) }
            }
            do {
                let data = try await client.thumbnail(id: id, token: token)
                guard let image = UIImage(data: data) else { return }
                await MainActor.run {
                    self?.images[id] = image
                }
            } catch {
                // Leave the cell on its title fallback; next snapshot may retry.
            }
        }
    }
}
