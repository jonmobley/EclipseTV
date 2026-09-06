//
//  LivePollAccountStore.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import Foundation
import LivePollKit

/// Keychain-backed Live Poll account for the iPhone app.
enum LivePollAccountStore {

    private static let legacyPINKey = "Eclipse.questpoll.hostPin"
    private static let migrationPromptedKey = "Eclipse.livepoll.didPromptPINMigration"

    /// Account store wired to Eclipse's Keychain helper.
    static let shared: LivePollAccount = LivePollAccount(
        keychainGet: { KeychainStore.string(forKey: $0) },
        keychainSet: { KeychainStore.set($0, forKey: $1) },
        keychainRemove: { KeychainStore.removeValue(forKey: $0) }
    )

    /// HTTPS client using the signed-in account token when present.
    static func client() -> LivePollClient {
        LivePollClient(accountToken: shared.accountToken)
    }

    /// Whether an account bearer token is stored.
    static var isSignedIn: Bool { shared.isSignedIn }

    /// Clears a leftover QuestPoll PIN and returns whether the sign-in sheet
    /// should explain the PIN → email migration.
    ///
    /// Call when presenting email sign-in. Existing PIN users are prompted
    /// once; the PIN itself cannot become an account token.
    @discardableResult
    static func prepareEmailSignInPrompt() -> Bool {
        migrateLegacyUserDefaultsPINIfNeeded()
        let hasPIN = !(KeychainStore.string(forKey: legacyPINKey)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? "").isEmpty
        if hasPIN {
            KeychainStore.removeValue(forKey: legacyPINKey)
            UserDefaults.standard.removeObject(forKey: legacyPINKey)
        }
        guard hasPIN, !shared.isSignedIn else { return false }
        let alreadyPrompted = UserDefaults.standard.bool(forKey: migrationPromptedKey)
        UserDefaults.standard.set(true, forKey: migrationPromptedKey)
        return !alreadyPrompted
    }

    /// Signs out and clears any leftover legacy PIN.
    static func signOut() {
        shared.signOut()
        KeychainStore.removeValue(forKey: legacyPINKey)
        UserDefaults.standard.removeObject(forKey: legacyPINKey)
    }

    // MARK: - Private

    private static func migrateLegacyUserDefaultsPINIfNeeded() {
        guard let legacy = UserDefaults.standard.string(forKey: legacyPINKey)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
            !legacy.isEmpty
        else { return }
        if KeychainStore.string(forKey: legacyPINKey)?.isEmpty != false {
            KeychainStore.set(legacy, forKey: legacyPINKey)
        }
        UserDefaults.standard.removeObject(forKey: legacyPINKey)
    }
}
