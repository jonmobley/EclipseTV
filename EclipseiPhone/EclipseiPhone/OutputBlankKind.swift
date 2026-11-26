//
//  OutputBlankKind.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import UIKit

/// The colour Blackout puts on the audience screen: Black or White, as on the Mac.
///
/// The choice is remembered, so a tap on Blackout puts up the last one picked;
/// a long press on the button picks the other.
enum OutputBlankKind: String, CaseIterable, Codable, Equatable {
    case black
    case white

    /// Word on the menu and for VoiceOver.
    var title: String {
        switch self {
        case .black: return "Black"
        case .white: return "White"
        }
    }

    /// Badge on the live picture, in the Mac's words ("Black Screen").
    var badgeText: String { "\(title.uppercased()) SCREEN" }

    /// Spoken / overlay name ("Black Screen").
    var screenName: String { "\(title) Screen" }

    /// Fill the audience screen takes.
    var fillColor: UIColor {
        switch self {
        case .black: return .black
        case .white: return .white
        }
    }

    /// Menu glyph: an outlined rectangle for Black, filled for White (as on the Mac).
    var systemImage: String {
        switch self {
        case .black: return "rectangle"
        case .white: return "rectangle.fill"
        }
    }

    // MARK: - Remembered Choice

    private static let defaultsKey = "outputBlankKind"

    /// The last colour picked; Black until White is chosen.
    static var current: OutputBlankKind {
        get {
            UserDefaults.standard.string(forKey: defaultsKey)
                .flatMap(OutputBlankKind.init(rawValue:)) ?? .black
        }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: defaultsKey) }
    }
}
