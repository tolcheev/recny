import AppKit
import SwiftUI
import TOrbitRecorderCore

struct LibraryView: View {
    @ObservedObject var appState: AppState
    @State private var filtersExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
            search
            filtersDisclosure
            recordingsList
        }
        .padding(20)
        .frame(minWidth: 800, minHeight: 600)
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear {
            try? appState.reloadRecordings()
        }
    }

    private var header: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Library")
                    .font(.title2.weight(.semibold))
                Text(filtersAreActive ? "Filtered recordings" : "Recent recordings")
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
            .accessibilityLabel("Refresh recordings")
        }
    }

    private var search: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)

            TextField(
                "Search recordings",
                text: Binding(
                    get: { appState.recordingFilters.titleText },
                    set: { appState.setTitleFilter($0) }
                )
            )
            .textFieldStyle(.plain)
            .accessibilityLabel("Search recordings")

            if !appState.recordingFilters.titleText.isEmpty {
                Button {
                    appState.setTitleFilter("")
                } label: {
                    Image(systemName: "xmark.circle.fill")
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .accessibilityLabel("Clear search")
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color(nsColor: .separatorColor).opacity(0.3), lineWidth: 1)
        )
    }

    private var filtersDisclosure: some View {
        DisclosureGroup(isExpanded: $filtersExpanded) {
            filters
                .padding(.top, 10)
        } label: {
            HStack(spacing: 8) {
                Text("Filters")
                    .font(.headline)
                if filtersAreActive {
                    StatusBadge(text: "Active", tone: .warning)
                }
            }
        }
    }

    private var filters: some View {
        VStack(alignment: .leading, spacing: 10) {
            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 10) {
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
                            Text(RecordingDisplayFormatter.statusText(status)).tag(status.rawValue)
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
                }
            }

            HStack {
                Spacer()

                Button {
                    appState.clearRecordingFilters()
                } label: {
                    Label("Clear Filters", systemImage: "line.3.horizontal.decrease.circle")
                }
                .disabled(!filtersAreActive)
            }
        }
    }

    private var recordingsList: some View {
        Group {
            if displayedRecordings.isEmpty {
                emptyState
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 10) {
                        ForEach(displayedRecordings) { recording in
                            LibraryRecordingRow(recording: recording, appState: appState)
                        }
                    }
                    .padding(.vertical, 2)
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "tray")
                .font(.system(size: 34))
                .foregroundStyle(.secondary)
            Text(filtersAreActive ? "No recordings match these filters" : "No recordings yet")
                .font(.headline)
            Text(filtersAreActive ? "Clear filters or adjust search." : "Start a recording from the main window.")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .combine)
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
    @State private var tagDraft: PostCallDraft?
    @State private var isDeleteConfirmationPresented = false

    var body: some View {
        RecorderCard {
            HStack(alignment: .top, spacing: 14) {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Text(recording.title)
                            .font(.callout.weight(.semibold))
                            .lineLimit(1)

                        StatusBadge(
                            text: RecordingDisplayFormatter.statusText(recording.status),
                            tone: tone(for: recording.status)
                        )
                    }

                    Text("\(displayDate(recording.startedAt)) · \(RecordingDisplayFormatter.duration(recording.durationSec)) · \(recording.sourceApp)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)

                    if !recording.tags.isEmpty || !recording.participant.isEmpty {
                        Text([recording.participant, recording.tags.joined(separator: " ")]
                            .filter { !$0.isEmpty }
                            .joined(separator: " · "))
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

                Spacer()

                HStack(spacing: 8) {
                    Button {
                        playMixedAudio()
                    } label: {
                        Label("Play", systemImage: "play.fill")
                    }
                    .disabled(!FileManager.default.fileExists(atPath: recording.mixedAudioURL.path(percentEncoded: false)))
                    .accessibilityLabel("Play recording")

                    Button {
                        NSWorkspace.shared.open(recording.sessionFolderURL)
                    } label: {
                        Label("Open", systemImage: "folder")
                    }
                    .accessibilityLabel("Open recording folder")

                    Menu {
                        Button {
                            openTagEditor()
                        } label: {
                            Label("Tag", systemImage: "tag")
                        }

                        Divider()

                        Button(role: .destructive) {
                            isDeleteConfirmationPresented = true
                        } label: {
                            Label("Delete Local Record", systemImage: "trash")
                        }
                    } label: {
                        Label("More", systemImage: "ellipsis.circle")
                    }
                    .accessibilityLabel("More actions")
                }
            }
        }
        .sheet(item: $tagDraft) { draft in
            TagEditorView(draft: draft) { updatedDraft in
                try appState.savePostCallDraft(updatedDraft)
                tagDraft = nil
            }
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

    private func openTagEditor() {
        do {
            tagDraft = try appState.draft(for: recording)
            actionError = nil
        } catch {
            actionError = String(describing: error)
        }
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

private func displayDate(_ value: String) -> String {
    value
        .replacingOccurrences(of: "T", with: " ")
        .prefix(16)
        .description
}
