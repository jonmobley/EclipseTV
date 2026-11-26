//
//  OverlayCardTemplates+Poll.swift
//  Eclipse (iPhone/iPad port of the Mac file of the same name;
//  keep the Codable shapes identical to EclipsePro)
//
//  Description: Poll / Question card template descriptor. Layout lives in
//               OverlayCardPollContent.
//  Thread Safety: Value types - no shared mutable state.
//

import SwiftUI

// MARK: - Poll Template

extension OverlayCardTemplate {

    /// Field keys for the Poll / Question template.
    enum PollKey {
        static let question = "question"
        static let optionA = "optionA"
        static let optionB = "optionB"
        static let optionC = "optionC"
        static let optionD = "optionD"

        /// Ordered option keys shown in the editor and layout.
        static let optionKeys = [optionA, optionB, optionC, optionD]

        static func optionLabel(_ key: String) -> String {
            switch key {
            case optionA: return "Option A"
            case optionB: return "Option B"
            case optionC: return "Option C"
            case optionD: return "Option D"
            default: return "Option"
            }
        }

        static func optionLetter(_ key: String) -> String {
            switch key {
            case optionA: return "A"
            case optionB: return "B"
            case optionC: return "C"
            case optionD: return "D"
            default: return "?"
            }
        }
    }

    /// Audience poll or Q&A prompt with up to four answer options.
    static let pollPrompt = OverlayCardTemplate(
        kind: .pollPrompt,
        displayName: "Poll / Question",
        menuIcon: "checklist",
        cardIcon: "checklist",
        category: .social,
        fields: pollFields,
        previewFields: [
            PollKey.question: "Which feature should we ship next?",
            PollKey.optionA: "Lower thirds",
            PollKey.optionB: "Scoreboards",
            PollKey.optionC: "Remote control",
            PollKey.optionD: ""
        ],
        defaultStyle: pollDefaultStyle,
        title: { fields in trimmed(fields, PollKey.question) ?? "Question" },
        subtitle: { fields in pollSubtitle(fields) }
    )

    private static var pollFields: [OverlayCardField] {
        [
            OverlayCardField(
                key: PollKey.question,
                label: "Question",
                placeholder: "Ask the audience…",
                isSecure: false
            )
        ] + PollKey.optionKeys.map { key in
            OverlayCardField(
                key: key,
                label: PollKey.optionLabel(key),
                placeholder: "Optional",
                isSecure: false
            )
        }
    }

    private static func pollSubtitle(_ fields: [String: String]) -> String? {
        let filled = PollKey.optionKeys.compactMap { trimmed(fields, $0) }
        guard !filled.isEmpty else { return nil }
        return filled.joined(separator: " · ")
    }

    private static var pollDefaultStyle: OverlayCardStyle {
        OverlayCardLook.standard.style(titleSize: 40)
    }
}
