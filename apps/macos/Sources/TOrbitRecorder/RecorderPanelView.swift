import SwiftUI
import TOrbitRecorderCore

struct RecorderPanelView: View {
    @ObservedObject var appState: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            header

            Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 10) {
                StatusRow(label: "Status", value: appState.status.rawValue)
                StatusRow(label: "Duration", value: appState.formattedDuration)
                StatusRow(label: "Mic", value: appState.micStatus.rawValue)
                StatusRow(label: "System Audio", value: appState.systemAudioStatus.rawValue)
                StatusRow(label: "Output Folder", value: appState.outputFolderPath)
            }

            if let errorMessage = appState.errorMessage {
                Text(errorMessage)
                    .font(.callout)
                    .foregroundStyle(.red)
                    .textSelection(.enabled)
            }

            HStack(spacing: 10) {
                Button("Start") {
                    Task {
                        try? await appState.startRecording()
                    }
                }
                .disabled(appState.status == .recording)

                Button("Stop") {
                    Task {
                        try? await appState.stopRecording()
                    }
                }
                .disabled(appState.status != .recording)

                Button("Open Folder") {
                    openOutputFolder()
                }
            }

            Divider()

            recordingsSection
        }
        .frame(minWidth: 560, minHeight: 520)
        .padding(24)
        .sheet(isPresented: $appState.isPostCallPanelPresented) {
            if let draft = appState.postCallDraft {
                PostCallTaggingView(draft: draft) { updatedDraft in
                    try appState.savePostCallDraft(updatedDraft)
                }
            }
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: appState.status == .recording ? "record.circle.fill" : "record.circle")
                .font(.title2)
                .foregroundStyle(appState.status == .recording ? .red : .secondary)

            Text("TOrbitRecorder")
                .font(.title2.weight(.semibold))
        }
    }

    private func openOutputFolder() {
        do {
            try FileManager.default.createDirectory(
                at: appState.outputFolderURL,
                withIntermediateDirectories: true
            )
            NSWorkspace.shared.open(appState.outputFolderURL)
        } catch {
            AppLogger.storage.error("Failed to open output folder from panel: \(String(describing: error), privacy: .public)")
        }
    }

    private var recordingsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Recordings")
                    .font(.headline)

                Spacer()

                Menu(appState.selectedTagFilter ?? "All Tags") {
                    Button("All Tags") {
                        appState.setTagFilter(nil)
                    }

                    Divider()

                    ForEach(MVPTags.all, id: \.self) { tag in
                        Button(tag) {
                            appState.setTagFilter(tag)
                        }
                    }
                }
            }

            if appState.recordings.isEmpty {
                Text("No recordings")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 8) {
                        ForEach(appState.recordings) { recording in
                            RecordingRow(recording: recording)
                        }
                    }
                }
                .frame(minHeight: 140)
            }
        }
    }
}

private struct StatusRow: View {
    let label: String
    let value: String

    var body: some View {
        GridRow {
            Text(label)
                .font(.callout.weight(.medium))
                .foregroundStyle(.secondary)
                .frame(width: 110, alignment: .leading)

            Text(value)
                .font(.callout.monospacedDigit())
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

private struct RecordingRow: View {
    let recording: RecordingSummary

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                Text(recording.title)
                    .font(.callout.weight(.semibold))
                    .lineLimit(1)

                Spacer()

                Text(recording.status.rawValue)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 6) {
                Text(recording.category)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if !recording.participant.isEmpty {
                    Text(recording.participant)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if !recording.tags.isEmpty {
                Text(recording.tags.joined(separator: " "))
                    .font(.caption)
                    .foregroundStyle(.blue)
                    .lineLimit(2)
            }
        }
        .padding(10)
        .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 8))
    }
}

private struct PostCallTaggingView: View {
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
            Text("Post-call tagging")
                .font(.title3.weight(.semibold))

            Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 12) {
                GridRow {
                    Text("Title")
                        .foregroundStyle(.secondary)
                    TextField("Recording title", text: $draft.title)
                        .textFieldStyle(.roundedBorder)
                }

                GridRow {
                    Text("Category")
                        .foregroundStyle(.secondary)
                    TextField("unsorted", text: $draft.category)
                        .textFieldStyle(.roundedBorder)
                }

                GridRow {
                    Text("Participant")
                        .foregroundStyle(.secondary)
                    TextField("Name or free text", text: $draft.participant)
                        .textFieldStyle(.roundedBorder)
                }

                GridRow {
                    Text("Status")
                        .foregroundStyle(.secondary)
                    Picker("Status", selection: $draft.status) {
                        ForEach(TaggingStatus.allCases, id: \.self) { status in
                            Text(status.rawValue).tag(status)
                        }
                    }
                    .labelsHidden()
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Tags")
                    .font(.callout.weight(.medium))

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 112), spacing: 8)], alignment: .leading, spacing: 8) {
                    ForEach(MVPTags.all, id: \.self) { tag in
                        Button(tag) {
                            toggleTag(tag)
                        }
                        .buttonStyle(.bordered)
                        .tint(draft.tags.contains(tag) ? .blue : .secondary)
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

                Button("Close") {
                    dismiss()
                }

                Button("Save") {
                    do {
                        try onSave(draft)
                        dismiss()
                    } catch {
                        saveError = String(describing: error)
                    }
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 520)
    }

    private func toggleTag(_ tag: String) {
        if let index = draft.tags.firstIndex(of: tag) {
            draft.tags.remove(at: index)
        } else {
            draft.tags.append(tag)
        }
    }
}
