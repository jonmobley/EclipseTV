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
    /// Latest Mac show aspect; appended to thumb URLs so caches don't stick.
    private var programAspect: Double = 16.0 / 9.0
    private var aspectRefreshTask: Task<Void, Never>?

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
        aspectRefreshTask?.cancel()
        aspectRefreshTask = nil
        images.removeAll()
        inflight.removeAll()
        client = nil
        token = nil
        programAspect = 16.0 / 9.0
    }

    /// Drops cached images so the next prefetch refetches (e.g. after aspect change).
    func invalidateImages() {
        images.removeAll()
        inflight.removeAll()
    }

    /// Updates the show aspect used for thumb URL cache-busting.
    /// - Parameter aspect: Mac `programAspect` (width ÷ height).
    func setProgramAspect(_ aspect: Double) {
        guard aspect > 0, aspect.isFinite else { return }
        programAspect = aspect
    }

    /// Prefetches thumbnails for entries that advertise `hasThumbnail`.
    /// - Parameter items: Media rows from the latest snapshot.
    func prefetch(items: [RemoteMediaEntry]) {
        for item in items where item.hasThumbnail {
            loadIfNeeded(id: item.id)
        }
    }

    /// Clears thumbs and reloads now plus a few delayed passes.
    ///
    /// Mac webpage cards recapture asynchronously after show-size changes; the
    /// delayed passes pick up those bitmaps without a new wire field.
    /// - Parameter itemsProvider: Returns the current media rows to refresh.
    func refreshAfterAspectChange(itemsProvider: @escaping () -> [RemoteMediaEntry]) {
        aspectRefreshTask?.cancel()
        invalidateImages()
        prefetch(items: itemsProvider())

        let delaysNs: [UInt64] = [800_000_000, 2_000_000_000, 4_000_000_000]
        aspectRefreshTask = Task { [weak self] in
            for delay in delaysNs {
                try? await Task.sleep(nanoseconds: delay)
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    guard let self else { return }
                    self.invalidateImages()
                    self.prefetch(items: itemsProvider())
                }
            }
        }
    }

    // MARK: - Private Helpers

    private func loadIfNeeded(id: String) {
        guard images[id] == nil, !inflight.contains(id),
              let client, let token else { return }
        inflight.insert(id)
        let aspect = programAspect
        Task { [weak self] in
            defer {
                Task { @MainActor in self?.inflight.remove(id) }
            }
            do {
                let data = try await client.thumbnail(
                    id: id,
                    token: token,
                    programAspect: aspect
                )
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
