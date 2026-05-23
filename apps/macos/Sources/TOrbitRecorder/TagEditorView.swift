import SwiftUI
import TOrbitRecorderCore

struct TagEditorView: View {
    private static let quickTags: [String] = [
        "#ученик",
        "#лид",
        "#мок",
        "#собес",
        "#разбор",
        "#продажа",
        "#конфликт",
        "#важное",
        "#разобрать",
        "#плохой_звук"
    ]

    @Environment(\.dismiss) private var dismiss
    @State private var draft: PostCallDraft
    @State private var saveError: String?

    let onSave: (PostCallDraft) throws -> Void

    init(draft: PostCallDraft, onSave: @escaping (PostCallDraft) throws -> Void) {
        self._draft = State(initialValue: draft)
        self.onSave = onSave
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Tag recording")
                    .font(.title3.weight(.semibold))
                Text("Add just enough context to find this call later.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 10) {
                TextField("Title, optional", text: $draft.title)
                    .textFieldStyle(.roundedBorder)
                    .accessibilityLabel("Recording title")

                TextField("Participant, optional", text: $draft.participant)
                    .textFieldStyle(.roundedBorder)
                    .accessibilityLabel("Participant")
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Quick tags")
                    .font(.callout.weight(.medium))

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 112), spacing: 8)], alignment: .leading, spacing: 8) {
                    ForEach(Self.quickTags, id: \.self) { tag in
                        Button(tag) {
                            toggleTag(tag)
                        }
                        .buttonStyle(.bordered)
                        .tint(draft.tags.contains(tag) ? .blue : .secondary)
                        .accessibilityLabel(draft.tags.contains(tag) ? "Remove tag \(tag)" : "Add tag \(tag)")
                    }
                }
            }

            if let saveError {
                Text(saveError)
                    .font(.callout)
                    .foregroundStyle(.red)
                    .textSelection(.enabled)
            }

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
        .padding(20)
        .frame(width: 480)
    }

    private func toggleTag(_ tag: String) {
        if let index = draft.tags.firstIndex(of: tag) {
            draft.tags.remove(at: index)
        } else {
            draft.tags.append(tag)
        }
    }

    private func save() {
        do {
            var savedDraft = draft
            if savedDraft.status == .needsTagging {
                savedDraft.status = .saved
            }
            try onSave(savedDraft)
            dismiss()
        } catch {
            saveError = String(describing: error)
        }
    }
}
