import AppKit
import SwiftUI
import TOrbitRecorderCore

struct LibraryView: View {
    @ObservedObject var appState: AppState

    @State private var searchText = ""
    @State private var filtersExpanded = false
    @State private var dateFromText = ""
    @State private var dateToText = ""
    @State private var selectedAudioHealthFilter: AudioHealthStatus?
    @State private var selectedRecordingID: String?
    @State private var tagDraft: PostCallDraft?
    @State private var deleteCandidate: RecordingSummary?
    @State private var reprocessCandidate: RecordingSummary?
    @State private var reprocessingRecordingIDs: Set<String> = []
    @State private var actionError: String?
    @State private var actionMessage: String?
    @State private var inlinePlayback: RecordingInlinePlaybackRequest?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            if let actionError {
                Label(actionError, systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.red)
                    .textSelection(.enabled)
            }
            if let actionMessage {
                Label(actionMessage, systemImage: "checkmark.circle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }

            HStack(alignment: .top, spacing: 14) {
                VStack(alignment: .leading, spacing: 12) {
                    searchBar
                    filtersDisclosure
                    recordingsList
                }
                .frame(minWidth: 520, idealWidth: 620, maxWidth: .infinity)

                detailsPanel
                    .frame(width: 340)
            }
        }
        .padding(20)
        .frame(minWidth: 980, minHeight: 660)
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear {
            reloadLibrary()
        }
        .onChange(of: searchText) { _, _ in
            ensureSelectionVisible()
        }
        .onChange(of: dateFromText) { _, _ in
            ensureSelectionVisible()
        }
        .onChange(of: dateToText) { _, _ in
            ensureSelectionVisible()
        }
        .onChange(of: selectedAudioHealthFilter) { _, _ in
            ensureSelectionVisible()
        }
        .onChange(of: appState.recordings) { _, _ in
            ensureSelectionVisible()
            ensureInlinePlaybackVisible()
        }
        .sheet(item: $tagDraft) { draft in
            TagEditorView(draft: draft) { updatedDraft in
                try appState.savePostCallDraft(updatedDraft)
                tagDraft = nil
                try? appState.reloadRecordings()
                ensureSelectionVisible()
            }
        }
        .confirmationDialog(
            "Delete local recording?",
            isPresented: Binding(
                get: { deleteCandidate != nil },
                set: { if !$0 { deleteCandidate = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Delete Local Recording", role: .destructive) {
                deleteSelectedCandidate()
            }

            Button("Cancel", role: .cancel) {
                deleteCandidate = nil
            }
        } message: {
            Text("This removes audio files and metadata.")
        }
        .confirmationDialog(
            "Balanced audio already exists",
            isPresented: Binding(
                get: { reprocessCandidate != nil },
                set: { if !$0 { reprocessCandidate = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Overwrite Balanced Audio") {
                if let reprocessCandidate {
                    runReprocess(for: reprocessCandidate, overwriteExisting: true)
                }
                reprocessCandidate = nil
            }

            Button("Skip") {
                actionMessage = "Reprocess skipped. Existing balanced audio was kept."
                actionError = nil
                reprocessCandidate = nil
            }

            Button("Cancel", role: .cancel) {
                reprocessCandidate = nil
            }
        } message: {
            Text("Reprocessing replaces only export/mixed_balanced.m4a and analysis/audio_analysis.json. Raw source files stay unchanged.")
        }
    }

    private var header: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Records")
                    .font(.title2.weight(.semibold))
                Text(librarySubtitle)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            HStack(spacing: 8) {
                Button {
                    openLibraryFolder()
                } label: {
                    Label("Open Library Folder", systemImage: "folder")
                }
                .accessibilityLabel("Open local recordings library folder")

                Button {
                    reloadLibrary()
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
                .accessibilityLabel("Refresh recordings")
            }
        }
    }

    private var searchBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)

            TextField("Search title, participant, tags, or app", text: $searchText)
                .textFieldStyle(.plain)
                .accessibilityLabel("Search recordings")

            if !searchText.isEmpty {
                Button {
                    searchText = ""
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
                .stroke(Color(nsColor: .separatorColor).opacity(0.28), lineWidth: 1)
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
                }

                GridRow {
                    Text("From")
                        .foregroundStyle(.secondary)
                    TextField("YYYY-MM-DD", text: $dateFromText)
                        .textFieldStyle(.roundedBorder)

                    Text("To")
                        .foregroundStyle(.secondary)
                    TextField("YYYY-MM-DD", text: $dateToText)
                        .textFieldStyle(.roundedBorder)
                }

                GridRow {
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

                    Text("Audio")
                        .foregroundStyle(.secondary)
                    Picker(
                        "Audio health",
                        selection: Binding(
                            get: { selectedAudioHealthFilter?.rawValue ?? "" },
                            set: { selectedAudioHealthFilter = AudioHealthStatus(rawValue: $0) }
                        )
                    ) {
                        Text("Any").tag("")
                        Text(RecordingDisplayFormatter.audioHealthBadgeText(.good)).tag(AudioHealthStatus.good.rawValue)
                        Text(RecordingDisplayFormatter.audioHealthBadgeText(.warning)).tag(AudioHealthStatus.warning.rawValue)
                        Text(RecordingDisplayFormatter.audioHealthBadgeText(.failed)).tag(AudioHealthStatus.failed.rawValue)
                    }
                    .labelsHidden()
                }
            }

            HStack {
                Spacer()

                Button {
                    clearFilters()
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
                    LazyVStack(alignment: .leading, spacing: 8) {
                        ForEach(displayedRecordings) { recording in
                            let metadata = metadata(for: recording)
                            LibraryRecordingRow(
                                recording: recording,
                                audioSummary: audioSummary(for: recording, metadata: metadata),
                                playbackState: playbackState(for: recording, metadata: metadata),
                                audioHealth: metadata?.audio.health ?? .good,
                                inlinePlayback: inlinePlayback?.recordingID == recording.id ? inlinePlayback : nil,
                                isSelected: recording.id == selectedRecordingID,
                                onSelect: {
                                    selectedRecordingID = recording.id
                                },
                                onPlay: {
                                    playMixedAudio(for: recording)
                                },
                                onOpen: {
                                    NSWorkspace.shared.open(recording.sessionFolderURL)
                                },
                                onPlayBalanced: {
                                    playIfExists(
                                        recording.balancedMixedAudioURL,
                                        kind: .balanced,
                                        recording: recording
                                    )
                                },
                                onPlayOriginal: {
                                    playIfExists(
                                        recording.originalMixedAudioURL,
                                        kind: .original,
                                        recording: recording
                                    )
                                },
                                onClosePlayback: {
                                    inlinePlayback = nil
                                },
                                onShowAnalysis: {
                                    revealIfExists(recording.audioAnalysisURL)
                                },
                                onReprocess: {
                                    requestReprocess(for: recording)
                                },
                                isReprocessing: reprocessingRecordingIDs.contains(recording.id),
                                onEdit: {
                                    openTagEditor(for: recording)
                                },
                                onDelete: {
                                    deleteCandidate = recording
                                }
                            )
                        }
                    }
                    .padding(.vertical, 2)
                }
            }
        }
    }

