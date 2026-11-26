//
//  OverlayCardTemplates+Scoreboard.swift
//  Eclipse (iPhone/iPad port of the Mac file of the same name;
//  keep the Codable shapes identical to EclipsePro)
//
//  Description: Sports scoreboard card templates — Team vs Team, Match Board,
//               Multiple Players, and Score + Clock. Descriptors only; layout
//               lives in OverlayCardScoreboardContent.
//  Thread Safety: Value types - no shared mutable state.
//

import SwiftUI

// MARK: - Scoreboard Keys

extension OverlayCardTemplate {

    /// Shared field keys for sports scoreboard templates.
    enum ScoreboardKey {
        static let homeName = "homeName"
        static let homeScore = "homeScore"
        static let awayName = "awayName"
        static let awayScore = "awayScore"
        static let period = "period"
        static let clock = "clock"
        static let boardTitle = "boardTitle"

        /// Maximum named rows on the Multiple Players board.
        static let maxPlayers = 6

        static func playerName(_ index: Int) -> String { "player\(index)Name" }
        static func playerScore(_ index: Int) -> String { "player\(index)Score" }
    }

    // MARK: - Team vs Team

    /// Classic two-team score bug: names flanking a large score pair.
    static let scoreboardVersus = OverlayCardTemplate(
        kind: .scoreboardVersus,
        displayName: "Team vs Team",
        menuIcon: "sportscourt",
        cardIcon: "sportscourt",
        category: .sports,
        fields: versusFields(includePeriod: false),
        previewFields: [
            ScoreboardKey.homeName: "Home",
            ScoreboardKey.homeScore: "3",
            ScoreboardKey.awayName: "Away",
            ScoreboardKey.awayScore: "2"
        ],
        defaultStyle: scoreboardDefaultStyle,
        title: { fields in versusTitle(fields) },
        subtitle: { _ in nil }
    )

    // MARK: - Match Board

    /// Team vs Team with a period / quarter / set label above the scores.
    static let scoreboardMatch = OverlayCardTemplate(
        kind: .scoreboardMatch,
        displayName: "Match Board",
        menuIcon: "flag.checkered",
        cardIcon: "flag.checkered",
        category: .sports,
        fields: versusFields(includePeriod: true),
        previewFields: [
            ScoreboardKey.homeName: "Eagles",
            ScoreboardKey.homeScore: "24",
            ScoreboardKey.awayName: "Hawks",
            ScoreboardKey.awayScore: "21",
            ScoreboardKey.period: "Q3"
        ],
        defaultStyle: scoreboardDefaultStyle,
        title: { fields in versusTitle(fields) },
        subtitle: { fields in trimmed(fields, ScoreboardKey.period) }
    )

    // MARK: - Score + Clock

    /// Team scores with period and game clock for a full sports bug.
    static let scoreboardClock = OverlayCardTemplate(
        kind: .scoreboardClock,
        displayName: "Score + Clock",
        menuIcon: "timer",
        cardIcon: "timer",
        category: .sports,
        fields: versusFields(includePeriod: true, includeClock: true),
        previewFields: [
            ScoreboardKey.homeName: "Eagles",
            ScoreboardKey.homeScore: "24",
            ScoreboardKey.awayName: "Hawks",
            ScoreboardKey.awayScore: "21",
            ScoreboardKey.period: "Q3",
            ScoreboardKey.clock: "4:32"
        ],
        defaultStyle: scoreboardDefaultStyle,
        title: { fields in versusTitle(fields) },
        subtitle: { fields in clockSubtitle(fields) }
    )

    // MARK: - Multiple Players

    /// Ranked name + score rows for multi-player games or contests.
    static let scoreboardPlayers = OverlayCardTemplate(
        kind: .scoreboardPlayers,
        displayName: "Multiple Players",
        menuIcon: "list.number",
        cardIcon: "list.number",
        category: .sports,
        fields: playerFields,
        previewFields: [
            ScoreboardKey.boardTitle: "Leaderboard",
            ScoreboardKey.playerName(1): "Alex",
            ScoreboardKey.playerScore(1): "12",
            ScoreboardKey.playerName(2): "Blake",
            ScoreboardKey.playerScore(2): "9",
            ScoreboardKey.playerName(3): "Casey",
            ScoreboardKey.playerScore(3): "7"
        ],
        defaultStyle: scoreboardDefaultStyle,
        title: { fields in
            trimmed(fields, ScoreboardKey.boardTitle)
                ?? firstPlayerName(fields)
                ?? "Players"
        },
        subtitle: { fields in playersSubtitle(fields) }
    )

    // MARK: - Field Builders

