//
//  OverlayCardScoreboardContent.swift
//  Eclipse (iPhone/iPad port of the Mac file of the same name;
//  keep the Codable shapes identical to EclipsePro)
//
//  Description: Visual layouts for sports scoreboard card templates — Team vs
//               Team, Match Board, Score + Clock, and Multiple Players — on
//               the shared card plate with scores at display size.
//  Thread Safety: Main thread only - SwiftUI view component.
//

import SwiftUI

// MARK: - OverlayCardScoreboardContent

/// Scoreboard card family.
///
/// Team names and period read at label size, scores at display size, so the
/// numbers lead from across a room. When `interactionOverlay` is set the
/// plate and labels go clear and only the score adjust buttons draw, so the
/// operator preview can stack this over the live card.
struct OverlayCardScoreboardContent: View {

    // MARK: - Properties

    let config: OverlayCardConfig

    /// Multiplier applied to every metric (1.0 == 1080p reference).
    var scale: CGFloat = 1.0

    /// Called with the score field key and delta when an operator taps − / +.
    var onAdjustScore: ((String, Int) -> Void)? = nil

    /// Draws only the invisible hit targets, for stacking over the live card.
    var interactionOverlay: Bool = false

    // MARK: - Constants

    enum Metric {
        /// Gap between the two team columns.
        static let teamSpacing: CGFloat = 32
        /// Gap between rows on the players board.
        static let rowSpacing: CGFloat = 10
        /// Narrowest team column so a short name still balances its score.
        static let minTeamWidth: CGFloat = 160
        /// Narrowest players board so names and scores do not crowd.
        static let minPlayersWidth: CGFloat = 440
    }

    var style: OverlayCardStyle { config.resolvedStyle }

    typealias TypeScale = OverlayCardTheme.TypeScale
    private typealias Space = OverlayCardTheme.Space
    private typealias Key = OverlayCardTemplate.ScoreboardKey

    // MARK: - Body

    var body: some View {
        Group {
            switch config.template {
            case .scoreboardVersus:
                versusBoard(showsPeriod: false, showsClock: false)
            case .scoreboardMatch:
                versusBoard(showsPeriod: true, showsClock: false)
            case .scoreboardClock:
                versusBoard(showsPeriod: true, showsClock: true)
            case .scoreboardSeries:
                seriesBoard
            case .scoreboardPlayers:
                playersBoard
            default:
                EmptyView()
            }
        }
        .modifier(PlatePadding(scale: scale))
        .modifier(ScoreboardPlate(
            style: style, scale: scale, interactionOverlay: interactionOverlay
        ))
        .fixedSize()
        // Container must allow hits so flanking buttons work, but clear
        // plate / labels opt out — only score buttons claim clicks.
        .allowsHitTesting(interactionOverlay)
    }

    // MARK: - Team Boards

    private func versusBoard(showsPeriod: Bool, showsClock: Bool) -> some View {
        let home = OverlayCardTemplate.trimmed(config.fields, Key.homeName) ?? "Home"
        let away = OverlayCardTemplate.trimmed(config.fields, Key.awayName) ?? "Away"
        let homeScore = OverlayCardTemplate.scoreboardScore(
            from: config.fields, key: Key.homeScore
        )
        let awayScore = OverlayCardTemplate.scoreboardScore(
            from: config.fields, key: Key.awayScore
        )
        let period = OverlayCardTemplate.trimmed(config.fields, Key.period)
        let clock = OverlayCardTemplate.trimmed(config.fields, Key.clock)
        return VStack(spacing: Space.lineGap * scale) {
            if showsPeriod || showsClock {
                periodClockHeader(
                    period: showsPeriod ? period : nil,
                    clock: showsClock ? clock : nil
                )
            }
            HStack(spacing: Metric.teamSpacing * scale) {
                teamColumn(
                    name: home, score: homeScore, scoreKey: Key.homeScore,
                    alignment: .trailing
                )
                scoreDivider
                teamColumn(
                    name: away, score: awayScore, scoreKey: Key.awayScore,
                    alignment: .leading
                )
            }
        }
    }

    /// Thin dash between the two scores, in the accent so it marks the family.
    var scoreDivider: some View {
        Text("–")
            .font(.system(
                size: TypeScale.display(for: style) * 0.4 * scale,
                weight: .semibold,
                design: style.fontDesign.design
            ))
            .foregroundColor(labelColor(style.resolvedAccent.color))
            .allowsHitTesting(false)
    }

