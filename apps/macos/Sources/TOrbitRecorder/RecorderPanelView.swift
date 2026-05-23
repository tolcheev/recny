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
                StatusRow(label: "Mixed Preview", value: appState.mixedPreviewPath ?? "Not created")
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

            recoverableSection

            recordingsListSection
        }
        .frame(minWidth: 720, minHeight: 680)
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

    private var recordingsListSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Recordings List")
                    .font(.headline)

                Spacer()

                Button {
                    try? appState.reloadRecordings()
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }

                Button {
                    appState.clearRecordingFilters()
                } label: {
                    Label("Clear Filters", systemImage: "line.3.horizontal.decrease.circle")
                }
            }

            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 8) {
                GridRow {
                    Text("Date")
                        .foregroundStyle(.secondary)
                    TextField(
                        "YYYY-MM-DD or YYYY-MM",
                        text: Binding(
                            get: { appState.recordingFilters.dateText },
                            set: { appState.setDateFilter($0) }
                        )
                    )
                    .textFieldStyle(.roundedBorder)

                    Text("Status")
                        .foregroundStyle(.secondary)
                    Picker(
                        "Status",
                        selection: Binding(
                            get: { appState.recordingFilters.status?.rawValue ?? "" },
                            set: { appState.setStatusFilter(TaggingStatus(rawValue: $0)) }
                        )
                    ) {
                        Text("Any").tag("")
                        ForEach(TaggingStatus.allCases, id: \.self) { status in
                            Text(status.rawValue).tag(status.rawValue)
                        }
                    }
                    .labelsHidden()
                }

                GridRow {
                    Text("Source")
                        .foregroundStyle(.secondary)
                    TextField(
                        "App name",
                        text: Binding(
                            get: { appState.recordingFilters.sourceAppText },
                            set: { appState.setSourceAppFilter($0) }
                        )
                    )
                    .textFieldStyle(.roundedBorder)

                    Text("Title")
                        .foregroundStyle(.secondary)
                    TextField(
                        "Title contains",
                        text: Binding(
                            get: { appState.recordingFilters.titleText },
                            set: { appState.setTitleFilter($0) }
                        )
                    )
                    .textFieldStyle(.roundedBorder)
                }
            }

            HStack(spacing: 8) {
                Text("Tags")
                    .foregroundStyle(.secondary)

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

                if let selectedTag = appState.selectedTagFilter {
                    Text(selectedTag)
                        .font(.caption)
                        .foregroundStyle(.blue)
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
                            RecordingRow(recording: recording, appState: appState)
                        }
                    }
                }
                .frame(minHeight: 220)
            }
        }
    }

    private var recoverableSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Recoverable")
                    .font(.headline)

                Spacer()

                Button("Refresh") {
                    try? appState.reloadRecoverableRecordings()
                }
            }

            if appState.recoverableRecordings.isEmpty {
                Text("No interrupted recordings")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                LazyVStack(alignment: .leading, spacing: 8) {
                    ForEach(appState.recoverableRecordings) { recording in
                        RecoverableRecordingRow(recording: recording, appState: appState)
                    }
                }
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
    let appState: AppState

    @State private var editedTitle: String
    @State private var editedTags: Set<String>
    @State private var actionError: String?
    @State private var isDeleteConfirmationPresented = false

    init(recording: RecordingSummary, appState: AppState) {
        self.recording = recording
        self.appState = appState
        self._editedTitle = State(initialValue: recording.title)
        self._editedTags = State(initialValue: Set(recording.tags))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                TextField("Title", text: $editedTitle)
                    .font(.callout.weight(.semibold))
                    .textFieldStyle(.roundedBorder)

                Spacer()

                Text(recording.status.rawValue)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 6) {
                Text(recording.sourceApp)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Text(recording.category)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if !recording.participant.isEmpty {
                    Text(recording.participant)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            HStack(spacing: 8) {
                Menu("Add Tags") {
                    ForEach(MVPTags.all, id: \.self) { tag in
                        Button(tag) {
                            toggleTag(tag)
                        }
                    }
                }

                Button {
                    saveEdits()
                } label: {
                    Label("Save", systemImage: "checkmark")
                }

                Button {
                    NSWorkspace.shared.activateFileViewerSelecting([recording.sessionFolderURL])
                } label: {
                    Label("Open in Finder", systemImage: "folder")
                }

                Button {
                    playMixedAudio()
                } label: {
                    Label("Play", systemImage: "play.fill")
                }
                .disabled(!FileManager.default.fileExists(atPath: recording.mixedAudioURL.path(percentEncoded: false)))

                Button(role: .destructive) {
                    isDeleteConfirmationPresented = true
                } label: {
                    Label("Delete", systemImage: "trash")
                }
            }

            if !editedTags.isEmpty {
                Text(editedTags.sorted().joined(separator: " "))
                    .font(.caption)
                    .foregroundStyle(.blue)
                    .lineLimit(2)
            }

            if let actionError {
                Text(actionError)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .textSelection(.enabled)
            }
        }
        .padding(10)
        .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 8))
        .confirmationDialog(
            "Delete local recording?",
            isPresented: $isDeleteConfirmationPresented,
            titleVisibility: .visible
        ) {
            Button("Delete Local Record", role: .destructive) {
                deleteRecording()
            }

            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This removes the recording folder and its SQLite index row.")
        }
    }

    private func toggleTag(_ tag: String) {
        if editedTags.contains(tag) {
            editedTags.remove(tag)
        } else {
            editedTags.insert(tag)
        }
    }

    private func saveEdits() {
        do {
            try appState.updateRecording(
                recording,
                title: editedTitle,
                tags: editedTags.sorted()
            )
            actionError = nil
        } catch {
            actionError = String(describing: error)
        }
    }

    private func playMixedAudio() {
        guard FileManager.default.fileExists(atPath: recording.mixedAudioURL.path(percentEncoded: false)) else {
            actionError = "mixed.m4a is missing"
            return
        }

        NSWorkspace.shared.open(recording.mixedAudioURL)
    }

    private func deleteRecording() {
        do {
            try appState.deleteLocalRecord(recording)
            actionError = nil
        } catch {
            actionError = String(describing: error)
        }
    }
}

private struct RecoverableRecordingRow: View {
    let recording: RecoverableRecordingSummary
    let appState: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(recording.id)
                    .font(.callout.weight(.semibold))
                    .lineLimit(1)

                Spacer()

                Text("failed / \(recording.status.rawValue)")
                    .font(.caption.monospaced())
                    .foregroundStyle(.orange)
            }

            HStack(spacing: 8) {
                Text("\(recording.segmentCount) segments")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Text(recording.startedAt)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            HStack(spacing: 8) {
                Button("Recover Recording") {
                    Task {
                        try? await appState.recoverRecording(recording)
                    }
                }

                Button("Open Folder") {
                    NSWorkspace.shared.open(recording.folderURL)
                }
            }
        }
        .padding(10)
        .background(.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
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
