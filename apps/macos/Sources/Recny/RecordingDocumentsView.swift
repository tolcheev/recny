import AppKit
import SwiftUI
import UniformTypeIdentifiers
import RecnyCore

/// Document presentation never owns a processing task: queued work survives dismissal.
struct RecordingDocumentsView: View {
    let recording: RecordingSummary
    let displayTitle: String
    let storageRootURL: URL
    let onClose: () -> Void

    @ObservedObject private var coordinator = LocalProcessingCoordinator.shared
    @State private var transcript: LocalRecordingTranscript?
    @State private var structuredNotes: LocalStructuredNotes?
    @State private var savedMarkdown = ""
    @State private var diskMarkdown: String?
    @State private var notesDraft = ""
    @State private var legacyNote: String?
    @State private var selectedTab = DocumentTab.transcript
    @State private var preset = LocalNotesPreset.meeting
    @State private var search = ""
    @State private var focusedSegmentID: String?
    @State private var editing = false
    @State private var errorMessage: String?
    @State private var documentsChanged = false
    @State private var pendingAction: PendingAction?
    @State private var audioURL: URL?
    @State private var seekRequest: SegmentSeekRequest?
    @State private var currentAudioIdentity: LocalAudioIdentity?
    @State private var sourceCheckTask: Task<Void, Never>?
    @State private var checkingAudio = false
    @State private var transcriptionReady = false
    @State private var notesStatus = LocalAIStatus(ready: false, message: "Checking local notes setup…")

