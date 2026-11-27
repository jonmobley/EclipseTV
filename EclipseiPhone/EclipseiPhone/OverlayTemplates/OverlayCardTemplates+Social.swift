//
//  OverlayCardTemplates+Social.swift
//  Eclipse (iPhone/iPad port of the Mac file of the same name;
//  keep the Codable shapes identical to EclipsePro)
//
//  Description: Social card templates (Social Handle, Subscribe / Follow). Pure
//               data descriptors consumed by the template picker and editor;
//               wired into `OverlayCardTemplate.all`.
//  Thread Safety: Value types - no shared mutable state.
//

import SwiftUI

// MARK: - Social Templates

extension OverlayCardTemplate {

    /// Field keys for the Social Handle template.
    enum SocialHandleKey {
        static let handle = "handle"
        static let prompt = "prompt"
    }

    /// A social handle with an optional call-to-action line (e.g. "Follow us").
    static let socialHandle = OverlayCardTemplate(
        kind: .socialHandle,
        displayName: "Social Handle",
        menuIcon: "at",
        cardIcon: "at",
        category: .social,
        fields: [
            OverlayCardField(key: SocialHandleKey.handle, label: "Handle",
                             placeholder: "@yourhandle", isSecure: false),
            OverlayCardField(key: SocialHandleKey.prompt, label: "Prompt",
                             placeholder: "Follow us", isSecure: false)
        ],
        previewFields: [
            SocialHandleKey.handle: "@eclipsepro",
            SocialHandleKey.prompt: "Follow along"
        ],
        defaultStyle: OverlayCardLook.standard.style(showsIcon: true),
        title: { fields in trimmed(fields, SocialHandleKey.handle) ?? "@handle" },
        subtitle: { fields in trimmed(fields, SocialHandleKey.prompt) }
    )

    /// Field keys for the Subscribe / Follow CTA template.
    enum SubscribeCtaKey {
        static let cta = "cta"
        static let handle = "handle"
    }

    /// Livestream subscribe/follow call-to-action with a handle beneath.
    static let subscribeCta = OverlayCardTemplate(
        kind: .subscribeCta,
        displayName: "Subscribe / Follow",
        menuIcon: "bell.badge.fill",
        cardIcon: "bell.fill",
        category: .social,
        fields: [
            OverlayCardField(key: SubscribeCtaKey.cta, label: "Call to Action",
                             placeholder: "Subscribe", isSecure: false),
            OverlayCardField(key: SubscribeCtaKey.handle, label: "Handle",
                             placeholder: "@channel", isSecure: false)
        ],
        previewFields: [
            SubscribeCtaKey.cta: "Subscribe",
            SubscribeCtaKey.handle: "@eclipsepro"
        ],
        defaultStyle: OverlayCardLook.standard.style(showsIcon: true),
        title: { fields in trimmed(fields, SubscribeCtaKey.cta) ?? "Subscribe" },
        subtitle: { fields in trimmed(fields, SubscribeCtaKey.handle) }
    )

    /// Field keys for the Viewer Question template.
    enum ChatQuestionKey {
        static let question = "question"
        static let from = "from"
    }

    /// Live chat callout: viewer question with optional @handle attribution.
    static let chatQuestion = OverlayCardTemplate(
        kind: .chatQuestion,
        displayName: "Viewer Question",
        menuIcon: "bubble.left.fill",
        cardIcon: "bubble.left.fill",
        category: .social,
        fields: [
            OverlayCardField(key: ChatQuestionKey.question, label: "Question",
                             placeholder: "What did they ask?", isSecure: false),
            OverlayCardField(key: ChatQuestionKey.from, label: "From",
                             placeholder: "@viewer", isSecure: false)
        ],
        previewFields: [
            ChatQuestionKey.question: "Will this work with two cameras?",
            ChatQuestionKey.from: "@alex"
        ],
        defaultStyle: OverlayCardLook.standard.style(titleSize: 40),
        title: { fields in trimmed(fields, ChatQuestionKey.question) ?? "Question" },
        subtitle: { fields in trimmed(fields, ChatQuestionKey.from) }
    )
}
