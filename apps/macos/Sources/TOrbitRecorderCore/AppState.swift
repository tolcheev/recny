import Combine
import Foundation

@MainActor
public final class AppState: ObservableObject {
    @Published public private(set) var status: RecordingStatus
    @Published public private(set) var currentRecordingDuration: TimeInterval
    @Published public private(set) var micStatus: CaptureStatus
    @Published public private(set) var systemAudioStatus: CaptureStatus
    @Published public private(set) var errorMessage: String?
    @Published public private(set) var postCallDraft: PostCallDraft?
    @Published public private(set) var mixedPreviewPath: String?
    @Published public var isPostCallPanelPresented: Bool
    @Published public private(set) var recordings: [RecordingSummary]
    @Published public private(set) var recoverableRecordings: [RecoverableRecordingSummary]
    @Published public private(set) var selectedTagFilter: String?
    @Published public private(set) var recordingFilters: RecordingListFilters
    @Published public private(set) var recordingSettings: RecordingSettings
    @Published public private(set) var autoStartSettings: AutoStartSettings
    @Published public private(set) var storageSettings: StorageSettings
    @Published public private(set) var hotkeySettings: HotkeySettings
    @Published public private(set) var privacySettings: PrivacySettings
    @Published public private(set) var autoStartLastDecision: String
    @Published public private(set) var outputFolderURL: URL

    private let recordingController: RecordingController
    private var recordingStore: FileSystemRecordingStore
    private let activeApplicationDetector: ActiveApplicationDetecting
    private let audioActivityDetector: AudioActivityDetecting
    private var recordingStartedAt: Date?
    private var durationTask: Task<Void, Never>?
    private var autoStartTask: Task<Void, Never>?
    private var autoStartEngine: AutoStartEngine
    private var lastRecordingStoppedAt: Date?
    private var lastAutoStartDecisionLogKey: String?

    public var outputFolderPath: String {
        outputFolderURL.path(percentEncoded: false)
    }

    public var formattedDuration: String {
        Self.formatDuration(currentRecordingDuration)
    }

    public init(
        recordingController: RecordingController? = nil,
        outputFolderURL: URL? = nil,
        activeApplicationDetector: ActiveApplicationDetecting? = nil,
        audioActivityDetector: AudioActivityDetecting? = nil,
        autoStartSettings: AutoStartSettings? = nil,
        appSettings: AppSettings = AppSettingsStore.load()
    ) {
        var resolvedSettings = appSettings
        if let autoStartSettings {
            resolvedSettings.autoStart = autoStartSettings
        }
        if let outputFolderURL {
            resolvedSettings.storage.rootFolderPath = outputFolderURL.path(percentEncoded: false)
        }

        self.recordingController = recordingController ?? MacOSAudioRecordingController()
        self.outputFolderURL = resolvedSettings.storage.rootFolderURL
        self.activeApplicationDetector = activeApplicationDetector ?? WorkspaceActiveApplicationDetector()
        self.audioActivityDetector = audioActivityDetector ?? CoreAudioActivityDetector()
        self.status = .idle
        self.currentRecordingDuration = 0
        self.micStatus = .idle
        self.systemAudioStatus = .idle
        self.errorMessage = nil
        self.postCallDraft = nil
        self.mixedPreviewPath = nil
        self.isPostCallPanelPresented = false
        self.recordings = []
        self.recoverableRecordings = []
        self.selectedTagFilter = nil
        self.recordingFilters = RecordingListFilters()
        self.recordingSettings = resolvedSettings.recording
        self.autoStartSettings = resolvedSettings.autoStart
        self.storageSettings = resolvedSettings.storage
        self.hotkeySettings = resolvedSettings.hotkeys
        self.privacySettings = resolvedSettings.privacy
        self.autoStartLastDecision = "not_checked"
        self.autoStartEngine = AutoStartEngine()
        self.recordingStore = FileSystemRecordingStore(rootURL: resolvedSettings.storage.rootFolderURL)
        reloadRecordingsSilently()
        reloadRecoverableRecordingsSilently()
    }

    deinit {
        durationTask?.cancel()
        autoStartTask?.cancel()
    }

    public func startRecording() async throws {
        try await startRecording(
            source: RecordingSource(
                appName: "TOrbitRecorder",
                bundleID: "com.torbit.recorder",
                trigger: "manual",
                ruleID: "manual.audio"
            )
        )
    }

