//
//  OverlayCardTemplates+Series.swift
//  Eclipse (iPhone/iPad port of the Mac file of the same name;
//  keep the Codable shapes identical to EclipsePro)
//
//  Description: Best of N / series-score card template. Descriptor only; layout
//               lives in OverlayCardScoreboardContent+Series.
//  Thread Safety: Value types - no shared mutable state.
//

import SwiftUI

// MARK: - Series Score Template

extension OverlayCardTemplate {

    /// Field keys for the Best of N series scoreboard.
    enum SeriesKey {
        static let homeName = "homeName"
        static let homeWins = "homeWins"
        static let awayName = "awayName"
        static let awayWins = "awayWins"
        static let seriesLabel = "seriesLabel"
    }

    /// Playoff / series wins bug (e.g. Best of 7).
    static let scoreboardSeries = OverlayCardTemplate(
        kind: .scoreboardSeries,
        displayName: "Best of N",
        menuIcon: "trophy",
        cardIcon: "trophy.fill",
        category: .sports,
        fields: seriesFields,
        previewFields: [
            SeriesKey.homeName: "Eagles",
            SeriesKey.homeWins: "3",
            SeriesKey.awayName: "Hawks",
            SeriesKey.awayWins: "2",
            SeriesKey.seriesLabel: "Best of 7"
        ],
        defaultStyle: seriesDefaultStyle,
        title: { fields in seriesTitle(fields) },
        subtitle: { fields in trimmed(fields, SeriesKey.seriesLabel) }
    )

    private static var seriesFields: [OverlayCardField] {
        [
            OverlayCardField(
                key: SeriesKey.homeName,
                label: "Home Team",
                placeholder: "Home",
                isSecure: false
            ),
            OverlayCardField(
                key: SeriesKey.homeWins,
                label: "Home Wins",
                placeholder: "0",
                isSecure: false
            ),
            OverlayCardField(
                key: SeriesKey.awayName,
                label: "Away Team",
                placeholder: "Away",
                isSecure: false
            ),
            OverlayCardField(
                key: SeriesKey.awayWins,
                label: "Away Wins",
                placeholder: "0",
                isSecure: false
            ),
            OverlayCardField(
                key: SeriesKey.seriesLabel,
                label: "Series",
                placeholder: "Best of 7",
                isSecure: false
            )
        ]
    }

    private static func seriesTitle(_ fields: [String: String]) -> String {
        let home = trimmed(fields, SeriesKey.homeName) ?? "Home"
        let away = trimmed(fields, SeriesKey.awayName) ?? "Away"
        let hw = trimmed(fields, SeriesKey.homeWins) ?? "0"
        let aw = trimmed(fields, SeriesKey.awayWins) ?? "0"
        return "\(home) \(hw) – \(aw) \(away)"
    }

    private static var seriesDefaultStyle: OverlayCardStyle {
        OverlayCardTemplate.scoreboardDefaultStyle
    }
}
