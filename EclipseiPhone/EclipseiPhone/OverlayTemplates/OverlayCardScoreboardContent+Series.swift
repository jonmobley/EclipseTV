//
//  OverlayCardScoreboardContent+Series.swift
//  Eclipse (iPhone/iPad port of the Mac file of the same name;
//  keep the Codable shapes identical to EclipsePro)
//
//  Description: Best of N series-wins layout for `.scoreboardSeries` overlays.
//  Thread Safety: Main thread only - SwiftUI view component.
//

import SwiftUI

// MARK: - Series Board

extension OverlayCardScoreboardContent {

    /// Series label over two columns of wins, each tagged "wins".
    @ViewBuilder
    var seriesBoard: some View {
        let key = OverlayCardTemplate.SeriesKey.self
        let home = OverlayCardTemplate.trimmed(config.fields, key.homeName) ?? "Home"
        let away = OverlayCardTemplate.trimmed(config.fields, key.awayName) ?? "Away"
        let homeWins = OverlayCardTemplate.scoreboardScore(
            from: config.fields, key: key.homeWins
        )
        let awayWins = OverlayCardTemplate.scoreboardScore(
            from: config.fields, key: key.awayWins
        )
        let label = OverlayCardTemplate.trimmed(config.fields, key.seriesLabel)
        VStack(spacing: OverlayCardTheme.Space.lineGap * scale) {
            if let label {
                boardLabel(label)
                    .padding(.bottom, OverlayCardTheme.Space.lineGap * scale)
            }
            HStack(spacing: Metric.teamSpacing * scale) {
                seriesColumn(
                    name: home, wins: homeWins, scoreKey: key.homeWins,
                    alignment: .trailing
                )
                scoreDivider
                seriesColumn(
                    name: away, wins: awayWins, scoreKey: key.awayWins,
                    alignment: .leading
                )
            }
        }
    }

    private func seriesColumn(
        name: String,
        wins: Int,
        scoreKey: String,
        alignment: HorizontalAlignment
    ) -> some View {
        VStack(alignment: alignment, spacing: 0) {
            boardLabel(name)
            scoreValue(
                wins,
                key: scoreKey,
                fontSize: TypeScale.display(for: style) * scale
            )
            Text("Wins")
                .font(.system(
                    size: TypeScale.label(for: style) * scale,
                    weight: .medium,
                    design: style.fontDesign.design
                ))
                .foregroundColor(labelColor(style.subtitleColor.color))
                .allowsHitTesting(false)
        }
        .frame(minWidth: Metric.minTeamWidth * scale, alignment: Alignment(
            horizontal: alignment,
            vertical: .center
        ))
    }
}