    public func startRecording(source: RecordingSource) async throws {
        do {
            try FileManager.default.createDirectory(
                at: outputFolderURL,
                withIntermediateDirectories: true
            )

            let update = try await recordingController.startRecording(
                outputFolder: outputFolderURL,
                source: source,
                settings: recordingRuntimeSettings()
            )
            apply(update)
            recordingStartedAt = update.startedAt ?? Date()
            currentRecordingDuration = 0
            mixedPreviewPath = nil
            errorMessage = nil
            startDurationClock()
            AppLogger.recording.info("Recording state changed to recording. trigger=\(source.trigger, privacy: .public), app=\(source.appName, privacy: .public), bundle_id=\(source.bundleID, privacy: .public), rule_id=\(source.ruleID, privacy: .public)")
        } catch {
            applyError(error)
            AppLogger.recording.error("Failed to start recording: \(String(describing: error), privacy: .public)")
            throw error
        }
    }

    public func stopRecording() async throws {
        do {
            let update = try await recordingController.stopRecording()
            apply(update)
            stopDurationClock()

            guard let draft = update.postCallDraft else {
                throw RecordingControllerError.notRecording
            }

            postCallDraft = draft
            mixedPreviewPath = mixedPreviewPath(for: draft)
            isPostCallPanelPresented = draft.status != .shortRecording && draft.status != .failed
            lastRecordingStoppedAt = Date()
            try reloadRecordings()
            try reloadRecoverableRecordings()
            errorMessage = nil
            if draft.status == .shortRecording {
                AppLogger.recording.info("Recording stopped as short_recording; post-call tagging skipped for \(draft.id, privacy: .public)")
            } else {
                AppLogger.recording.info("Recording stopped; post-call tagging required for \(draft.id, privacy: .public)")
            }
        } catch {
            applyError(error)
            AppLogger.recording.error("Failed to stop recording: \(String(describing: error), privacy: .public)")
            throw error
        }
    }

    public func savePostCallDraft(_ draft: PostCallDraft) throws {
        try recordingStore.saveDraft(draft)
        postCallDraft = draft
        isPostCallPanelPresented = false
        try reloadRecordings()
        AppLogger.recording.info("Saved post-call tags for \(draft.id, privacy: .public)")
    }

    public func setTagFilter(_ tag: String?) {
        selectedTagFilter = tag
        recordingFilters.tags = tag.map { [$0] } ?? []
        reloadRecordingsSilently()
    }

    public func setDateFilter(_ value: String) {
        recordingFilters.dateText = value
        reloadRecordingsSilently()
    }

    public func setStatusFilter(_ status: TaggingStatus?) {
        recordingFilters.status = status
        reloadRecordingsSilently()
    }

    public func setSourceAppFilter(_ value: String) {
        recordingFilters.sourceAppText = value
        reloadRecordingsSilently()
    }

    public func setTitleFilter(_ value: String) {
        recordingFilters.titleText = value
        reloadRecordingsSilently()
    }

    public func clearRecordingFilters() {
        recordingFilters = RecordingListFilters()
        selectedTagFilter = nil
        reloadRecordingsSilently()
    }

    public func reloadRecordings() throws {
        recordings = try recordingStore.recordings(filters: recordingFilters)
    }

    public func updateRecording(_ recording: RecordingSummary, title: String, tags: [String]) throws {
        try recordingStore.updateRecording(id: recording.id, title: title, tags: tags)
        try reloadRecordings()
    }

    public func deleteLocalRecord(_ recording: RecordingSummary) throws {
        try recordingStore.deleteLocalRecord(recording)
        try reloadRecordings()
    }

    public func setAutoStartEnabled(_ isEnabled: Bool) {
        updateAutoStartSettings { settings in
            settings.isEnabled = isEnabled
        }
    }

    public func setAutoStartWhitelist(_ whitelist: [String]) {
        updateAutoStartSettings { settings in
            settings.whitelist = normalizedAppList(whitelist)
        }
    }

    public func setAutoStartBlacklist(_ blacklist: [String]) {
        updateAutoStartSettings { settings in
            settings.blacklist = normalizedAppList(blacklist)
        }
    }

    public func setAutoStartCooldownSeconds(_ seconds: TimeInterval) {
        updateAutoStartSettings { settings in
            settings = AutoStartSettings(
                isEnabled: settings.isEnabled,
                whitelist: settings.whitelist,
                blacklist: settings.blacklist,
                cooldownSeconds: seconds,
                minDetectionDurationSeconds: settings.minDetectionDurationSeconds,
                shortRecordingThresholdSeconds: settings.shortRecordingThresholdSeconds
            )
        }
    }

    public func setAutoStartMinDetectionDurationSeconds(_ seconds: TimeInterval) {
        updateAutoStartSettings { settings in
            settings = AutoStartSettings(
                isEnabled: settings.isEnabled,
                whitelist: settings.whitelist,
                blacklist: settings.blacklist,
                cooldownSeconds: settings.cooldownSeconds,
                minDetectionDurationSeconds: seconds,
                shortRecordingThresholdSeconds: settings.shortRecordingThresholdSeconds
            )
        }
    }