    private enum DocumentTab: String { case transcript = "Transcript", notes = "Notes" }
    private enum PendingAction { case close, reload, retry, process(LocalProcessingMode) }
    private var store: LocalRecordingDocumentStore { .init(sessionFolderURL: recording.sessionFolderURL) }
    private var dirty: Bool { notesDraft != savedMarkdown }
    private var busy: Bool { coordinator.isProcessing(recording.id) }
    private var job: LocalProcessingJobState? { coordinator.jobs[recording.id] }
    private var notesAreStale: Bool {
        guard structuredNotes != nil || !savedMarkdown.isEmpty else { return false }
        return !LocalDocumentFreshness.referencesAreCurrent(transcript: transcript, notes: structuredNotes, currentAudio: currentAudioIdentity)
    }
    private var transcriptIsCurrent: Bool {
        LocalDocumentFreshness.transcriptIsCurrent(transcript, currentAudio: currentAudioIdentity)
    }
    private var visibleSegments: [LocalTranscriptSegment] {
        (transcript?.segments ?? []).filter { search.isEmpty || $0.text.localizedCaseInsensitiveContains(search) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            processingControls
            if let errorMessage {
                Label(errorMessage, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.red).font(.callout).textSelection(.enabled)
            }
            if documentsChanged {
                Label("Documents changed on disk. Reload to review them; your unsaved edits are still here.", systemImage: "arrow.clockwise")
                    .font(.callout).foregroundStyle(.orange)
            }
            Picker("Document", selection: $selectedTab) {
                Text("Transcript").tag(DocumentTab.transcript)
                Text(dirty ? "Notes • Unsaved" : "Notes").tag(DocumentTab.notes)
            }
            .pickerStyle(.segmented)
            if selectedTab == .transcript { transcriptContent } else { notesContent }
            if let audioURL {
                Divider()
                DocumentAudioPlayer(url: audioURL, title: displayTitle, seekRequest: seekRequest)
                    .id(audioURL)
            }
        }
        .padding(20)
        .frame(minWidth: 780, idealWidth: 880, minHeight: 650, idealHeight: 760)
        .interactiveDismissDisabled()
        .onDisappear { sourceCheckTask?.cancel() }
        .task {
            audioURL = RecordingPlaybackResolver.preferredShareableAudio(sessionFolderURL: recording.sessionFolderURL)?.url
            loadDocuments()
            await refreshSetup()
        }
        .onChange(of: job?.stage) { _, stage in
            guard let stage, !stage.isActive else { return }
            if dirty { documentsChanged = true } else { loadDocuments() }
        }
        .confirmationDialog("Unsaved notes", isPresented: Binding(
            get: { pendingAction != nil }, set: { if !$0 { pendingAction = nil } }
        ), titleVisibility: .visible) {
            Button("Save and Continue") {
                if saveNotes() { performPendingAction() }
            }
            .disabled(busy)
            Button("Discard Edits and Continue", role: .destructive) {
                notesDraft = savedMarkdown
                performPendingAction()
            }
            Button("Keep Editing", role: .cancel) { pendingAction = nil }
        } message: {
            Text("Save your notes before continuing, or discard the unsaved changes. Saved notes are kept in local history when replaced.")
        }
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Transcript & Notes").font(.title2.weight(.semibold))
                Text(displayTitle).font(.callout).foregroundStyle(.secondary).lineLimit(2)
            }
            Spacer()
            Button("Reload") { request(.reload) }.disabled(busy)
            Button("Close") { request(.close) }.keyboardShortcut(.cancelAction)
        }
    }

    private var processingControls: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Picker("Notes preset", selection: $preset) {
                    ForEach(LocalNotesPreset.allCases, id: \.self) { value in Text(value.title).tag(value) }
                }
                .frame(width: 225).disabled(busy)
                Spacer()
                Button("Process Locally") { request(.process(.all)) }
                    .disabled(busy || audioURL == nil || !transcriptionReady || !notesStatus.ready)
                Menu("More") {
                    Button("Transcribe Only") { request(.process(.transcript)) }
                        .disabled(busy || audioURL == nil || !transcriptionReady)
                    Button("Regenerate Notes") { request(.process(.notes)) }
                        .disabled(busy || audioURL == nil || transcript?.source == nil || !notesStatus.ready)
                }
            }
            if let job {
                HStack(spacing: 8) {
                    if busy { ProgressView().controlSize(.small) }
                    Text(job.stage.title).font(.callout)
                    if let message = job.message { Text(message).font(.caption).textSelection(.enabled) }
                    Spacer()
                    if busy {
                        Button("Cancel Processing") { coordinator.cancel(recording.id) }
                    } else if [.failed, .cancelled, .interrupted].contains(job.stage) {
                        Button("Retry") { request(.retry) }.disabled(audioURL == nil)
                    }
                }
            }
            if !transcriptionReady || !notesStatus.ready {
                Text(!transcriptionReady ? "Prepare Parakeet and ffmpeg in Settings to transcribe. \(notesStatus.message)" : notesStatus.message)
                    .font(.caption).foregroundStyle(.secondary)
                HStack {
                    SettingsLink { Label("Open Settings", systemImage: "gearshape") }
                    Button("Check Setup") { Task { await refreshSetup() } }.disabled(busy)
                }
            }
            Text("Manual, on-device processing. Closing this view keeps queued work running. Generated notes may contain mistakes; use source references to check them.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private var transcriptContent: some View {
        VStack(alignment: .leading, spacing: 10) {
            TextField("Search transcript", text: $search).textFieldStyle(.roundedBorder)
            if transcript != nil && !transcriptIsCurrent {
                Text(checkingAudio ? "Verifying source audio…" : "Transcript source is unverified or the audio changed. Transcribe again to enable timestamp playback.")
                    .font(.caption).foregroundStyle(.orange)
            }
            if transcript == nil {
                emptyDocument("No transcript yet", detail: "Process this recording locally, or choose Transcribe Only after setup.")
            } else {
                if transcript?.source == nil {
                    Text("Legacy transcript. Source audio has not been verified. Transcribe again before generating notes.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                ScrollViewReader { reader in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 14) {
                            ForEach(visibleSegments) { segment in
                                HStack(alignment: .top, spacing: 12) {
                                    if let start = segment.start {
                                        Button(RecordingDisplayFormatter.duration(start)) { seek(to: segment) }
                                            .font(.caption.monospacedDigit())
                                            .disabled(audioURL == nil || !transcriptIsCurrent)
                                            .help("Seek to this segment without starting playback")
                                    } else {
                                        Text(segment.id).font(.caption).foregroundStyle(.secondary)
                                    }
                                    Text(segment.text).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
                                }
                                .padding(8)
                                .background(focusedSegmentID == segment.id ? Color.accentColor.opacity(0.10) : Color.clear, in: RoundedRectangle(cornerRadius: 6))
                                .id(segment.id)
                            }
                            if visibleSegments.isEmpty { Text("No matching segments").foregroundStyle(.secondary) }
                        }
                    }
                    .onChange(of: focusedSegmentID) { _, id in
                        if let id { reader.scrollTo(id, anchor: .center) }
                    }
                    .onAppear { if let focusedSegmentID { reader.scrollTo(focusedSegmentID, anchor: .center) } }
                }
            }
        }
    }

    private var notesContent: some View {
        VStack(alignment: .leading, spacing: 10) {
            if notesAreStale {
                Label("These notes do not have a verified match to the current transcript. Source references may be outdated.", systemImage: "exclamationmark.triangle")
                    .font(.caption).foregroundStyle(.orange)
            }
            HStack {
                Toggle("Edit Markdown", isOn: $editing).toggleStyle(.switch).disabled(busy)
                Spacer()
                Button("Save") { _ = saveNotes() }.disabled(!dirty || busy)
                Button("Copy") { copyNotes() }.disabled(notesDraft.isEmpty)
                Button("Export Markdown…") { exportNotes() }.disabled(notesDraft.isEmpty || busy)
            }
            if editing {
                TextEditor(text: $notesDraft)
                    .font(.body.monospaced()).disabled(busy)
                    .accessibilityLabel("Notes Markdown editor")
            } else if !notesDraft.isEmpty {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 10) {
                        ForEach(Array(notesDraft.components(separatedBy: "\n").enumerated()), id: \.offset) { _, line in
                            NotesMarkdownLine(line: line, segments: transcript?.segments ?? [], referencesEnabled: !notesAreStale) { id in
                                showSource(id)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            } else if let legacyNote {
                VStack(alignment: .leading) {
                    Text("Legacy note — saved prompt and transcript, not generated notes")
                        .font(.caption).foregroundStyle(.secondary)
                    ScrollView { Text(legacyNote).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading) }
                }
            } else {
                emptyDocument("No notes yet", detail: "Choose a preset and process locally. An existing verified transcript can be used with Regenerate Notes.")
            }
        }
    }

    private func emptyDocument(_ title: String, detail: String) -> some View {
        VStack(spacing: 8) {
            Text(title).font(.headline)
            Text(detail).foregroundStyle(.secondary).multilineTextAlignment(.center)
        }.frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func refreshSetup() async {
        transcriptionReady = LocalTranscriptionSetupInspector.status().canTranscribeWithoutSetup
        notesStatus = await LocalAISetup().notesStatus()
    }

    private func loadDocuments() {
        var errors: [String] = []
        // Read independently: malformed provider metadata must not hide readable Markdown.
        transcript = nil
        structuredNotes = nil
        legacyNote = nil
        do { transcript = try store.loadTranscript() }
        catch { errors.append("Could not read transcript: \(error.localizedDescription)") }
        do { structuredNotes = try store.loadNotes() }
        catch { errors.append("Could not read structured notes: \(error.localizedDescription)") }
        do {
            diskMarkdown = try store.loadNotesMarkdown()
            savedMarkdown = diskMarkdown ?? structuredNotes?.markdown ?? ""
            notesDraft = savedMarkdown
            documentsChanged = false
        } catch { errors.append("Could not read notes: \(error.localizedDescription)") }
        do {
            if let data = try store.read("call_note.md") { legacyNote = String(data: data, encoding: .utf8) }
        } catch { errors.append("Could not read legacy note: \(error.localizedDescription)") }
        if let restoredPreset = job?.preset ?? structuredNotes?.preset { preset = restoredPreset }
        verifySourceAudio()
        errorMessage = errors.isEmpty ? nil : errors.joined(separator: "\n")
    }

    private func verifySourceAudio() {
        sourceCheckTask?.cancel()
        currentAudioIdentity = nil
        audioURL = RecordingPlaybackResolver.preferredShareableAudio(sessionFolderURL: recording.sessionFolderURL)?.url
        guard let audioURL else { checkingAudio = false; return }
        checkingAudio = true
        sourceCheckTask = Task {
            let reader = Task.detached(priority: .utility) { try LocalAudioIdentity.read(audioURL) }
            do {
                let identity = try await withTaskCancellationHandler { try await reader.value } onCancel: { reader.cancel() }
                try Task.checkCancellation()
                currentAudioIdentity = identity
                checkingAudio = false
            } catch {
                guard !Task.isCancelled else { return }
                checkingAudio = false
                currentAudioIdentity = nil
            }
        }
    }

    private func request(_ action: PendingAction) {
        if dirty { pendingAction = action } else { perform(action) }
    }

    private func performPendingAction() {
        guard let action = pendingAction else { return }
        pendingAction = nil
        perform(action)
    }

    private func perform(_ action: PendingAction) {
        switch action {
        case .close: onClose()
        case .reload: loadDocuments()
        case .retry:
            guard let job else { return }
            preset = job.preset
            perform(.process(job.mode))
        case .process(let mode):
            guard !busy else { return }
            guard let audio = RecordingPlaybackResolver.preferredShareableAudio(sessionFolderURL: recording.sessionFolderURL) else {
                errorMessage = "No playable audio found for this recording."
                return
            }
            audioURL = audio.url
            errorMessage = nil
            do {
                try coordinator.enqueue(.init(recordingID: recording.id, sessionFolderURL: recording.sessionFolderURL,
                    audioURL: audio.url, storageRootURL: storageRootURL, preset: preset, mode: mode))
            } catch { errorMessage = error.localizedDescription }
        }
    }

    @discardableResult private func saveNotes() -> Bool {
        guard !busy else { errorMessage = "Wait for local processing to finish before saving notes."; return false }
        do {
            // Include the absent-file case; expected:nil alone disables the store's conflict check.
            guard try store.loadNotesMarkdown() == diskMarkdown else { throw LocalDocumentError.editConflict }
            try store.saveEditedNotes(notesDraft, expected: diskMarkdown)
            savedMarkdown = notesDraft
            diskMarkdown = notesDraft
            errorMessage = nil
            return true
        } catch { errorMessage = error.localizedDescription; return false }
    }

    private func showSource(_ id: String) {
        guard let segment = transcript?.segments.first(where: { $0.id == id }) else { return }
        search = ""
        focusedSegmentID = id
        selectedTab = .transcript
        seek(to: segment)
    }

    private func seek(to segment: LocalTranscriptSegment) {
        focusedSegmentID = segment.id
        if transcriptIsCurrent, let start = segment.start { seekRequest = SegmentSeekRequest(seconds: start) }
    }

    private func copyNotes() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(notesDraft, forType: .string)
    }

    private func exportNotes() {
        guard !busy else { return }
        let panel = NSSavePanel()
        panel.title = "Export Notes"
        panel.nameFieldStringValue = "notes.md"
        panel.allowedContentTypes = [UTType(filenameExtension: "md") ?? .plainText]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let folder = recording.sessionFolderURL.resolvingSymlinksInPath().standardizedFileURL.path + "/"
        guard !url.resolvingSymlinksInPath().standardizedFileURL.path.hasPrefix(folder) else {
            errorMessage = "Export outside this recording folder. Use Save to update notes and preserve their history."
            return
        }
        do { try notesDraft.write(to: url, atomically: true, encoding: .utf8) }
        catch { errorMessage = "Could not export notes: \(error.localizedDescription)" }
    }
}

