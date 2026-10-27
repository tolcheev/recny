import AppKit
import SwiftUI
import RecnyCore

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
    @State private var trimCandidate: RecordingSummary?
    @State private var reprocessCandidate: RecordingSummary?
    @State private var reprocessingRecordingIDs: Set<String> = []
    @ObservedObject private var localProcessing = LocalProcessingCoordinator.shared
    @State private var documentsCandidate: RecordingSummary?
    @State private var screenshotRecordingIDs: Set<String> = []
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
                .frame(minWidth: 560, idealWidth: 680, maxWidth: .infinity)

                detailsPanel
                    .frame(width: 430)
            }
        }
        .padding(20)
        .frame(minWidth: 1_140, minHeight: 700)
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
            restoreLocalProcessing()
        }
        .sheet(item: $tagDraft) { draft in
            TagEditorView(draft: draft) { updatedDraft in
                try appState.savePostCallDraft(updatedDraft)
                tagDraft = nil
                try? appState.reloadRecordings()
                ensureSelectionVisible()
            }
        }
        .sheet(item: $documentsCandidate) { recording in
            RecordingDocumentsView(
                recording: recording,
                displayTitle: displayTitle(for: recording),
                storageRootURL: appState.outputFolderURL,
                onClose: { documentsCandidate = nil }
            )
        }
        .sheet(item: $trimCandidate) { recording in
            AudioTrimSheet(
                recording: recording,
                displayTitle: displayTitle(for: recording),
                onExported: { result, shareAfterExport in
                    trimCandidate = nil
                    actionError = nil
                    actionMessage = "Clip exported: \(result.outputURL.lastPathComponent)."
                    if shareAfterExport {
                        NativeAudioSharing.share(url: result.outputURL)
                    }
                },
                onCancel: {
                    trimCandidate = nil
                }
            )
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
            Text("This permanently deletes the recording folder and every file inside it, including source audio, mixed exports, analysis, and metadata. This cannot be undone.")
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
                                displayTitle: displayTitle(for: recording),
                                displaySource: displaySource(for: recording),
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
                                    openShareableAudio(for: recording)
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
                                onShare: {
                                    shareAudio(for: recording)
                                },
                                onCopyAudioPath: {
                                    copyAudioPath(for: recording)
                                },
                                onTrim: {
                                    trimCandidate = recording
                                },
                                onCaptureScreenshot: {
                                    captureScreenshot(for: recording)
                                },
                                onTranscribe: {
                                    openDocuments(for: recording)
                                },
                                onReprocess: {
                                    requestReprocess(for: recording)
                                },
                                isReprocessing: reprocessingRecordingIDs.contains(recording.id),
                                isTranscribing: localProcessing.isProcessing(recording.id),
                                onEdit: {
                                    openTagEditor(for: recording)
                                },
                                onDelete: {
                                    requestDelete(recording)
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
                ScrollView {
                    LibraryRecordingDetailsPanel(
                        recording: selectedRecording,
                        displayTitle: displayTitle(for: selectedRecording),
                        displaySource: displaySource(for: selectedRecording),
                        metadata: metadata(for: selectedRecording),
                        onPlay: {
                            playMixedAudio(for: selectedRecording)
                        },
                        onOpen: {
                            openShareableAudio(for: selectedRecording)
                        },
                        onEdit: {
                            openTagEditor(for: selectedRecording)
                        },
                        onShowAnalysis: {
                            revealIfExists(selectedRecording.audioAnalysisURL)
                        },
                        onShare: { anchorView in
                            shareAudio(for: selectedRecording, anchorView: anchorView)
                        },
                        onCopyAudioPath: {
                            copyAudioPath(for: selectedRecording)
                        },
                        onTrim: {
                            trimCandidate = selectedRecording
                        },
                        onCaptureScreenshot: {
                            captureScreenshot(for: selectedRecording)
                        },
                        onTranscribe: {
                            openDocuments(for: selectedRecording)
                        },
                        isTranscribing: localProcessing.isProcessing(selectedRecording.id),
                        onDelete: {
                            requestDelete(selectedRecording)
                        }
                    )
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                }
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

        return filtered
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
            return filtersAreActive ? "No matching local recordings" : "Local recordings"
        }

        return "\(displayedRecordings.count) local recording\(displayedRecordings.count == 1 ? "" : "s")"
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
        restoreLocalProcessing()
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

    private func displayTitle(for recording: RecordingSummary) -> String {
        RecordingDisplayFormatter.recordingTitle(
            recording.title,
            sequenceNumber: sequenceNumber(for: recording)
        )
    }

    private func displaySource(for recording: RecordingSummary) -> String {
        RecordingDisplayFormatter.sourceAppText(recording.sourceApp)
    }

    private func sequenceNumber(for recording: RecordingSummary) -> Int? {
        let sorted = appState.recordings.sorted {
            if $0.startedAt == $1.startedAt {
                return $0.id < $1.id
            }

            return $0.startedAt < $1.startedAt
        }

        guard let index = sorted.firstIndex(where: { $0.id == recording.id }) else {
            return nil
        }

        return index + 1
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
            recordingTitle: displayTitle(for: recording),
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

    private func openShareableAudio(for recording: RecordingSummary) {
        guard let shareableAudio = userFacingShareableAudioOrReport(for: recording) else {
            return
        }

        NSWorkspace.shared.activateFileViewerSelecting([shareableAudio.url])
        actionError = nil
        actionMessage = "Selected final audio file: \(shareableAudio.url.lastPathComponent)."
        AppLogger.file(
            .info,
            category: "library",
            "open final audio requested recording=\(recording.id) kind=\(shareableAudio.kind.rawValue) path=\(shareableAudio.url.path(percentEncoded: false))"
        )
    }

    private func shareAudio(for recording: RecordingSummary, anchorView: NSView? = nil) {
        guard let shareableAudio = userFacingShareableAudioOrReport(for: recording) else {
            return
        }

        NativeAudioSharing.share(url: shareableAudio.url, anchorView: anchorView)
        actionError = nil
        actionMessage = "Share sheet opened for \(shareableAudio.url.lastPathComponent)."
        AppLogger.file(
            .info,
            category: "library",
            "share audio requested recording=\(recording.id) kind=\(shareableAudio.kind.rawValue) path=\(shareableAudio.url.path(percentEncoded: false))"
        )
    }

    private func copyAudioPath(for recording: RecordingSummary) {
        guard let shareableAudio = userFacingShareableAudioOrReport(for: recording) else {
            return
        }

        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(shareableAudio.url.path(percentEncoded: false), forType: .string)
        actionError = nil
        actionMessage = "Audio path copied: \(shareableAudio.url.lastPathComponent)."
        AppLogger.file(
            .info,
            category: "library",
            "copied audio path recording=\(recording.id) kind=\(shareableAudio.kind.rawValue)"
        )
    }

    private func userFacingShareableAudioOrReport(
        for recording: RecordingSummary
    ) -> RecordingPlaybackCandidate? {
        do {
            guard let shareableAudio = try RecordingPlaybackResolver.preferredUserFacingShareableAudio(
                for: recording
            ) else {
                actionError = "No shareable audio file found."
                actionMessage = nil
                return nil
            }
            return shareableAudio
        } catch {
            actionError = "Could not prepare final audio file: \(String(describing: error))"
            actionMessage = nil
            AppLogger.file(
                .error,
                category: "library",
                "prepare final audio failed recording=\(recording.id) error=\(String(describing: error))"
            )
            return nil
        }
    }

    private func captureScreenshot(for recording: RecordingSummary) {
        guard !screenshotRecordingIDs.contains(recording.id) else {
            return
        }

        screenshotRecordingIDs.insert(recording.id)
        actionError = nil
        actionMessage = "Capturing full-screen screenshot..."

        Task {
            do {
                let screenshotURL = try await NativeScreenshotCapture.captureFullScreen(
                    sessionFolderURL: recording.sessionFolderURL
                )
                actionError = nil
                actionMessage = "Screenshot saved: \(screenshotURL.lastPathComponent)."
            } catch NativeScreenshotError.cancelled {
                actionMessage = nil
            } catch {
                actionError = String(describing: error)
                actionMessage = nil
            }
            screenshotRecordingIDs.remove(recording.id)
        }
    }

    private func openDocuments(for recording: RecordingSummary) {
        selectedRecordingID = recording.id
        inlinePlayback = nil
        AudioPlaybackStopCenter.stopPlayback(inside: recording.sessionFolderURL)
        documentsCandidate = recording
    }

    private func restoreLocalProcessing() {
        let root = appState.outputFolderURL.resolvingSymlinksInPath().standardizedFileURL.path + "/"
        for recording in appState.recordings {
            let folder = recording.sessionFolderURL.resolvingSymlinksInPath().standardizedFileURL
            guard folder.path.hasPrefix(root), FileManager.default.fileExists(atPath: folder.path) else { continue }
            do {
                try localProcessing.restore(recordingID: recording.id, sessionFolderURL: folder)
            } catch {
                AppLogger.file(.warning, category: "local-ai", "restore_failed recording_id=\(recording.id)")
            }
        }
    }

    private func requestDelete(_ recording: RecordingSummary) {
        guard !localProcessing.isProcessing(recording.id) else {
            actionError = "Cancel local processing and wait for it to stop before deleting this recording."
            return
        }
        deleteCandidate = recording
    }

    private func deleteSelectedCandidate() {
        guard let recording = deleteCandidate else {
            return
        }

        guard !localProcessing.isProcessing(recording.id) else {
            deleteCandidate = nil
            actionError = "Cancel local processing and wait for it to stop before deleting this recording."
            return
        }

        do {
            stopPlaybackBeforeDeleting(recording)
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

    private func stopPlaybackBeforeDeleting(_ recording: RecordingSummary) {
        AudioPlaybackStopCenter.stopPlayback(inside: recording.sessionFolderURL)

        if RecordingPlaybackResolver.shouldStopPlaybackBeforeDeleting(
            inlinePlayback: inlinePlayback,
            deletedRecordingID: recording.id,
            deletedSessionFolderURL: recording.sessionFolderURL
        ) {
            inlinePlayback = nil
            AppLogger.file(.info, category: "playback", "closed inline player before deleting recording=\(recording.id)")
        }

        if AppWindows.closeAudioPlayer(ifPlayingInside: recording.sessionFolderURL) {
            AppLogger.file(.info, category: "playback", "closed player window before deleting recording=\(recording.id)")
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
    let displayTitle: String
    let displaySource: String
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
    let onShare: () -> Void
    let onCopyAudioPath: () -> Void
    let onTrim: () -> Void
    let onCaptureScreenshot: () -> Void
    let onTranscribe: () -> Void
    let onReprocess: () -> Void
    let isReprocessing: Bool
    let isTranscribing: Bool
    let onEdit: () -> Void
    let onDelete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(displayTitle)
                        .font(.callout.weight(.semibold))
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)

                    HStack(spacing: 6) {
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
                    .fixedSize(horizontal: false, vertical: true)

                    Text("\(displayDate(recording.startedAt)) · \(RecordingDisplayFormatter.duration(recording.durationSec)) · \(displaySource) · \(audioSummary)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)

                    CompactTagsView(participant: recording.participant, tags: recording.tags)
                }
                .layoutPriority(1)

                Spacer(minLength: 8)

                HStack(spacing: 6) {
                    if inlinePlayback == nil {
                        Button(action: onPlay) {
                            Label(RecordingDisplayFormatter.recordingRowPlayActionTitle, systemImage: "play.fill")
                        }
                        .disabled(playbackState == .missing)
                        .accessibilityLabel("Play recording")
                    } else {
                        Button(action: onClosePlayback) {
                            Label(RecordingDisplayFormatter.recordingRowClosePlayerActionTitle, systemImage: "xmark")
                        }
                        .accessibilityLabel("Close inline player")
                    }

                    Button(action: onOpen) {
                        Label(RecordingDisplayFormatter.recordingRowOpenActionTitle, systemImage: "folder")
                    }
                    .accessibilityLabel("Reveal final audio file")

                    Button(action: onEdit) {
                        Label(RecordingDisplayFormatter.recordingRowRenameActionTitle, systemImage: "pencil")
                    }
                    .accessibilityLabel("Rename recording")

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
                            Label("Reveal Final Audio File", systemImage: "music.note")
                        }

                        Button(action: onShare) {
                            Label("Share Audio...", systemImage: "square.and.arrow.up")
                        }
                        .disabled(shareableAudio == nil)

                        Button(action: onCopyAudioPath) {
                            Label("Copy Audio Path", systemImage: "doc.on.doc")
                        }
                        .disabled(shareableAudio == nil)

                        Button(action: onTrim) {
                            Label("Trim Audio...", systemImage: "scissors")
                        }
                        .disabled(shareableAudio == nil)

                        Button(action: onCaptureScreenshot) {
                            Label("Capture Full Screenshot", systemImage: "camera.viewfinder")
                        }

                        Button(action: onTranscribe) {
                            Label(isTranscribing ? "Transcript & Notes · Processing" : "Transcript & Notes", systemImage: "text.quote")
                        }
                        .help("Read transcripts and notes or process this recording locally")

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
                            Label("Rename / Tags", systemImage: "pencil")
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

    private var shareableAudio: RecordingPlaybackCandidate? {
        RecordingPlaybackResolver.preferredShareableAudio(sessionFolderURL: recording.sessionFolderURL)
    }
}

private struct LibraryRecordingDetailsPanel: View {
    let recording: RecordingSummary
    let displayTitle: String
    let displaySource: String
    let metadata: RecordingMetadata?
    let onPlay: () -> Void
    let onOpen: () -> Void
    let onEdit: () -> Void
    let onShowAnalysis: () -> Void
    let onShare: (NSView?) -> Void
    let onCopyAudioPath: () -> Void
    let onTrim: () -> Void
    let onCaptureScreenshot: () -> Void
    let onTranscribe: () -> Void
    let isTranscribing: Bool
    let onDelete: () -> Void

    var body: some View {
        RecorderCard {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 6) {
                    StatusBadge(
                        text: RecordingDisplayFormatter.statusText(recording.status),
                        tone: tone(for: recording.status)
                    )

                    Text(displayTitle)
                        .font(.headline)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)

                    Text(displayDate(recording.startedAt))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                actionsSection

                Divider()

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
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
    }

    private var actionsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 8) {
                    playButton
                    openButton
                    editButton
                }

                VStack(alignment: .leading, spacing: 8) {
                    playButton
                    openButton
                    editButton
                }
            }

            ViewThatFits(in: .horizontal) {
                HStack(spacing: 8) {
                    shareButton
                    trimButton
                    screenshotButton
                }

                VStack(alignment: .leading, spacing: 8) {
                    shareButton
                    trimButton
                    screenshotButton
                }
            }

            ViewThatFits(in: .horizontal) {
                HStack(spacing: 8) {
                    transcribeButton
                    copyPathButton
                }

                VStack(alignment: .leading, spacing: 8) {
                    transcribeButton
                    copyPathButton
                }
            }

            ViewThatFits(in: .horizontal) {
                HStack(spacing: 8) {
                    analysisButton
                }

                VStack(alignment: .leading, spacing: 8) {
                    analysisButton
                }
            }

            deleteButton
        }
        .controlSize(.regular)
    }

    private var playButton: some View {
        Button(action: onPlay) {
            Label("Play", systemImage: "play.fill")
        }
        .disabled(playbackState == .missing)
    }

    private var openButton: some View {
        Button(action: onOpen) {
            Label("Open", systemImage: "folder")
        }
    }

    private var editButton: some View {
        Button(action: onEdit) {
            Label("Rename / Tags", systemImage: "pencil")
        }
    }

    private var shareButton: some View {
        AnchoredShareButton(
            title: "Share",
            isDisabled: shareableAudio == nil,
            onShare: onShare
        )
    }

    private var trimButton: some View {
        Button(action: onTrim) {
            Label("Trim", systemImage: "scissors")
        }
        .disabled(shareableAudio == nil)
    }

    private var screenshotButton: some View {
        Button(action: onCaptureScreenshot) {
            Label("Full Screenshot", systemImage: "camera.viewfinder")
        }
    }

    private var transcribeButton: some View {
        Button(action: onTranscribe) {
            Label(isTranscribing ? "Transcript & Notes · Processing" : "Transcript & Notes", systemImage: "text.quote")
        }
        .help("Read transcripts and notes or process this recording locally")
    }

    private var copyPathButton: some View {
        Button(action: onCopyAudioPath) {
            Label("Copy Audio Path", systemImage: "doc.on.doc")
        }
        .disabled(shareableAudio == nil)
    }

    private var analysisButton: some View {
        Button(action: onShowAnalysis) {
            Label("Reveal Audio Analysis", systemImage: "doc.text.magnifyingglass")
        }
        .disabled(RecordingPlaybackResolver.nonEmptyFileSize(at: recording.audioAnalysisURL) == nil)
    }

    private var deleteButton: some View {
        Button(role: .destructive, action: onDelete) {
            Label("Delete", systemImage: "trash")
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
            detailRow("Source", displaySource)
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
            FileRow(label: "Original", value: fileDescription(kind: "mixed", fallback: "export/mixed.m4a")),
            FileRow(label: "Balanced", value: fileDescription(kind: "mixed_balanced", fallback: "export/mixed_balanced.m4a"))
        ]
    }

    private var playbackState: RecordingPlaybackDisplayState {
        RecordingPlaybackResolver.displayState(
            sessionFolderURL: recording.sessionFolderURL,
            processingStatus: metadata?.audio.processing.balancedMixStatus ?? .skipped
        )
    }

    private var shareableAudio: RecordingPlaybackCandidate? {
        RecordingPlaybackResolver.preferredShareableAudio(sessionFolderURL: recording.sessionFolderURL)
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
        HStack(alignment: .top, spacing: 10) {
            Text(label)
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
                .frame(width: 74, alignment: .leading)
                .fixedSize(horizontal: true, vertical: false)

            Text(value)
                .font(.caption)
                .lineLimit(label == "Details" ? 5 : 4)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

@MainActor
private enum NativeAudioSharing {
    static func share(url: URL, anchorView: NSView? = nil) {
        if let anchorView, anchorView.window != nil {
            let picker = NSSharingServicePicker(items: [url])
            picker.show(relativeTo: anchorView.bounds, of: anchorView, preferredEdge: .minY)
            return
        }

        guard let contentView = activeContentView else {
            NSWorkspace.shared.activateFileViewerSelecting([url])
            return
        }

        let picker = NSSharingServicePicker(items: [url])
        let anchorRect = NSRect(
            x: contentView.bounds.midX,
            y: contentView.bounds.midY,
            width: 1,
            height: 1
        )
        picker.show(relativeTo: anchorRect, of: contentView, preferredEdge: .minY)
    }

    private static var activeContentView: NSView? {
        NSApp.keyWindow?.contentView
            ?? NSApp.mainWindow?.contentView
            ?? NSApp.windows.first(where: { $0.isVisible })?.contentView
    }
}

private struct AnchoredShareButton: NSViewRepresentable {
    let title: String
    let isDisabled: Bool
    let onShare: (NSView?) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onShare: onShare)
    }

    func makeNSView(context: Context) -> NSButton {
        let button = NSButton(title: title, target: context.coordinator, action: #selector(Coordinator.share(_:)))
        button.bezelStyle = .rounded
        button.controlSize = .regular
        button.image = NSImage(systemSymbolName: "square.and.arrow.up", accessibilityDescription: nil)
        button.imagePosition = .imageLeading
        button.setButtonType(.momentaryPushIn)
        return button
    }

    func updateNSView(_ button: NSButton, context: Context) {
        context.coordinator.onShare = onShare
        button.title = title
        button.isEnabled = !isDisabled
        button.target = context.coordinator
        button.action = #selector(Coordinator.share(_:))
    }

    final class Coordinator: NSObject {
        var onShare: (NSView?) -> Void

        init(onShare: @escaping (NSView?) -> Void) {
            self.onShare = onShare
        }

        @objc func share(_ sender: NSButton) {
            onShare(sender)
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
