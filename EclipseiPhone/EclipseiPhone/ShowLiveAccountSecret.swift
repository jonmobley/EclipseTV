//
//  ShowLiveAccountSecret.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import CryptoKit
import Foundation
import Security

/// Result of looking up the Show Live account secret.
enum ShowLiveSecretRead: Equatable {
    /// The stored secret.
    case found(Data)
    /// Nothing stored yet on this account.
    case missing
    /// The Keychain can't answer right now (locked before first unlock, or an
    /// error). Show Live stays off and tries again the next time a Show opens.
    case unavailable
}

/// Where the account secret lives. The app uses ``ShowLiveKeychainSecretStore``;
/// tests use an in-memory store.
protocol ShowLiveSecretStore {
    /// Reads the stored secret.
    /// - Returns: What the store found.
    func read() -> ShowLiveSecretRead
    /// Stores a new secret.
    /// - Parameter secret: Random bytes to keep.
    /// - Returns: `errSecSuccess`, `errSecDuplicateItem`, or another status.
    func add(_ secret: Data) -> OSStatus
}

/// A random secret shared by every device on one iCloud account, used to prove
/// two phones belong to the same owner before Show Live trusts them.
///
/// It replaces a key made from the iCloud user record name, which people the
/// owner shares a CloudKit record with can see. The secret is made once, on the
/// first device that needs it, and iCloud Keychain copies it to the owner's
/// other devices. It never leaves the account's Keychain except as a key in
/// memory. Pure apart from the store, so tests need no Keychain.
enum ShowLiveAccountSecret {

    /// Length of the secret in bytes (256 bits).
    static let byteCount = 32

    /// Returns the account secret, creating it when this account has none yet.
    /// - Parameter store: Where the secret is kept.
    /// - Returns: The secret, or nil while the Keychain can't be used. Callers
    ///   keep Show Live off and ask again later; there is deliberately no
    ///   weaker key to fall back to.
    static func loadOrCreate(
        store: ShowLiveSecretStore = ShowLiveKeychainSecretStore()
    ) -> Data? {
        switch store.read() {
        case .found(let secret):
            return secret.count == byteCount ? secret : nil
        case .unavailable:
            return nil
        case .missing:
            return create(in: store)
        }
    }

    private static func create(in store: ShowLiveSecretStore) -> Data? {
        let fresh = SymmetricKey(size: .bits256).withUnsafeBytes { Data($0) }
        switch store.add(fresh) {
        case errSecSuccess:
            return fresh
        case errSecDuplicateItem:
            // Another launch (or iCloud) stored one first; use that one.
            if case .found(let secret) = store.read(), secret.count == byteCount {
                return secret
            }
            return nil
        default:
            return nil
        }
    }
}

/// Keeps the account secret in iCloud Keychain (`kSecAttrSynchronizable`), so
/// all of the owner's devices end up with the same value.
///
/// Thread safety: stateless; Keychain calls are safe from any thread.
struct ShowLiveKeychainSecretStore: ShowLiveSecretStore {
    private static let service = "com.eclipseapp.ios.showlive"
    private static let account = "account-secret.v1"

    private var baseQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.service,
            kSecAttrAccount as String: Self.account,
            kSecAttrSynchronizable as String: kCFBooleanTrue as Any
        ]
    }

    func read() -> ShowLiveSecretRead {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        switch status {
        case errSecSuccess:
            guard let data = result as? Data else { return .unavailable }
            return .found(data)
        case errSecItemNotFound:
            return .missing
        default:
            return .unavailable
        }
    }

    func add(_ secret: Data) -> OSStatus {
        var query = baseQuery
        query[kSecValueData as String] = secret
        // Synchronizable items can't be "this device only"; after first unlock
        // lets Show Live start from the background once the phone was unlocked.
        query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        return SecItemAdd(query as CFDictionary, nil)
    }
}