private struct NotesMarkdownLine: View {
    let line: String
    let segments: [LocalTranscriptSegment]
    let referencesEnabled: Bool
    let onSource: (String) -> Void

    private var references: [(text: String, id: String)] {
        guard let regex = try? NSRegularExpression(pattern: #"\[([^\]]+)\]\(recny-segment:([A-Za-z0-9_]+)\)"#) else { return [] }
        return regex.matches(in: line, range: NSRange(line.startIndex..., in: line)).compactMap { match in
            guard let full = Range(match.range, in: line), let idRange = Range(match.range(at: 2), in: line) else { return nil }
            return (String(line[full]), String(line[idRange]))
        }
    }
    private var displayText: String {
        references.reduce(line) { $0.replacingOccurrences(of: $1.text, with: "") }
            .trimmingCharacters(in: .whitespaces)
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            if displayText.hasPrefix("## ") {
                Text(String(displayText.dropFirst(3))).font(.headline).textSelection(.enabled)
            } else if displayText.hasPrefix("# ") {
                Text(String(displayText.dropFirst(2))).font(.title3).textSelection(.enabled)
            } else if !displayText.isEmpty {
                Text(displayText).textSelection(.enabled)
            }
            if !references.isEmpty {
                // A horizontal scroll keeps unusually many references inside the document width.
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack {
                        ForEach(Array(references.enumerated()), id: \.offset) { _, reference in
                            let segment = segments.first(where: { $0.id == reference.id })
                            Button(segment?.start.map { RecordingDisplayFormatter.duration($0) } ?? reference.id) { onSource(reference.id) }
                                .buttonStyle(.link).font(.caption)
                                .disabled(!referencesEnabled || segment == nil)
                                .help("Show transcript source \(reference.id)")
                        }
                    }
                }
            }
        }
    }
}

