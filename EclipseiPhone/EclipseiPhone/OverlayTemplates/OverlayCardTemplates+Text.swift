//
//  OverlayCardTemplates+Text.swift
//  Eclipse (iPhone/iPad port of the Mac file of the same name;
//  keep the Codable shapes identical to EclipsePro)
//
//  Description: Text-forward card templates (Title/Subtitle, Scripture). Pure
//               data descriptors consumed by the template picker and editor;
//               wired into `OverlayCardTemplate.all`.
//  Thread Safety: Value types - no shared mutable state.
//

import SwiftUI

// MARK: - Text Templates

extension OverlayCardTemplate {

    /// Field keys for the Title / Subtitle template.
    enum TitleSubtitleKey {
        static let title = "title"
        static let subtitle = "subtitle"
    }

    /// A generic headline with an optional supporting line.
    static let titleSubtitle = OverlayCardTemplate(
        kind: .titleSubtitle,
        displayName: "Title & Subtitle",
        menuIcon: "textformat",
        cardIcon: "text.alignleft",
        category: .info,
        fields: [
            OverlayCardField(key: TitleSubtitleKey.title, label: "Title",
                             placeholder: "Title", isSecure: false),
            OverlayCardField(key: TitleSubtitleKey.subtitle, label: "Subtitle",
                             placeholder: "Subtitle", isSecure: false)
        ],
        previewFields: [
            TitleSubtitleKey.title: "Welcome",
            TitleSubtitleKey.subtitle: "We're glad you're here"
        ],
        defaultStyle: OverlayCardLook.standard.style(),
        title: { fields in trimmed(fields, TitleSubtitleKey.title) ?? "Title" },
        subtitle: { fields in trimmed(fields, TitleSubtitleKey.subtitle) }
    )

    /// Field keys for the Scripture template.
    enum ScriptureKey {
        static let reference = "reference"
        static let verse = "verse"
    }

    /// A verse plate: reference eyebrow above large serif passage text.
    static let scripture = OverlayCardTemplate(
        kind: .scripture,
        displayName: "Scripture",
        menuIcon: "book.closed",
        cardIcon: "book.fill",
        category: .info,
        fields: [
            OverlayCardField(key: ScriptureKey.reference, label: "Reference",
                             placeholder: "John 3:16", isSecure: false),
            OverlayCardField(key: ScriptureKey.verse, label: "Verse",
                             placeholder: "Passage text", isSecure: false)
        ],
        previewFields: [
            ScriptureKey.reference: "John 3:16",
            ScriptureKey.verse: "For God so loved the world, that he gave "
                + "his only Son, that whoever believes in him should not "
                + "perish but have eternal life."
        ],
        defaultStyle: scriptureDefaultStyle,
        title: { fields in trimmed(fields, ScriptureKey.reference) ?? "Scripture" },
        subtitle: { fields in trimmed(fields, ScriptureKey.verse) }
    )

    /// Field keys for the Term / Definition template.
    enum QuizTermKey {
        static let term = "term"
        static let definition = "definition"
    }

    /// Education flashcard-style term with definition beneath.
    static let quizTerm = OverlayCardTemplate(
        kind: .quizTerm,
        displayName: "Term / Definition",
        menuIcon: "text.book.closed",
        cardIcon: "text.book.closed.fill",
        category: .info,
        fields: [
            OverlayCardField(key: QuizTermKey.term, label: "Term",
                             placeholder: "Term", isSecure: false),
            OverlayCardField(key: QuizTermKey.definition, label: "Definition",
                             placeholder: "Definition", isSecure: false)
        ],
        previewFields: [
            QuizTermKey.term: "Latency",
            QuizTermKey.definition: "The delay between a cause and its effect."
        ],
        defaultStyle: OverlayCardLook.worship.style(),
        title: { fields in trimmed(fields, QuizTermKey.term) ?? "Term" },
        subtitle: { fields in trimmed(fields, QuizTermKey.definition) }
    )

    /// Scripture reads in the Worship look: ivory serif on warm charcoal, the
    /// reference as a gold eyebrow above a verse at secondary size.
    private static var scriptureDefaultStyle: OverlayCardStyle {
        OverlayCardLook.worship.style(
            titleSize: OverlayCardTheme.TypeScale.label,
            subtitleSize: 38
        )
    }
}
