import AppKit
import SwiftUI
import TOrbitRecorderCore

struct LibraryView: View {
    @ObservedObject var appState: AppState
    @State private var filtersExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Library")
                        .font(.title2.weight(.semibold))
                    Text("Recent recordings")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button {
                    try? appState.reloadRecordings()
                    try? appState.reloadLastRecording()
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
            }

            DisclosureGroup(isExpanded: $filtersExpanded) {
                filters
                    .padding(.top, 8)
            } label: {
                Text("Filters")
                    .font(.headline)
            }

            Divider()

            if displayedRecordings.isEmpty {
                Text("No recordings")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 8) {
                        ForEach(displayedRecordings) { recording in
                            LibraryRecordingRow(recording: recording, appState: appState)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
        }
        .padding(20)
        .frame(minWidth: 760, minHeight: 560)
        .onAppear {
            try? appState.reloadRecordings()
        }
    }

    private var filters: some View {
        VStack(alignment: .leading, spacing: 10) {
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
                            Text(statusLabel(status)).tag(status.rawValue)
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

                Spacer()

                Button {
                    appState.clearRecordingFilters()
                } label: {
                    Label("Clear Filters", systemImage: "line.3.horizontal.decrease.circle")
                }
            }
        }
    }

    private var displayedRecordings: [RecordingSummary] {
        if filtersAreActive {
            return appState.recordings
        }

        return Array(appState.recordings.prefix(50))
    }

    private var filtersAreActive: Bool {
        !appState.recordingFilters.dateText.isEmpty
            || appState.recordingFilters.status != nil
            || !appState.recordingFilters.sourceAppText.isEmpty
            || !appState.recordingFilters.titleText.isEmpty
            || !appState.recordingFilters.tags.isEmpty
    }
}

private struct LibraryRecordingRow: View {
    let recording: RecordingSummary
    let appState: AppState

    @State private var actionError: String?
    @State private var isDeleteConfirmationPresented = false
    @State private var isEditPresented = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(recording.title)
                        .font(.callout.weight(.semibold))
                        .lineLimit(1)

                    Text("\(displayDate(recording.startedAt)) · \(recording.sourceApp) · \(statusLabel(recording.status))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Text(formatDuration(recording.durationSec))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            if !recording.tags.isEmpty || !recording.participant.isEmpty {
                Text([recording.participant, recording.tags.joined(separator: " ")]
                    .filter { !$0.isEmpty }
                    .joined(separator: " · "))
                    .font(.caption)
                    .foregroundStyle(.blue)
                    .lineLimit(2)
            }

            HStack(spacing: 8) {
                Button {
                    NSWorkspace.shared.open(recording.sessionFolderURL)
                } label: {
                    Label("Open in Finder", systemImage: "folder")
                }

                Button {
                    playMixedAudio()
                } label: {
                    Label("Play", systemImage: "play.fill")
                }
                .disabled(!FileManager.default.fileExists(atPath: recording.mixedAudioURL.path(percentEncoded: false)))

                Button {
                    isEditPresented = true
                } label: {
                    Label("Edit", systemImage: "pencil")
                }

                Button(role: .destructive) {
                    isDeleteConfirmationPresented = true
                } label: {
                    Label("Delete", systemImage: "trash")
                }
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
        .sheet(isPresented: $isEditPresented) {
            RecordingEditSheet(recording: recording, appState: appState)
        }
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

private struct RecordingEditSheet: View {
    @Environment(\.dismiss) private var dismiss

    let recording: RecordingSummary
    let appState: AppState

    @State private var editedTitle: String
    @State private var editedTags: Set<String>
    @State private var actionError: String?

    init(recording: RecordingSummary, appState: AppState) {
        self.recording = recording
        self.appState = appState
        self._editedTitle = State(initialValue: recording.title)
        self._editedTags = State(initialValue: Set(recording.tags))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Edit recording")
                .font(.title3.weight(.semibold))

            TextField("Title", text: $editedTitle)
                .textFieldStyle(.roundedBorder)

            VStack(alignment: .leading, spacing: 8) {
                Text("Tags")
                    .font(.callout.weight(.medium))

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 112), spacing: 8)], alignment: .leading, spacing: 8) {
                    ForEach(MVPTags.all, id: \.self) { tag in
                        Button(tag) {
                            toggleTag(tag)
                        }
                        .buttonStyle(.bordered)
                        .tint(editedTags.contains(tag) ? .blue : .secondary)
                    }
                }
            }

            if let actionError {
                Text(actionError)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .textSelection(.enabled)
            }

            HStack {
                Spacer()

                Button("Cancel") {
                    dismiss()
                }

                Button("Save") {
                    save()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 520)
    }

    private func toggleTag(_ tag: String) {
        if editedTags.contains(tag) {
            editedTags.remove(tag)
        } else {
            editedTags.insert(tag)
        }
    }

    private func save() {
        do {
            try appState.updateRecording(
                recording,
                title: editedTitle,
                tags: editedTags.sorted()
            )
            actionError = nil
            dismiss()
        } catch {
            actionError = String(describing: error)
        }
    }
}

private func statusLabel(_ status: TaggingStatus) -> String {
    switch status {
    case .needsTagging:
        return "Needs tagging"
    case .saved:
        return "Saved"
    case .needsReview:
        return "Needs review"
    case .reviewed:
        return "Reviewed"
    case .failed:
        return "Failed"
    case .shortRecording:
        return "Short recording"
    }
}

private func displayDate(_ value: String) -> String {
    value
        .replacingOccurrences(of: "T", with: " ")
        .prefix(16)
        .description
}

private func formatDuration(_ duration: TimeInterval) -> String {
    let totalSeconds = max(0, Int(duration.rounded(.down)))
    let minutes = totalSeconds / 60
    let seconds = totalSeconds % 60
    if minutes >= 60 {
        let hours = minutes / 60
        let remainingMinutes = minutes % 60
        return String(format: "%d:%02d:%02d", hours, remainingMinutes, seconds)
    }
    return String(format: "%02d:%02d", minutes, seconds)
}