private struct SegmentSeekRequest: Equatable {
    let id = UUID()
    let seconds: TimeInterval
}

private struct DocumentAudioPlayer: View {
    @StateObject private var player: AudioPlayerViewModel
    let seekRequest: SegmentSeekRequest?
    init(url: URL, title: String, seekRequest: SegmentSeekRequest?) {
        _player = StateObject(wrappedValue: AudioPlayerViewModel(url: url, title: title))
        self.seekRequest = seekRequest
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Button(player.isPlaying ? "Pause" : "Play") { player.togglePlayback() }
                Text(RecordingDisplayFormatter.duration(player.currentTime)).font(.caption.monospacedDigit())
                Slider(value: Binding(get: { player.currentTime }, set: { player.seek(to: $0) }), in: 0...max(1, player.duration))
                    .accessibilityLabel("Recording playback position")
                Text(RecordingDisplayFormatter.duration(player.duration)).font(.caption.monospacedDigit())
            }
            if let error = player.errorMessage { Text(error).font(.caption).foregroundStyle(.orange) }
        }
        .onChange(of: seekRequest) { _, request in
            if let request, player.duration > 0 { player.seek(to: request.seconds) }
        }
        .onChange(of: player.duration) { _, duration in
            if duration > 0, let seekRequest { player.seek(to: seekRequest.seconds) }
        }
        .onDisappear { player.stopAndTearDown() }
        .onReceive(NotificationCenter.default.publisher(for: AudioPlaybackStopCenter.notificationName)) { notification in
            if let folder = AudioPlaybackStopCenter.sessionFolderURL(from: notification) { player.stopIfPlaying(insideSessionFolder: folder) }
        }
    }
}