    public func setShortRecordingThresholdSeconds(_ seconds: TimeInterval) {
        updateAutoStartSettings { settings in
            settings = AutoStartSettings(
                isEnabled: settings.isEnabled,
                whitelist: settings.whitelist,
                blacklist: settings.blacklist,
                cooldownSeconds: settings.cooldownSeconds,
                minDetectionDurationSeconds: settings.minDetectionDurationSeconds,
                shortRecordingThresholdSeconds: seconds
            )
        }
    }

    public func setSystemAudioEnabled(_ isEnabled: Bool) {
        recordingSettings.systemAudioEnabled = isEnabled
        saveSettings()
    }

    public func setMixedPreviewEnabled(_ isEnabled: Bool) {
        recordingSettings.mixedPreviewEnabled = isEnabled
        saveSettings()
    }

    public func resetStorageRootToDefault() {
        setStorageRoot(RecordingPaths.defaultRoot)
    }

    public func setShowRecordingIndicator(_ isEnabled: Bool) {
        privacySettings.showRecordingIndicator = isEnabled
        saveSettings()
    }

    public func setStorageRoot(_ url: URL) {
        outputFolderURL = url
        storageSettings.rootFolderPath = url.path(percentEncoded: false)
        recordingStore = FileSystemRecordingStore(rootURL: url)
        reloadRecordingsSilently()
        reloadRecoverableRecordingsSilently()
        saveSettings()
    }