    @ViewBuilder
    private func periodClockHeader(period: String?, clock: String?) -> some View {
        let periodText = period?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let clockText = clock?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !periodText.isEmpty || !clockText.isEmpty {
            HStack(spacing: Space.stackGap * scale) {
                if !periodText.isEmpty {
                    boardLabel(periodText)
                }
                if !clockText.isEmpty {
                    Text(clockText)
                        .font(.system(
                            size: TypeScale.label(for: style) * scale,
                            weight: .bold,
                            design: .monospaced
                        ))
                        .foregroundColor(labelColor(style.textColor.color))
                        .monospacedDigit()
                }
            }
            .padding(.bottom, Space.lineGap * scale)
            .allowsHitTesting(false)
        }
    }

    private func teamColumn(
        name: String,
        score: Int,
        scoreKey: String,
        alignment: HorizontalAlignment
    ) -> some View {
        VStack(alignment: alignment, spacing: 0) {
            boardLabel(name)
            scoreValue(
                score,
                key: scoreKey,
                fontSize: TypeScale.display(for: style) * scale
            )
        }
        .frame(minWidth: Metric.minTeamWidth * scale, alignment: Alignment(
            horizontal: alignment,
            vertical: .center
        ))
    }

    // MARK: - Players Board

    private var playersBoard: some View {
        let rows = playerRows
        let title = OverlayCardTemplate.trimmed(config.fields, Key.boardTitle)
        return VStack(alignment: .leading, spacing: Metric.rowSpacing * scale) {
            if let title {
                boardLabel(title)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.bottom, Space.lineGap * scale)
            }
            if rows.isEmpty {
                Text("Add players")
                    .font(.system(
                        size: style.subtitleSize * scale,
                        weight: .medium,
                        design: style.fontDesign.design
                    ))
                    .foregroundColor(labelColor(style.subtitleColor.color.opacity(0.6)))
                    .allowsHitTesting(false)
            } else {
                ForEach(rows, id: \.key) { row in
                    playerRow(name: row.name, score: row.score, scoreKey: row.key)
                }
            }
        }
        .frame(minWidth: Metric.minPlayersWidth * scale)
    }

    private var playerRows: [(name: String, score: Int, key: String)] {
        var rows: [(name: String, score: Int, key: String)] = []
        for index in 1...Key.maxPlayers {
            guard let name = OverlayCardTemplate.trimmed(
                config.fields, Key.playerName(index)
            ) else { continue }
            let key = Key.playerScore(index)
            let score = OverlayCardTemplate.scoreboardScore(
                from: config.fields, key: key
            )
            rows.append((name, score, key))
        }
        return rows
    }

    private func playerRow(
        name: String,
        score: Int,
        scoreKey: String
    ) -> some View {
        HStack(spacing: Space.inlineGap * scale) {
            Text(name)
                .font(.system(
                    size: style.subtitleSize * scale,
                    weight: .semibold,
                    design: style.fontDesign.design
                ))
                .foregroundColor(labelColor(style.textColor.color))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .allowsHitTesting(false)
            Spacer(minLength: Space.inlineGap * scale)
                .allowsHitTesting(false)
            scoreValue(
                score,
                key: scoreKey,
                fontSize: style.titleSize * scale
            )
        }
    }

    // MARK: - Shared Pieces

    /// Uppercase accent label (team name, period, board title, series label).
    func boardLabel(_ text: String) -> some View {
        Text(text.uppercased())
            .font(.system(
                size: TypeScale.label(for: style) * scale,
                weight: .semibold,
                design: style.fontDesign.design
            ))
            .tracking(TypeScale.labelTracking * scale)
            .foregroundColor(labelColor(style.resolvedAccent.color))
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .allowsHitTesting(false)
    }
}

// MARK: - ScoreboardPlate

/// The shared plate, or nothing at all when the board is only an invisible
/// layer of hit targets over the live card.
private struct ScoreboardPlate: ViewModifier {

    let style: OverlayCardStyle
    let scale: CGFloat
    let interactionOverlay: Bool

    func body(content: Content) -> some View {
        if interactionOverlay {
            content.background(Color.clear.allowsHitTesting(false))
        } else {
            content.cardPlate(style: style, scale: scale)
        }
    }
}