    private var detailsPanel: some View {
        Group {
            if let selectedRecording {
                LibraryRecordingDetailsPanel(
                    recording: selectedRecording,
                    metadata: metadata(for: selectedRecording),
                    onPlay: {
                        playMixedAudio(for: selectedRecording)
                    },
                    onOpen: {
                        NSWorkspace.shared.open(selectedRecording.sessionFolderURL)
                    },
                    onEdit: {
                        openTagEditor(for: selectedRecording)
                    },
                    onShowAnalysis: {
                        revealIfExists(selectedRecording.audioAnalysisURL)
                    },
                    onDelete: {
                        deleteCandidate = selectedRecording
                    }
                )
            } else {
                RecorderCard {
                    VStack(spacing: 10) {
                        Image(systemName: "sidebar.right")
                            .font(.system(size: 28))
                            .foregroundStyle(.secondary)
                        Text("Select a recording")
                            .font(.headline)
                        Text("Details and file actions appear here.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(.vertical, 40)
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: filtersAreActive ? "line.3.horizontal.decrease.circle" : "waveform.badge.plus")
                .font(.system(size: 34))
                .foregroundStyle(.secondary)
            Text(filtersAreActive ? "No recordings match filters." : "Recorded calls will appear here.")
                .font(.headline)
            Text(filtersAreActive ? "Clear filters or adjust search." : "Start from the main recorder or auto-start.")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .combine)
    }

    private var selectedRecording: RecordingSummary? {
        guard let selectedRecordingID else {
            return displayedRecordings.first
        }

        return displayedRecordings.first { $0.id == selectedRecordingID }
    }

    private var displayedRecordings: [RecordingSummary] {
        let filtered = appState.recordings.filter { recording in
            let metadata = metadata(for: recording)
            return LibraryRecordingFilter.matches(
                recording,
                query: searchText,
                dateFromText: dateFromText,
                dateToText: dateToText
            )
            && LibraryRecordingFilter.matchesAudioHealth(
                metadata?.audio.health.status ?? .good,
                selectedStatus: selectedAudioHealthFilter
            )
        }

        return filtersAreActive ? filtered : Array(filtered.prefix(80))
    }

    private var filtersAreActive: Bool {
        !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || appState.recordingFilters.status != nil
            || !appState.recordingFilters.sourceAppText.isEmpty
            || !appState.recordingFilters.tags.isEmpty
            || selectedAudioHealthFilter != nil
            || !dateFromText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || !dateToText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var librarySubtitle: String {
        if displayedRecordings.isEmpty {
            return filtersAreActive ? "No matching local recordings" : "Recent local recordings"
        }

        return "\(displayedRecordings.count) recent local recording\(displayedRecordings.count == 1 ? "" : "s")"
    }

    private func clearFilters() {
        searchText = ""
        dateFromText = ""
        dateToText = ""
        selectedAudioHealthFilter = nil
        appState.clearRecordingFilters()
        ensureSelectionVisible()
    }

    private func reloadLibrary() {
        try? appState.reloadRecordings()
        try? appState.reloadLastRecording()
        ensureSelectionVisible()
    }

    private func ensureSelectionVisible() {
        guard let selectedRecordingID,
              displayedRecordings.contains(where: { $0.id == selectedRecordingID })
        else {
            self.selectedRecordingID = displayedRecordings.first?.id
            return
        }
    }

    private func ensureInlinePlaybackVisible() {
        guard let inlinePlayback,
              displayedRecordings.contains(where: { $0.id == inlinePlayback.recordingID })
        else {
            self.inlinePlayback = nil
            return
        }
    }

    private func metadata(for recording: RecordingSummary) -> RecordingMetadata? {
        try? FileSystemRecordingStore(rootURL: appState.outputFolderURL)
            .readMetadata(at: recording.metadataURL)
    }

    private func audioSummary(
        for recording: RecordingSummary,
        metadata: RecordingMetadata?
    ) -> String {
        let micTrack = metadata?.audioTracks.first { $0.kind == "microphone" }
        let systemTrack = metadata?.audioTracks.first { $0.kind == "system" }

        return RecordingDisplayFormatter.audioSummary(
            micFileSizeBytes: fileSize(from: micTrack, fallbackURL: recording.sessionFolderURL.appendingPathComponent("source/mic.m4a")),
            systemFileSizeBytes: fileSize(from: systemTrack, fallbackURL: recording.sessionFolderURL.appendingPathComponent("source/system.m4a"))
        )
    }

    private func fileSize(from track: AudioTrackMetadata?, fallbackURL: URL) -> Int64? {
        if let size = track?.fileSizeBytes {
            return size
        }

        guard let size = try? FileManager.default
            .attributesOfItem(atPath: fallbackURL.path(percentEncoded: false))[.size] as? NSNumber
        else {
            return nil
        }

        return size.int64Value
    }

    private func openTagEditor(for recording: RecordingSummary) {
        do {
            tagDraft = try appState.draft(for: recording)
            actionError = nil
        } catch {
            actionError = String(describing: error)
        }
    }

    private func playMixedAudio(for recording: RecordingSummary) {
        guard let playback = RecordingPlaybackResolver.preferredPlayback(
            sessionFolderURL: recording.sessionFolderURL
        ) else {
            actionError = "No playable audio file found"
            return
        }

        startInlinePlayback(for: recording, candidate: playback)
    }

    private func playbackState(
        for recording: RecordingSummary,
        metadata: RecordingMetadata?
    ) -> RecordingPlaybackDisplayState {
        RecordingPlaybackResolver.displayState(
            sessionFolderURL: recording.sessionFolderURL,
            processingStatus: metadata?.audio.processing.balancedMixStatus ?? .skipped
        )
    }

    private func playIfExists(
        _ url: URL,
        kind: RecordingPlaybackKind,
        recording: RecordingSummary
    ) {
        guard let size = RecordingPlaybackResolver.nonEmptyFileSize(at: url) else {
            actionError = "\(url.lastPathComponent) is missing"
            actionMessage = nil
            return
        }

        startInlinePlayback(
            for: recording,
            candidate: RecordingPlaybackCandidate(kind: kind, url: url, fileSizeBytes: size)
        )
    }

    private func startInlinePlayback(
        for recording: RecordingSummary,
        candidate: RecordingPlaybackCandidate
    ) {
        AppWindows.closeAudioPlayer()
        selectedRecordingID = recording.id
        inlinePlayback = RecordingInlinePlaybackRequest(
            recordingID: recording.id,
            recordingTitle: recording.title,
            candidate: candidate
        )
        actionError = nil
        actionMessage = nil
        AppLogger.file(.info, category: "playback", "open inline library player recording=\(recording.id) path=\(candidate.url.path(percentEncoded: false))")
    }

    private func revealIfExists(_ url: URL) {
        guard RecordingPlaybackResolver.nonEmptyFileSize(at: url) != nil else {
            actionError = "\(url.lastPathComponent) is missing"
            actionMessage = nil
            return
        }

        NSWorkspace.shared.activateFileViewerSelecting([url])
        actionError = nil
    }

    private func deleteSelectedCandidate() {
        guard let recording = deleteCandidate else {
            return
        }

        do {
            try appState.deleteLocalRecord(recording)
            deleteCandidate = nil
            selectedRecordingID = displayedRecordings.first?.id
            actionError = nil
            actionMessage = "Recording deleted."
        } catch {
            actionError = String(describing: error)
            actionMessage = nil
        }
    }

    private func requestReprocess(for recording: RecordingSummary) {
        actionError = nil
        actionMessage = nil
        guard RecordingPlaybackResolver.nonEmptyFileSize(at: recording.balancedMixedAudioURL) == nil else {
            reprocessCandidate = recording
            return
        }

        runReprocess(for: recording, overwriteExisting: false)
    }

    private func runReprocess(for recording: RecordingSummary, overwriteExisting: Bool) {
        guard !reprocessingRecordingIDs.contains(recording.id) else {
            return
        }

        reprocessingRecordingIDs.insert(recording.id)
        actionError = nil
        actionMessage = "Reprocessing audio..."

        Task {
            do {
                let result = try await appState.reprocessAudio(
                    for: recording,
                    overwriteExisting: overwriteExisting
                )
                if result.status == .failed {
                    actionError = "\(result.title): \(result.message)"
                    actionMessage = nil
                } else {
                    actionMessage = "\(result.title): \(result.message)"
                    actionError = nil
                }
                reloadLibrary()
            } catch {
                actionError = String(describing: error)
                actionMessage = nil
            }
            reprocessingRecordingIDs.remove(recording.id)
        }
    }

    private func openLibraryFolder() {
        do {
            try FileManager.default.createDirectory(
                at: appState.outputFolderURL,
                withIntermediateDirectories: true
            )
            NSWorkspace.shared.open(appState.outputFolderURL)
        } catch {
            actionError = String(describing: error)
            actionMessage = nil
            AppLogger.storage.error("Failed to open library folder: \(String(describing: error), privacy: .public)")
        }
    }
}

private struct LibraryRecordingRow: View {
    let recording: RecordingSummary
    let audioSummary: String
    let playbackState: RecordingPlaybackDisplayState
    let audioHealth: AudioHealthMetadata
    let inlinePlayback: RecordingInlinePlaybackRequest?
    let isSelected: Bool
    let onSelect: () -> Void
    let onPlay: () -> Void
    let onOpen: () -> Void
    let onPlayBalanced: () -> Void
    let onPlayOriginal: () -> Void
    let onClosePlayback: () -> Void
    let onShowAnalysis: () -> Void
    let onReprocess: () -> Void
    let isReprocessing: Bool
    let onEdit: () -> Void
    let onDelete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 7) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(recording.title)
                            .font(.callout.weight(.semibold))
                            .lineLimit(1)

                        StatusBadge(
                            text: RecordingDisplayFormatter.statusText(recording.status),
                            tone: tone(for: recording.status)
                        )

                        StatusBadge(
                            text: playbackBadgeText,
                            tone: playbackBadgeTone
                        )

                        if audioHealth.status != .good {
                            StatusBadge(
                                text: RecordingDisplayFormatter.audioHealthBadgeText(audioHealth.status),
                                tone: audioHealth.status == .failed ? .danger : .warning
                            )
                        }
                    }

                    Text("\(displayDate(recording.startedAt)) · \(RecordingDisplayFormatter.duration(recording.durationSec)) · \(recording.sourceApp) · \(audioSummary)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)

                    CompactTagsView(participant: recording.participant, tags: recording.tags)
                }

                Spacer(minLength: 10)

                HStack(spacing: 6) {
                    if inlinePlayback == nil {
                        Button(action: onPlay) {
                            Label("Play", systemImage: "play.fill")
                        }
                        .disabled(playbackState == .missing)
                        .accessibilityLabel("Play recording")
                    } else {
                        Button(action: onClosePlayback) {
                            Label("Close Player", systemImage: "xmark")
                        }
                        .accessibilityLabel("Close inline player")
                    }

                    Button(action: onOpen) {
                        Label("Open", systemImage: "folder")
                    }
                    .accessibilityLabel("Open recording folder")

                    Menu {
                        Button(action: onPlayBalanced) {
                            Label("Play Balanced", systemImage: "slider.horizontal.3")
                        }
                        .disabled(RecordingPlaybackResolver.nonEmptyFileSize(at: recording.balancedMixedAudioURL) == nil)

                        Button(action: onPlayOriginal) {
                            Label("Play Original", systemImage: "waveform")
                        }
                        .disabled(RecordingPlaybackResolver.nonEmptyFileSize(at: recording.originalMixedAudioURL) == nil)

                        Button(action: onOpen) {
                            Label("Open Folder", systemImage: "folder")
                        }

                        Button(action: onShowAnalysis) {
                            Label("Reveal Audio Analysis", systemImage: "doc.text.magnifyingglass")
                        }
                        .disabled(RecordingPlaybackResolver.nonEmptyFileSize(at: recording.audioAnalysisURL) == nil)

                        Button(action: onReprocess) {
                            Label("Reprocess Audio", systemImage: "arrow.triangle.2.circlepath")
                        }
                        .disabled(isReprocessing)

                        Divider()

                        Button(action: onEdit) {
                            Label("Edit Note / Tags", systemImage: "tag")
                        }

                        Divider()

                        Button(role: .destructive, action: onDelete) {
                            Label("Delete Local Recording", systemImage: "trash")
                        }
                    } label: {
                        Label("More", systemImage: "ellipsis.circle")
                            .labelStyle(.iconOnly)
                    }
                    .menuStyle(.borderlessButton)
                    .fixedSize()
                    .accessibilityLabel("More actions")
                }
                .fixedSize()
            }

            if let inlinePlayback {
                InlineAudioPlayerView(
                    url: inlinePlayback.url,
                    title: inlinePlayback.title,
                    autoplays: true
                )
                .id(inlinePlayback.id)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 11)
        .background(rowBackground, in: RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(isSelected ? Color.accentColor.opacity(0.6) : Color(nsColor: .separatorColor).opacity(0.18), lineWidth: 1)
        )
        .contentShape(RoundedRectangle(cornerRadius: 8))
        .onTapGesture(perform: onSelect)
        .accessibilityElement(children: .contain)
    }

