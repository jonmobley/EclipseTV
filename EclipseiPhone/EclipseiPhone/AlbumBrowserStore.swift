//
//  AlbumBrowserStore.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

// AlbumBrowserStore.swift
import Foundation
import os.log

/// Backs the iPhone's album browser. Holds the configured account code and the albums
/// fetched from the account manifest over HTTPS, persisting both so the last-seen albums
/// show immediately on relaunch (thumbnails come from `RemoteImageLoader`'s disk cache).
///
/// Unlike the Apple TV's `RemoteAlbumStore`, the phone never downloads full media — it
/// displays straight from the manifest's remote URLs — so this store only keeps metadata.
@MainActor
final class AlbumBrowserStore {

    static let shared = AlbumBrowserStore()

    // MARK: - Errors

    enum FetchError: LocalizedError {
        case notConfigured
        case invalidURL
        case invalidCode      // HTTP 400
        case unknownCode      // HTTP 404
        case rateLimited      // HTTP 429
        case badResponse(Int)
        case decodeFailed

        var errorDescription: String? {
            switch self {
            case .notConfigured: return "No account code set"
            case .invalidURL, .invalidCode: return "That account code looks invalid"
            case .unknownCode: return "No account found for that code"
            case .rateLimited: return "Too many requests — please try again in a moment"
            case .badResponse(let status): return "Server error (\(status))"
            case .decodeFailed: return "Couldn't read the album data"
            }
        }
    }

    // MARK: - State

    private(set) var accountCode: String?
    private(set) var albums: [AlbumManifestAlbum] = []

    private let defaults: UserDefaults
    private let session: URLSession
    private let logger = Logger(subsystem: "com.eclipseapp.ios", category: "AlbumBrowserStore")

    private let codeKey = "EclipseiPhone.album.code"
    private let manifestKey = "EclipseiPhone.album.manifest"

    init(defaults: UserDefaults = .standard, session: URLSession = .shared) {
        self.defaults = defaults
        self.session = session
        // The account code lives in the Keychain (encrypted at rest). Migrate a code
        // persisted by older builds out of plaintext UserDefaults on first load.
        if let legacy = defaults.string(forKey: codeKey) {
            KeychainStore.set(legacy, forKey: codeKey)
            defaults.removeObject(forKey: codeKey)
        }
        accountCode = KeychainStore.string(forKey: codeKey)
        loadCachedManifest()
    }

    // MARK: - Configuration

    var hasAccountConfigured: Bool { accountCode?.isEmpty == false }

    /// Validates and stores `rawCode`. Returns false (without changing state) if invalid.
    @discardableResult
    func setAccountCode(_ rawCode: String) -> Bool {
        let normalized = AlbumConfig.normalize(rawCode)
        guard AlbumConfig.isValidCode(normalized) else { return false }
        if normalized != accountCode {
            // Different account: drop stale albums until the next fetch.
            albums = []
            defaults.removeObject(forKey: manifestKey)
        }
        accountCode = normalized
        KeychainStore.set(normalized, forKey: codeKey)
        // The code is the account secret; keep it out of plaintext logs.
        logger.info("Account code set: \(normalized, privacy: .private)")
        return true
    }

    // MARK: - Fetch

    /// Fetches the account manifest over HTTPS and updates `albums`. Throws a `FetchError`
    /// (mapping 400/404 to friendly messages) on failure.
    @discardableResult
    func refresh() async throws -> [AlbumManifestAlbum] {
        guard hasAccountConfigured, let code = accountCode else { throw FetchError.notConfigured }
        guard let url = AlbumConfig.manifestURL(forCode: code) else { throw FetchError.invalidURL }

        var request = URLRequest(url: url)
        request.cachePolicy = .reloadIgnoringLocalCacheData

        let (data, response) = try await session.data(for: request)
        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            switch http.statusCode {
            case 400: throw FetchError.invalidCode
            case 404: throw FetchError.unknownCode
            case 429: throw FetchError.rateLimited
            default: throw FetchError.badResponse(http.statusCode)
            }
        }

        let manifest: AlbumManifest
        do {
            manifest = try JSONDecoder().decode(AlbumManifest.self, from: data)
        } catch {
            logger.error("Manifest decode failed: \(error.localizedDescription, privacy: .public)")
            throw FetchError.decodeFailed
        }

        albums = manifest.albums
        defaults.set(data, forKey: manifestKey)
        logger.info("Fetched \(manifest.albums.count) album(s)")
        return albums
    }

    // MARK: - Storage

    private func loadCachedManifest() {
        guard let data = defaults.data(forKey: manifestKey),
              let manifest = try? JSONDecoder().decode(AlbumManifest.self, from: data) else { return }
        albums = manifest.albums
    }
}
