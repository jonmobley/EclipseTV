//
//  TemplateEditorView.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//
//  Description: Field editor for a template card: a live preview, one text
//               field per template field, look, position, and (for
//               announcements) remove-after.
//  Thread Safety: Main thread only - SwiftUI view.
//

import SwiftUI

// MARK: - TemplateEditorView

/// Edits a `TemplateCardDraft`; Add / Save hands the draft back.
struct TemplateEditorView: View {

    // MARK: - Properties

    @State var draft: TemplateCardDraft
    /// True when adding (button reads "Add"), false when editing ("Save").
    let isNew: Bool
    let onCommit: (TemplateCardDraft) -> Void
    let onCancel: () -> Void

    // MARK: - Body

    var body: some View {
        Form {
            Section {
                TemplateThumbnailImage(config: draft.config)
                    .listRowInsets(EdgeInsets())
            }
            Section("Name") {
                TextField("Name", text: $draft.name)
                    .textInputAutocapitalization(.words)
            }
            Section("Text") {
                ForEach(draft.descriptor.fields) { field in
                    fieldRow(field)
                }
            }
            appearanceSection
            if draft.supportsAutoRemove {
                autoRemoveSection
            }
        }
        .navigationTitle(draft.descriptor.displayName)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button(isNew ? "Add" : "Save") { onCommit(draft) }
                    .disabled(!draft.canCommit)
            }
            if !isNew {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: onCancel)
                }
            }
        }
    }

    // MARK: - Sections

    private var appearanceSection: some View {
        Section("Appearance") {
            Picker("Look", selection: lookBinding) {
                ForEach(OverlayCardLook.allCases) { look in
                    Text(look.label).tag(Optional(look))
                }
                if draft.look == nil {
                    Text("Custom").tag(OverlayCardLook?.none)
                }
            }
            Picker("Position", selection: positionBinding) {
                ForEach(draft.positionChoices, id: \.self) { choice in
                    Text(choice.label).tag(choice)
                }
            }
        }
    }

    private var autoRemoveSection: some View {
        Section {
            Toggle("Remove Automatically", isOn: $draft.autoRemoveEnabled)
            if draft.autoRemoveEnabled {
                Stepper(
                    "After \(draft.autoRemoveSeconds) seconds",
                    value: $draft.autoRemoveSeconds,
                    in: TemplateCardDraft.autoRemoveRange
                )
            }
        } footer: {
            Text("Takes the announcement off the screen after the time you choose.")
        }
    }

    // MARK: - Rows

    private func fieldRow(_ field: OverlayCardField) -> some View {
        let binding = Binding(
            get: { draft.fields[field.key] ?? "" },
            set: { draft.fields[field.key] = $0 }
        )
        return LabeledContent(field.label) {
            TextField(field.placeholder, text: binding, axis: .vertical)
                .multilineTextAlignment(.trailing)
                .autocorrectionDisabled(field.isSecure)
                .textInputAutocapitalization(field.isSecure ? .never : .sentences)
        }
    }

    // MARK: - Bindings

    private var lookBinding: Binding<OverlayCardLook?> {
        Binding(
            get: { draft.look },
            set: { look in
                if let look { draft.applyLook(look) }
            }
        )
    }

    private var positionBinding: Binding<TemplateCardPosition> {
        Binding(
            get: { draft.position },
            set: { draft.setPosition($0) }
        )
    }
}
