//
//  CompanionSettings.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import Foundation

/// Single source of truth for companion preferences that more than one type reads.
///
/// These were previously redeclared as private string constants in both the Settings UI
/// and the connection layer, where a typo in either copy would silently decouple a toggle
/// from the behaviour it is supposed to control.
enum CompanionSettings {

    private static let syncAllTVsKey = "EclipseTV.companion.syncAllTVs"
    private static let preferredTVNameKey = "EclipseTV.companion.preferredTVName"

    /// When true, library mutations fan out to every connected Apple TV and extra
    /// discovered TVs are kept connected as sync replicas.
    static var syncAllTVs: Bool {
        get { UserDefaults.standard.bool(forKey: syncAllTVsKey) }
        set { UserDefaults.standard.set(newValue, forKey: syncAllTVsKey) }
    }

    /// The Apple TV (by device name) the user last chose to view; auto-connect prefers it
    /// over the first-discovered peer. Nil means no preference.
    static var preferredTVName: String? {
        get { UserDefaults.standard.string(forKey: preferredTVNameKey) }
        set { UserDefaults.standard.set(newValue, forKey: preferredTVNameKey) }
    }
}