    private var rowBackground: Color {
        isSelected
            ? Color.accentColor.opacity(0.12)
            : Color(nsColor: .controlBackgroundColor).opacity(0.55)
    }

    private var playbackBadgeText: String {
        switch playbackState {
        case .balancedReady:
            return "Balanced"
        case .balancedFailed:
            return "Audio warning"
        case .originalOnly, .levelingSkipped:
            return "Original"
        case .fallbackSource(let kind):
            return kind.displayName
        case .missing:
            return "Audio missing"
        }
    }

    private var playbackBadgeTone: StatusTone {
        switch playbackState {
        case .balancedReady:
            return .ready
        case .balancedFailed, .fallbackSource:
            return .warning
        case .missing:
            return .danger
        default:
            return .neutral
        }
    }
}

private struct LibraryRecordingDetailsPanel: View {
    let recording: RecordingSummary
    let metadata: RecordingMetadata?
    let onPlay: () -> Void
    let onOpen: () -> Void
    let onEdit: () -> Void
    let onShowAnalysis: () -> Void
    let onDelete: () -> Void

    var body: some View {
        RecorderCard {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 6) {
                    StatusBadge(
                        text: RecordingDisplayFormatter.statusText(recording.status),
                        tone: tone(for: recording.status)
                    )

                    Text(recording.title)
                        .font(.headline)
                        .lineLimit(2)

                    Text(displayDate(recording.startedAt))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if recording.category != "unsorted" {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Note")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                        Text(recording.category)
                            .font(.caption)
                            .textSelection(.enabled)
                    }
                }

                detailsGrid

                if !recording.tags.isEmpty || !recording.participant.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Tags")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                        CompactTagsView(participant: recording.participant, tags: recording.tags)
                    }
                }

                markersSection
                filesSection
                audioProcessingSection
                metadataSection

                Spacer(minLength: 0)

                HStack(spacing: 8) {
                    Button(action: onPlay) {
                        Label("Play", systemImage: "play.fill")
                    }
                    .disabled(playbackState == .missing)

                    Button(action: onOpen) {
                        Label("Open", systemImage: "folder")
                    }

                    Button(action: onEdit) {
                        Label("Edit / Tag", systemImage: "tag")
                    }
                }

                Button(action: onShowAnalysis) {
                    Label("Reveal Audio Analysis", systemImage: "doc.text.magnifyingglass")
                }
                .disabled(RecordingPlaybackResolver.nonEmptyFileSize(at: recording.audioAnalysisURL) == nil)

                Button(role: .destructive, action: onDelete) {
                    Label("Delete", systemImage: "trash")
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }

    @ViewBuilder
    private var markersSection: some View {
        let markers = (metadata?.markers ?? []).sorted {
            if $0.timeSec == $1.timeSec {
                return $0.createdAt < $1.createdAt
            }

            return $0.timeSec < $1.timeSec
        }

        if !markers.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("Markers")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)

                ForEach(markers) { marker in
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(RecordingDisplayFormatter.markerTimestamp(marker.timeSec))
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                            .frame(width: 48, alignment: .leading)

                        Text(marker.label)
                            .font(.caption)
                            .lineLimit(1)
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("Marker \(marker.label) at \(RecordingDisplayFormatter.markerTimestamp(marker.timeSec))")
                }
            }
        }
    }

    private var detailsGrid: some View {
        VStack(alignment: .leading, spacing: 8) {
            detailRow("Duration", RecordingDisplayFormatter.duration(recording.durationSec))
            detailRow("Source", recording.sourceApp)
            detailRow("Started", displayDate(recording.startedAt))
            if let source = metadata?.source {
                detailRow("Trigger", source.trigger)
            }
        }
    }

    private var filesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Files")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            ForEach(fileRows, id: \.label) { row in
                detailRow(row.label, row.value)
            }
        }
    }

    private var metadataSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Metadata")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            detailRow("ID", recording.id)
            if let reason = metadata?.source.reason {
                detailRow("Reason", reason)
            }
        }
    }

    private var audioProcessingSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Audio")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            detailRow("Playback", RecordingDisplayFormatter.audioProcessingCopy(state: playbackState))
            detailRow("Health", RecordingDisplayFormatter.audioHealthBadgeText(metadata?.audio.health.status ?? .good))
            detailRow("Analysis", analysisSummary)
            detailRow("Mic gain", gainText(metadata?.audio.processing.microphoneGainDB))
            detailRow("System gain", gainText(metadata?.audio.processing.systemGainDB))

            let details = audioHealthDetails
            if !details.isEmpty {
                detailRow("Details", details.joined(separator: " "))
            }
        }
    }

    private var fileRows: [FileRow] {
        [
            FileRow(label: "Mic", value: fileDescription(kind: "microphone", fallback: "source/mic.m4a")),
            FileRow(label: "System", value: fileDescription(kind: "system", fallback: "source/system.m4a")),
            FileRow(label: "Original mixed", value: fileDescription(kind: "mixed", fallback: "export/mixed.m4a")),
            FileRow(label: "Balanced mixed", value: fileDescription(kind: "mixed_balanced", fallback: "export/mixed_balanced.m4a"))
        ]
    }

    private var playbackState: RecordingPlaybackDisplayState {
        RecordingPlaybackResolver.displayState(
            sessionFolderURL: recording.sessionFolderURL,
            processingStatus: metadata?.audio.processing.balancedMixStatus ?? .skipped
        )
    }

    private var audioWarnings: [String] {
        let qualityWarnings = metadata?.qualityWarnings ?? []
        let processingWarnings = metadata?.audio.processing.warnings ?? []
        var seen = Set<String>()
        return (qualityWarnings + processingWarnings).filter { seen.insert($0).inserted }
    }

    private var analysisSummary: String {
        RecordingPlaybackResolver.nonEmptyFileSize(at: recording.audioAnalysisURL) == nil
            ? "Missing"
            : "Available"
    }

    private var audioHealthDetails: [String] {
        guard let metadata else {
            return []
        }

        let healthDetails = RecordingDisplayFormatter.audioHealthDetails(
            health: metadata.audio.health,
            processingStatus: metadata.audio.processing.balancedMixStatus
        )
        let legacyWarnings = audioWarnings.filter { warning in
            !healthDetails.contains(warning)
        }
        return healthDetails + legacyWarnings
    }

    private func gainText(_ value: Double?) -> String {
        guard let value else {
            return "Not applied"
        }

        if value == 0 {
            return "0 dB"
        }

        return String(format: "%+.1f dB", value)
    }

    private func fileDescription(kind: String, fallback: String) -> String {
        let track = metadata?.audioTracks.first { $0.kind == kind }
        return RecordingDisplayFormatter.fileSize(track?.fileSizeBytes ?? fallbackFileSize(fallback))
    }

    private func fallbackFileSize(_ relativePath: String) -> Int64? {
        let url = recording.sessionFolderURL.appendingPathComponent(relativePath)
        guard let size = try? FileManager.default
            .attributesOfItem(atPath: url.path(percentEncoded: false))[.size] as? NSNumber
        else {
            return nil
        }
        return size.int64Value
    }

    private func detailRow(_ label: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(label)
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
                .frame(width: 64, alignment: .leading)

            Text(value)
                .font(.caption)
                .lineLimit(3)
                .textSelection(.enabled)
        }
    }
}

private struct CompactTagsView: View {
    let participant: String
    let tags: [String]

    var body: some View {
        HStack(spacing: 6) {
            if !participant.isEmpty {
                Text(participant)
                    .foregroundStyle(.secondary)
            }

            ForEach(Array(tags.prefix(3)), id: \.self) { tag in
                Text(tag)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.accentColor.opacity(0.14), in: Capsule())
                    .foregroundStyle(Color.accentColor)
            }

            if tags.count > 3 {
                Text("+\(tags.count - 3)")
                    .foregroundStyle(.secondary)
            }
        }
        .font(.caption)
        .lineLimit(1)
    }
}

private struct FileRow {
    let label: String
    let value: String
}

private func displayDate(_ value: String) -> String {
    value
        .replacingOccurrences(of: "T", with: " ")
        .prefix(16)
        .description
}
