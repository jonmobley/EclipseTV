//
//  JoinedAccountReconcile.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import Foundation

/// Merge rule for the hosted-album join code when a TV reports its account.
enum JoinedAccountReconcile {
    /// Posted when phone and TV have different valid join codes.
    static let conflictNotification = Notification.Name(
        "JoinedAccountReconcile.conflict"
    )

    enum Outcome: Equatable {
        case adoptTV(String)
        case pushPhone(String)
        case conflict(phone: String, tv: String)
        case none
    }

    /// Decides how phone and TV join codes should meet.
    ///
    /// Empty phone adopts the TV. Empty TV gets the phone's code. Matching codes
    /// are a no-op. Differing codes are a conflict — neither side is overwritten.
    static func outcome(phone: String?, tv: String?) -> Outcome {
        let phoneCode = normalized(phone)
        let tvCode = normalized(tv)
        switch (phoneCode, tvCode) {
        case (nil, nil):
            return .none
        case (nil, let tv?):
            return .adoptTV(tv)
        case (let phone?, nil):
            return .pushPhone(phone)
        case (let phone?, let tv?):
            return phone == tv ? .none : .conflict(phone: phone, tv: tv)
        }
    }

    private static func normalized(_ raw: String?) -> String? {
        guard let raw else { return nil }
        let code = AlbumConfig.normalize(raw)
        return AlbumConfig.isValidCode(code) ? code : nil
    }
}
