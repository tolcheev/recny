import SwiftUI
import RecnyCore

struct TagEditorView: View {
    private static let saveStatuses: [TaggingStatus] = [
        .saved,
        .needsReview,
        .reviewed
    ]

    @Environment(\.dismiss) private var dismiss
    @State private var draft: PostCallDraft
    @State private var selectedStatus: TaggingStatus
    @State private var customTagsText = ""
    @State private var saveError: String?
    @FocusState private var focusedField: FocusedField?

    private let originalStatus: TaggingStatus
    let onSave: (PostCallDraft) throws -> Void

    private enum FocusedField: Hashable {
        case title
    }

    init(draft: PostCallDraft, onSave: @escaping (PostCallDraft) throws -> Void) {
        self._draft = State(initialValue: draft)
        self._selectedStatus = State(initialValue: Self.initialStatus(for: draft.status))
        self.originalStatus = draft.status
        self.onSave = onSave
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
            textFields
            quickTags
            customTags
            statusPicker

            if let saveError {
                Text(saveError)
                    .font(.callout)
                    .foregroundStyle(.red)
                    .textSelection(.enabled)
            }

            footer
            keyboardSaveButton
        }
        .padding(20)
        .frame(width: 520)
        .onAppear {
            focusedField = .title
        }
        .onExitCommand {
            dismiss()
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Rename recording")
                .font(.title3.weight(.semibold))
            Text("Name it clearly before sharing or reviewing.")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }

    private var textFields: some View {
        VStack(alignment: .leading, spacing: 10) {
            TextField("Title, optional", text: $draft.title)
                .textFieldStyle(.roundedBorder)
                .accessibilityLabel("Recording title")
                .focused($focusedField, equals: .title)
                .onSubmit(save)

            TextField("Participant, optional", text: $draft.participant)
                .textFieldStyle(.roundedBorder)
                .accessibilityLabel("Participant")
                .onSubmit(save)

            TextField("Context / note, optional", text: $draft.category)
                .textFieldStyle(.roundedBorder)
                .accessibilityLabel("Recording context or note")
                .onSubmit(save)
        }
    }

    private var quickTags: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Quick tags")
                .font(.callout.weight(.medium))

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 112), spacing: 8)], alignment: .leading, spacing: 8) {
                ForEach(MVPTags.quick, id: \.self) { tag in
                    Button {
                        draft.tags = TagEditorLogic.toggled(tag, in: draft.tags)
                    } label: {
                        Text(tag)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .tint(draft.tags.contains(tag) ? .accentColor : .secondary)
                    .accessibilityLabel(draft.tags.contains(tag) ? "Remove tag \(tag)" : "Add tag \(tag)")
                }
            }
        }
    }

    private var customTags: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Custom tags")
                .font(.callout.weight(.medium))

            HStack(spacing: 8) {
                TextField("custom, #tags", text: $customTagsText)
                    .textFieldStyle(.roundedBorder)
                    .accessibilityLabel("Custom tags")
                    .onSubmit(save)

                Button {
                    addCustomTags()
                } label: {
                    Label("Add", systemImage: "plus")
                }
                .disabled(TagEditorLogic.normalizedCustomTags(customTagsText).isEmpty)
            }

            if !draft.tags.isEmpty {
                TagChipFlow(tags: draft.tags) { tag in
                    draft.tags = TagEditorLogic.toggled(tag, in: draft.tags)
                }
            }
        }
    }

    private var statusPicker: some View {
        Group {
            if TagEditorLogic.isTechnicalStatusLocked(originalStatus) {
                HStack {
                    Text("Status")
                    Spacer()
                    Text(RecordingDisplayFormatter.statusText(originalStatus))
                        .foregroundStyle(.secondary)
                }
                .font(.callout)
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Recording status \(RecordingDisplayFormatter.statusText(originalStatus))")
            } else {
                Picker("Status", selection: $selectedStatus) {
                    ForEach(Self.saveStatuses, id: \.self) { status in
                        Text(RecordingDisplayFormatter.statusText(status)).tag(status)
                    }
                }
                .pickerStyle(.segmented)
                .accessibilityLabel("Recording status")
            }
        }
    }

    private var footer: some View {
        HStack {
            Spacer()

            Button("Cancel") {
                dismiss()
            }
            .keyboardShortcut(.cancelAction)

            Button("Save") {
                save()
            }
            .keyboardShortcut(.defaultAction)
        }
    }

    private var keyboardSaveButton: some View {
        Button("") {
            save()
        }
        .keyboardShortcut(.return, modifiers: .command)
        .frame(width: 0, height: 0)
        .opacity(0)
        .accessibilityHidden(true)
    }

    private static func initialStatus(for status: TaggingStatus) -> TaggingStatus {
        saveStatuses.contains(status) ? status : .saved
    }

    private func addCustomTags() {
        let customTags = TagEditorLogic.normalizedCustomTags(customTagsText)
        guard !customTags.isEmpty else {
            return
        }

        draft.tags = TagEditorLogic.normalizedTags(draft.tags + customTags)
        customTagsText = ""
    }

    private func save() {
        do {
            var savedDraft = draft
            savedDraft.tags = TagEditorLogic.normalizedTags(
                savedDraft.tags + TagEditorLogic.normalizedCustomTags(customTagsText)
            )
            savedDraft.status = TagEditorLogic.resolvedSaveStatus(
                originalStatus: originalStatus,
                selectedStatus: selectedStatus
            )
            try onSave(savedDraft)
            dismiss()
        } catch {
            saveError = String(describing: error)
        }
    }
}

private struct TagChipFlow: View {
    let tags: [String]
    let onRemove: (String) -> Void

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 94), spacing: 6)], alignment: .leading, spacing: 6) {
            ForEach(tags, id: \.self) { tag in
                Button {
                    onRemove(tag)
                } label: {
                    HStack(spacing: 4) {
                        Text(tag)
                            .lineLimit(1)
                        Image(systemName: "xmark")
                            .font(.caption2)
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .accessibilityLabel("Remove tag \(tag)")
            }
        }
    }
}
