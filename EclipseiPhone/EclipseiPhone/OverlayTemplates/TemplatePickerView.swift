//
//  TemplatePickerView.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//
//  Description: The "Template…" sheet: the Mac's category chips over a grid
//               of template previews; choosing one opens the field editor.
//  Thread Safety: Main thread only - SwiftUI view.
//

import SwiftUI

// MARK: - TemplatePickerView

/// Lists every template, filtered by the Mac's categories.
struct TemplatePickerView: View {

    // MARK: - Properties

    let showId: UUID
    /// Called with the new card's id after Add.
    let onAdded: (UUID) -> Void
    let onCancel: () -> Void

    @State private var category: OverlayCardCategory?
    @State private var chosen: OverlayCardTemplateKind?

    private let columns = [GridItem(.adaptive(minimum: 150, maximum: 240), spacing: 12)]

    private var filtered: [OverlayCardTemplate] {
        OverlayCardTemplate.all.filter { category == nil || $0.category == category }
    }

    private var categories: [OverlayCardCategory] {
        OverlayCardCategory.allCases.filter { kind in
            OverlayCardTemplate.all.contains { $0.category == kind }
        }
    }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    chips
                    LazyVGrid(columns: columns, spacing: 12) {
                        ForEach(filtered) { template in
                            tile(template)
                        }
                    }
                    .padding(.horizontal, 16)
                }
                .padding(.vertical, 8)
            }
            .navigationTitle("Templates")
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(item: $chosen) { kind in
                TemplateEditorView(
                    draft: TemplateCardDraft(newCardOf: kind),
                    isNew: true,
                    onCommit: { draft in
                        let card = TemplateCardStore.shared.create(
                            config: draft.config, name: draft.name, showId: showId
                        )
                        onAdded(card.id)
                    },
                    onCancel: { chosen = nil }
                )
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: onCancel)
                }
            }
        }
    }

    // MARK: - Subviews

    private var chips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                chip("All", isOn: category == nil) { category = nil }
                ForEach(categories) { kind in
                    chip(kind.label, isOn: category == kind) { category = kind }
                }
            }
            .padding(.horizontal, 16)
        }
    }

    private func chip(_ title: String, isOn: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .frame(minHeight: 44)
                .foregroundStyle(isOn ? Color.white : Color.primary)
                .background(
                    Capsule().fill(isOn ? Color.accentColor : Color(.secondarySystemFill))
                )
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }

    private func tile(_ template: OverlayCardTemplate) -> some View {
        Button {
            chosen = template.kind
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                TemplateThumbnailImage(config: template.sampleConfig)
                Text(template.displayName)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(template.displayName)
    }
}

// MARK: - TemplateThumbnailImage

/// A 16:9 preview of a card as it sits on output.
struct TemplateThumbnailImage: View {

    let config: OverlayCardConfig

    var body: some View {
        Group {
            if let image = OverlayCardThumbnail.image(for: config) {
                Image(uiImage: image).resizable()
            } else {
                Color(white: 0.08)
            }
        }
        .aspectRatio(16.0 / 9.0, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .accessibilityHidden(true)
    }
}