    public func startAutoStartMonitoring(pollIntervalSeconds: TimeInterval = 5) {
        guard autoStartTask == nil else {
            return
        }

        let interval = UInt64(max(1, pollIntervalSeconds) * 1_000_000_000)
        autoStartTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                guard let self else {
                    return
                }

                await self.evaluateAutoStartNow()

                do {
                    try await Task.sleep(nanoseconds: interval)
                } catch {
                    return
                }
            }
        }
    }

    public func stopAutoStartMonitoring() {
        autoStartTask?.cancel()
        autoStartTask = nil
    }

    public func evaluateAutoStartNow(now: Date = Date()) async {
        await evaluateAutoStart(
            activeApplication: activeApplicationDetector.activeApplication(),
            audioActivity: audioActivityDetector.audioActivity(),
            now: now
        )
    }

    public func evaluateAutoStart(
        activeApplication: ActiveApplicationSnapshot?,
        audioActivity: AudioActivitySnapshot,
        now: Date
    ) async {
        let decision = autoStartEngine.evaluate(
            AutoStartEvaluationContext(
                activeApplication: activeApplication,
                audioActivity: audioActivity,
                isAlreadyRecording: status == .recording,
                lastStoppedAt: lastRecordingStoppedAt,
                now: now
            ),
            settings: autoStartSettings
        )

        applyAutoStartDecision(decision)

        guard decision.action == .start, let source = decision.recordingSource else {
            return
        }

        do {
            try await startRecording(source: source)
        } catch {
            applyError(error)
            AppLogger.recording.error("Auto-start failed: reason=\(decision.reason.rawValue, privacy: .public), app=\(source.appName, privacy: .public), bundle_id=\(source.bundleID, privacy: .public), error=\(String(describing: error), privacy: .public)")
        }
    }

    public func reloadRecoverableRecordings() throws {
        guard status != .recording else {
            return
        }

        recoverableRecordings = try recordingStore.recoverableSessions()
    }

    public func recoverRecording(_ summary: RecoverableRecordingSummary) async throws {
        do {
            let draft = try await RecordingRecoveryController(store: recordingStore).recover(summary)
            postCallDraft = draft
            mixedPreviewPath = mixedPreviewPath(for: draft)
            isPostCallPanelPresented = draft.status != .failed
            try reloadRecordings()
            try reloadRecoverableRecordings()
            errorMessage = nil
            AppLogger.recording.info("Recovered interrupted recording \(summary.id, privacy: .public)")
        } catch {
            applyError(error)
            AppLogger.recording.error("Failed to recover recording \(summary.id, privacy: .public): \(String(describing: error), privacy: .public)")
            throw error
        }
    }

    private func apply(_ update: RecordingControllerUpdate) {
        status = update.status
        micStatus = update.micStatus
        systemAudioStatus = update.systemAudioStatus

        if let duration = update.duration {
            currentRecordingDuration = duration
        }
    }

    private func applyAutoStartDecision(_ decision: AutoStartDecision) {
        autoStartLastDecision = "\(decision.reason.rawValue): \(decision.message)"
        let logKey = "\(decision.action)-\(decision.reason)-\(decision.message)"
        guard decision.action == .start || logKey != lastAutoStartDecisionLogKey else {
            return
        }

        lastAutoStartDecisionLogKey = logKey
        AppLogger.recording.info("Auto-start decision: action=\(String(describing: decision.action), privacy: .public), reason=\(decision.reason.rawValue, privacy: .public), message=\(decision.message, privacy: .public)")
    }

    private func applyError(_ error: Error) {
        status = .error
        micStatus = Self.captureStatus(for: error)
        systemAudioStatus = Self.systemAudioStatus(for: error)
        errorMessage = String(describing: error)
        stopDurationClock()
    }

    private static func captureStatus(for error: Error) -> CaptureStatus {
        guard let recordingError = error as? RecordingControllerError else {
            return .error
        }

        switch recordingError {
        case .microphonePermissionDenied:
            return .permissionDenied
        case .noInputDevice:
            return .noInputDevice
        case .systemAudioPermissionDenied, .noShareableDisplay, .systemAudioSetupFailed, .systemAudioWriteFailed, .systemAudioNoSamples:
            return .idle
        default:
            return .error
        }
    }

    private static func systemAudioStatus(for error: Error) -> CaptureStatus {
        guard let recordingError = error as? RecordingControllerError else {
            return .error
        }

        switch recordingError {
        case .microphonePermissionDenied, .noInputDevice:
            return .idle
        case .systemAudioPermissionDenied:
            return .permissionDenied
        case .noShareableDisplay, .systemAudioSetupFailed, .systemAudioWriteFailed, .systemAudioNoSamples:
            return .error
        default:
            return .error
        }
    }

    private func reloadRecordingsSilently() {
        do {
            try reloadRecordings()
        } catch {
            AppLogger.storage.error("Failed to reload recordings: \(String(describing: error), privacy: .public)")
        }
    }

    private func reloadRecoverableRecordingsSilently() {
        do {
            try reloadRecoverableRecordings()
        } catch {
            AppLogger.storage.error("Failed to reload recoverable recordings: \(String(describing: error), privacy: .public)")
        }
    }

    private func mixedPreviewPath(for draft: PostCallDraft) -> String? {
        let url = draft.sessionFolderURL
            .appendingPathComponent("export", isDirectory: true)
            .appendingPathComponent("mixed.m4a")
        let path = url.path(percentEncoded: false)
        return FileManager.default.fileExists(atPath: path) ? path : nil
    }

    private func updateAutoStartSettings(_ mutate: (inout AutoStartSettings) -> Void) {
        var settings = autoStartSettings
        mutate(&settings)
        autoStartSettings = AutoStartSettings(
            isEnabled: settings.isEnabled,
            whitelist: normalizedAppList(settings.whitelist),
            blacklist: normalizedAppList(settings.blacklist),
            cooldownSeconds: settings.cooldownSeconds,
            minDetectionDurationSeconds: settings.minDetectionDurationSeconds,
            shortRecordingThresholdSeconds: settings.shortRecordingThresholdSeconds
        )
        autoStartEngine.resetCandidate()
        saveSettings()
    }

    private func recordingRuntimeSettings() -> RecordingRuntimeSettings {
        RecordingRuntimeSettings(
            systemAudioEnabled: recordingSettings.systemAudioEnabled,
            mixedPreviewEnabled: recordingSettings.mixedPreviewEnabled,
            shortRecordingThresholdSeconds: autoStartSettings.shortRecordingThresholdSeconds
        )
    }

    private func saveSettings() {
        AppSettingsStore.save(
            AppSettings(
                recording: recordingSettings,
                autoStart: autoStartSettings,
                storage: storageSettings,
                hotkeys: hotkeySettings,
                privacy: privacySettings
            )
        )
    }

    private func normalizedAppList(_ values: [String]) -> [String] {
        var seen = Set<String>()
        return values.compactMap { value in
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else {
                return nil
            }

            let key = trimmed.lowercased()
            guard seen.insert(key).inserted else {
                return nil
            }

            return trimmed
        }
    }

    private func startDurationClock() {
        durationTask?.cancel()

        durationTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else {
                    return
                }

                self.refreshDuration()

                do {
                    try await Task.sleep(for: .seconds(1))
                } catch {
                    return
                }
            }
        }
    }

    private func stopDurationClock() {
        durationTask?.cancel()
        durationTask = nil
        recordingStartedAt = nil
        currentRecordingDuration = 0
    }

    private func refreshDuration() {
        guard status == .recording, let recordingStartedAt else {
            return
        }

        currentRecordingDuration = Date().timeIntervalSince(recordingStartedAt)
    }

    private static func formatDuration(_ duration: TimeInterval) -> String {
        let totalSeconds = max(0, Int(duration.rounded(.down)))
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let seconds = totalSeconds % 60

        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        }

        return String(format: "%02d:%02d", minutes, seconds)
    }
}