    private static func versusFields(
        includePeriod: Bool,
        includeClock: Bool = false
    ) -> [OverlayCardField] {
        var fields = [
            OverlayCardField(
                key: ScoreboardKey.homeName,
                label: "Home Team",
                placeholder: "Home",
                isSecure: false
            ),
            OverlayCardField(
                key: ScoreboardKey.homeScore,
                label: "Home Score",
                placeholder: "0",
                isSecure: false
            ),
            OverlayCardField(
                key: ScoreboardKey.awayName,
                label: "Away Team",
                placeholder: "Away",
                isSecure: false
            ),
            OverlayCardField(
                key: ScoreboardKey.awayScore,
                label: "Away Score",
                placeholder: "0",
                isSecure: false
            )
        ]
        if includePeriod {
            fields.append(
                OverlayCardField(
                    key: ScoreboardKey.period,
                    label: "Period",
                    placeholder: "Q1",
                    isSecure: false
                )
            )
        }
        if includeClock {
            fields.append(
                OverlayCardField(
                    key: ScoreboardKey.clock,
                    label: "Clock",
                    placeholder: "12:00",
                    isSecure: false
                )
            )
        }
        return fields
    }

    private static var playerFields: [OverlayCardField] {
        var fields = [
            OverlayCardField(
                key: ScoreboardKey.boardTitle,
                label: "Title",
                placeholder: "Leaderboard",
                isSecure: false
            )
        ]
        for index in 1...ScoreboardKey.maxPlayers {
            fields.append(
                OverlayCardField(
                    key: ScoreboardKey.playerName(index),
                    label: "Player \(index)",
                    placeholder: "Name",
                    isSecure: false
                )
            )
            fields.append(
                OverlayCardField(
                    key: ScoreboardKey.playerScore(index),
                    label: "Score \(index)",
                    placeholder: "0",
                    isSecure: false
                )
            )
        }
        return fields
    }

    // MARK: - Display Helpers

    private static func versusTitle(_ fields: [String: String]) -> String {
        let home = trimmed(fields, ScoreboardKey.homeName) ?? "Home"
        let away = trimmed(fields, ScoreboardKey.awayName) ?? "Away"
        let hs = trimmed(fields, ScoreboardKey.homeScore) ?? "0"
        let ascore = trimmed(fields, ScoreboardKey.awayScore) ?? "0"
        return "\(home) \(hs) – \(ascore) \(away)"
    }

    private static func firstPlayerName(_ fields: [String: String]) -> String? {
        for index in 1...ScoreboardKey.maxPlayers {
            if let name = trimmed(fields, ScoreboardKey.playerName(index)) {
                return name
            }
        }
        return nil
    }

    private static func playersSubtitle(_ fields: [String: String]) -> String? {
        var names: [String] = []
        for index in 1...ScoreboardKey.maxPlayers {
            if let name = trimmed(fields, ScoreboardKey.playerName(index)) {
                names.append(name)
            }
        }
        guard names.count > 1 else { return nil }
        return names.dropFirst().joined(separator: ", ")
    }

    private static func clockSubtitle(_ fields: [String: String]) -> String? {
        let period = trimmed(fields, ScoreboardKey.period)
        let clock = trimmed(fields, ScoreboardKey.clock)
        switch (period, clock) {
        case let (period?, clock?): return "\(period) · \(clock)"
        case let (period?, nil): return period
        case let (nil, clock?): return clock
        case (nil, nil): return nil
        }
    }

    /// Dark translucent broadcast bug — high-contrast scores on program video.
    /// Shared by every scoreboard: the default look with centered text and
    /// the title size that drives the score digits.
    static var scoreboardDefaultStyle: OverlayCardStyle {
        OverlayCardLook.standard.style(textAlignment: .center)
    }
}

// MARK: - Score Parsing

extension OverlayCardTemplate {

    /// Parses a score field as a non-negative integer (default 0).
    static func scoreboardScore(from fields: [String: String], key: String) -> Int {
        let raw = trimmed(fields, key) ?? "0"
        return max(0, Int(raw) ?? 0)
    }

    /// Applies a delta to a score string, clamped to 0…999.
    static func adjustedScoreboardScore(_ raw: String, delta: Int) -> String {
        let current = Int(raw.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0
        return String(max(0, min(999, current + delta)))
    }

    /// Appends a named player on the next empty Multiple Players slot.
    ///
    /// - Parameters:
    ///   - fields: Current scoreboard field map.
    ///   - name: Display name for the new row.
    ///   - score: Starting score (clamped to 0…999).
    /// - Returns: Updated fields, or `nil` when the name is empty or the board
    ///   is already full.
    static func appendingScoreboardPlayer(
        to fields: [String: String],
        name: String,
        score: Int = 0
    ) -> [String: String]? {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { return nil }
        let key = ScoreboardKey.self
        guard let slot = (1...key.maxPlayers).first(where: {
            trimmed(fields, key.playerName($0)) == nil
        }) else { return nil }
        var updated = fields
        updated[key.playerName(slot)] = trimmedName
        updated[key.playerScore(slot)] = String(max(0, min(999, score)))
        return updated
    }
}
