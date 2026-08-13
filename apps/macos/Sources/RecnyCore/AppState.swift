import Combine
import Foundation

public struct PendingAutoStartPrompt: Equatable, Sendable {
    public let source: RecordingSource
    public let message: String
    public let confidence: String
    public let detectedAt: Date

    public init(
        source: RecordingSource,
        message: String,
        confidence: String,
        detectedAt: Date
    ) {
        self.source = source
        self.message = message
        self.confidence = confidence
        self.detectedAt = detectedAt
    }
}

@MainActor
public final class AppState: ObservableObject {
    public static let defaultAutoStartMonitoringPollIntervalSeconds: TimeInterval = 1

    private static let legacySystemAudioPermissionProbeSucceededKey =
        "com.torbit.recorder.systemAudioPermissionProbeSucceeded"
    private static let systemAudioPermissionProbeVersion = "core-audio-capture-start-v2"
    private static var systemAudioPermissionProbeSucceededKey: String {
        let fingerprint = [
            BuildInfo.appVersion,
            BuildInfo.buildDate,
            BuildInfo.gitCommit
        ]
            .map(sanitizedPermissionCacheComponent)
            .joined(separator: ".")
        return "\(legacySystemAudioPermissionProbeSucceededKey).\(fingerprint).\(systemAudioPermissionProbeVersion)"
    }
    internal static var systemAudioPermissionProbeSucceededKeyForTesting: String {
        systemAudioPermissionProbeSucceededKey
    }
    /// Maximum grace period the engine ever waits before stopping a
    /// signal-lost recording. Used only as a defensive upper bound; the
    /// active value comes from `autoStartSettings.autoStopDelaySeconds`.
    private static let autoStopSignalLostGracePeriodSecondsMax: TimeInterval = 60

    @Published public private(set) var status: RecordingStatus
    @Published public private(set) var currentRecordingDuration: TimeInterval
    @Published public private(set) var micStatus: CaptureStatus
    @Published public private(set) var systemAudioStatus: CaptureStatus
    @Published public private(set) var microphoneLevel: Float
    @Published public private(set) var systemAudioLevel: Float
    @Published public private(set) var errorMessage: String?
    @Published public private(set) var postCallDraft: PostCallDraft?
    @Published public private(set) var mixedPreviewPath: String?
    @Published public var isPostCallPanelPresented: Bool
    @Published public private(set) var recordings: [RecordingSummary]
    @Published public private(set) var recoverableRecordings: [RecoverableRecordingSummary]
    @Published public private(set) var lastRecording: LastRecordingSummary?
    @Published public private(set) var activeMarkers: [RecordingMarker]
    @Published public private(set) var selectedTagFilter: String?
    @Published public private(set) var recordingFilters: RecordingListFilters
    @Published public private(set) var recordingSettings: RecordingSettings
    @Published public private(set) var autoStartSettings: AutoStartSettings
    @Published public private(set) var storageSettings: StorageSettings
    @Published public private(set) var hotkeySettings: HotkeySettings
    @Published public private(set) var privacySettings: PrivacySettings
    @Published public private(set) var autoStartLastDecision: String
    @Published public private(set) var pendingAutoStartPrompt: PendingAutoStartPrompt?
    @Published public private(set) var outputFolderURL: URL
    @Published public private(set) var availableMicrophoneDevices: [MicrophoneInputDevice]
    @Published public private(set) var selectedMicrophoneName: String
    @Published public private(set) var recommendedMicrophoneName: String
    @Published public private(set) var microphoneInputWarning: String?
    @Published public private(set) var microphoneSelectionReason: String
    @Published public private(set) var permissionSnapshot: RecorderPermissionSnapshot
    @Published public private(set) var permissionOnboardingMessage: String?
    @Published public private(set) var isPermissionOnboardingInProgress: Bool
    @Published public private(set) var isSystemAudioPermissionRequestInProgress: Bool
    @Published public private(set) var audioReprocessProgress: AudioReprocessProgress?
    @Published public private(set) var audioReprocessLastSummary: AudioReprocessBatchSummary?
    @Published public private(set) var launchAtLoginLastErrorMessage: String?
    @Published public private(set) var isStoppingRecording: Bool
    @Published public private(set) var currentSessionFolderURL: URL?

    private let recordingController: RecordingController
    private let permissionChecker: RecordingPermissionChecking
    private let preflightChecker: RecordingPreflightChecking
    private let microphoneDeviceProvider: () -> [MicrophoneInputDevice]
    private var recordingStore: FileSystemRecordingStore
    private let activeApplicationDetector: ActiveApplicationDetecting
    private let runningApplicationDetector: RunningApplicationDetecting
    private let audioActivityDetector: AudioActivityDetecting
    private var recordingStartedAt: Date?
    private var durationTask: Task<Void, Never>?
    private var autoStartTask: Task<Void, Never>?
    private var microphoneDeviceTask: Task<Void, Never>?
    private var permissionOnboardingFeedbackTask: Task<Void, Never>?
    private var autoStartEngine: AutoStartEngine
    private var lastRecordingStoppedAt: Date?
    private var currentRecordingSource: RecordingSource?
    private var autoStopSignalLostAt: Date?
    private var lastAutoStartDecisionLogKey: String?
    private var lastLoggedSelectedMicrophoneName: String?
    private var screenSystemAudioSettingsOpened = false
    private var systemAudioPermissionProbeSucceeded = false
    private var systemAudioPermissionVerifiedThisRun = false

    public var outputFolderPath: String {
        outputFolderURL.path(percentEncoded: false)
    }

    public var formattedDuration: String {
        Self.formatDuration(currentRecordingDuration)
    }

    public var shouldShowPermissionsOnboarding: Bool {
        if isSystemAudioPermissionRequestInProgress
            && recordingSettings.systemAudioEnabled {
            return true
        }
        return RecordingPermissionDisplay.shouldShowOnboarding(
            permissionSnapshot,
            systemAudioEnabled: recordingSettings.systemAudioEnabled
        )
    }

    public var shouldShowPermissionChecklist: Bool {
        shouldShowPermissionsOnboarding
            || isPermissionOnboardingInProgress
            || isSystemAudioPermissionRequestInProgress
            || permissionOnboardingMessage != nil
    }

    public var isRecordingStartAllowed: Bool {
        guard !(isSystemAudioPermissionRequestInProgress
                && recordingSettings.systemAudioEnabled) else {
            return false
        }
        return status != .recording
            && !isStoppingRecording
            && selectedMicrophoneName != "No input device"
            && RecordingPermissionDisplay.canStartRecording(
                permissionSnapshot,
                systemAudioEnabled: recordingSettings.systemAudioEnabled
            )
    }

    public var recordingStartBlockingReason: String? {
        if selectedMicrophoneName == "No input device" {
            return microphoneSelectionReason
        }

        if isSystemAudioPermissionRequestInProgress
            && recordingSettings.systemAudioEnabled {
            return "Waiting for system audio permission. Click Allow on the macOS prompt."
        }

        return RecordingPermissionDisplay.blockingReason(
            permissionSnapshot,
            systemAudioEnabled: recordingSettings.systemAudioEnabled
        )
    }

    public var preferredScreenshotFolderURL: URL? {
        currentSessionFolderURL ?? lastRecording?.sessionFolderURL
    }

    public init(
        recordingController: RecordingController? = nil,
        outputFolderURL: URL? = nil,
        activeApplicationDetector: ActiveApplicationDetecting? = nil,
        runningApplicationDetector: RunningApplicationDetecting? = nil,
        audioActivityDetector: AudioActivityDetecting? = nil,
        permissionChecker: RecordingPermissionChecking? = nil,
        microphoneDeviceProvider: @escaping () -> [MicrophoneInputDevice] = MicrophoneDeviceProvider.availableInputDevices,
        preflightChecker: RecordingPreflightChecking? = nil,
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

        let availableMicrophoneDevices = microphoneDeviceProvider()
        resolvedSettings.recording.microphoneDeviceID = Self.allowedPreferredMicrophoneDeviceID(
            resolvedSettings.recording.microphoneDeviceID,
            devices: availableMicrophoneDevices
        )

        self.recordingController = recordingController ?? MacOSAudioRecordingController()
        self.permissionChecker = permissionChecker ?? SystemRecordingPermissionChecker()
        self.preflightChecker = preflightChecker ?? DefaultRecordingPreflightChecker()
        self.outputFolderURL = resolvedSettings.storage.rootFolderURL
        self.activeApplicationDetector = activeApplicationDetector ?? WorkspaceActiveApplicationDetector()
        self.runningApplicationDetector = runningApplicationDetector ?? WorkspaceRunningApplicationDetector()
        self.audioActivityDetector = audioActivityDetector ?? CoreAudioActivityDetector()
        self.microphoneDeviceProvider = microphoneDeviceProvider
        self.status = .idle
        self.currentRecordingDuration = 0
        self.micStatus = .idle
        self.systemAudioStatus = .idle
        self.microphoneLevel = 0
        self.systemAudioLevel = 0
        self.errorMessage = nil
        self.postCallDraft = nil
        self.mixedPreviewPath = nil
        self.isPostCallPanelPresented = false
        self.recordings = []
        self.recoverableRecordings = []
        self.lastRecording = nil
        self.activeMarkers = []
        self.selectedTagFilter = nil
        self.recordingFilters = RecordingListFilters()
        self.recordingSettings = resolvedSettings.recording
        self.autoStartSettings = resolvedSettings.autoStart
        self.storageSettings = resolvedSettings.storage
        self.hotkeySettings = resolvedSettings.hotkeys
        self.privacySettings = resolvedSettings.privacy
        self.autoStartLastDecision = "not_checked"
        self.pendingAutoStartPrompt = nil
        self.availableMicrophoneDevices = availableMicrophoneDevices
        let recommendedMicrophoneSelection = Self.resolveMicrophoneSelection(
            devices: availableMicrophoneDevices,
            preferredDeviceID: nil
        )
        let microphoneSelection = Self.resolveMicrophoneSelection(
            devices: availableMicrophoneDevices,
            preferredDeviceID: resolvedSettings.recording.microphoneDeviceID
        )
        self.recommendedMicrophoneName = recommendedMicrophoneSelection?.device.name ?? "No input device"
        self.selectedMicrophoneName = microphoneSelection?.device.name ?? "No input device"
        self.microphoneInputWarning = microphoneSelection?.warning
        self.microphoneSelectionReason = DevicePriorityResolver.selectionReason(
            devices: availableMicrophoneDevices,
            selection: microphoneSelection,
            preferredDeviceID: resolvedSettings.recording.microphoneDeviceID
        )
        self.permissionSnapshot = .unknown
        self.permissionOnboardingMessage = nil
        self.isPermissionOnboardingInProgress = false
        self.isSystemAudioPermissionRequestInProgress = false
        self.audioReprocessProgress = nil
        self.audioReprocessLastSummary = nil
        self.launchAtLoginLastErrorMessage = nil
        self.isStoppingRecording = false
        self.currentSessionFolderURL = nil
        self.autoStartEngine = AutoStartEngine()
        self.recordingStore = FileSystemRecordingStore(rootURL: resolvedSettings.storage.rootFolderURL)
        UserDefaults.standard.removeObject(forKey: Self.legacySystemAudioPermissionProbeSucceededKey)
        self.systemAudioPermissionProbeSucceeded = UserDefaults.standard.bool(
            forKey: Self.systemAudioPermissionProbeSucceededKey
        )
        AppLogger.configureFileLogging(rootURL: resolvedSettings.storage.rootFolderURL)
        refreshPermissionSnapshot()
        reloadRecordingsSilently()
        reloadLastRecordingSilently()
        reloadRecoverableRecordingsSilently()
        logSelectedMicrophoneIfNeeded()
    }

    deinit {
        durationTask?.cancel()
        autoStartTask?.cancel()
        microphoneDeviceTask?.cancel()
        permissionOnboardingFeedbackTask?.cancel()
    }

    public func startRecording() async throws {
        try await startRecording(
            source: RecordingSource(
                appName: "Recny",
                bundleID: "com.torbit.recorder",
                trigger: "manual",
                ruleID: "manual.audio"
            )
        )
    }

    public func startRecording(source: RecordingSource) async throws {
        guard status != .recording, !isStoppingRecording else {
            throw RecordingControllerError.alreadyRecording
        }

        do {
            refreshMicrophoneDevices()
            refreshPermissionSnapshot()

            try preflightChecker.validate(recordingPreflightContext())

            let update = try await recordingController.startRecording(
                outputFolder: outputFolderURL,
                source: source,
                settings: recordingRuntimeSettings()
            )
            apply(update)
            recordingStartedAt = update.startedAt ?? Date()
            currentRecordingSource = source
            autoStopSignalLostAt = nil
            currentRecordingDuration = 0
            activeMarkers = []
            mixedPreviewPath = nil
            errorMessage = nil
            startDurationClock()
            AppLogger.recording.info("Recording state changed to recording. trigger=\(source.trigger, privacy: .public), app=\(source.appName, privacy: .public), bundle_id=\(source.bundleID, privacy: .public), rule_id=\(source.ruleID, privacy: .public)")
            AppLogger.file(.info, category: "recording", "recording start trigger=\(source.trigger) app=\(source.appName) bundle_id=\(source.bundleID) rule_id=\(source.ruleID) output_root=\(outputFolderPath) selected_mic=\(selectedMicrophoneName)")
        } catch let error as RecordingControllerError {
            currentRecordingSource = nil
            autoStopSignalLostAt = nil
            applyError(error)
            if case .preflightFailed(let message) = error {
                AppLogger.recording.error("Recording preflight failed before session creation: \(message, privacy: .public)")
                AppLogger.file(.error, category: "preflight", "recording preflight failed message=\(message)")
            } else {
                AppLogger.recording.error("Failed to start recording: \(String(describing: error), privacy: .public)")
                AppLogger.file(.error, category: "recording", "recording failure during start error=\(String(describing: error))")
            }
            throw error
        } catch {
            currentRecordingSource = nil
            autoStopSignalLostAt = nil
            applyError(error)
            AppLogger.recording.error("Failed to start recording: \(String(describing: error), privacy: .public)")
            AppLogger.file(.error, category: "recording", "recording failure during start error=\(String(describing: error))")
            throw error
        }
    }

    public func stopRecording() async throws {
        guard status == .recording else {
            throw RecordingControllerError.notRecording
        }

        guard !isStoppingRecording else {
            AppLogger.file(.info, category: "recording", "ignored duplicate stop request")
            return
        }

        isStoppingRecording = true
        let stopRequestedAt = Date()
        AppLogger.recording.info("Recording stop requested")
        AppLogger.file(
            .info,
            category: "recording",
            "recording stop requested elapsed_seconds=\(Int(currentRecordingDuration.rounded(.down)))"
        )

        defer {
            let elapsed = Date().timeIntervalSince(stopRequestedAt)
            AppLogger.file(.info, category: "recording", "recording stop request finished elapsed_ms=\(Int((elapsed * 1000).rounded()))")
            isStoppingRecording = false
        }

        do {
            let update = try await recordingController.stopRecording()
            apply(update)
            stopDurationClock()

            guard let draft = update.postCallDraft else {
                throw RecordingControllerError.notRecording
            }

            postCallDraft = draft
            if !activeMarkers.isEmpty {
                try recordingStore.appendMarkers(activeMarkers, to: draft)
                AppLogger.recording.info("Saved \(self.activeMarkers.count, privacy: .public) recording markers for \(draft.id, privacy: .public)")
                AppLogger.file(.info, category: "recording", "saved recording markers id=\(draft.id) count=\(activeMarkers.count)")
                activeMarkers = []
            }
            mixedPreviewPath = mixedPreviewPath(for: draft)
            isPostCallPanelPresented = false
            currentRecordingSource = nil
            autoStopSignalLostAt = nil
            lastRecordingStoppedAt = Date()
            try reloadRecordings()
            try reloadLastRecording()
            try reloadRecoverableRecordings()
            errorMessage = nil
            if draft.status == .shortRecording {
                AppLogger.recording.info("Recording stopped as short_recording; post-call tagging skipped for \(draft.id, privacy: .public)")
            } else {
                AppLogger.recording.info("Recording stopped; tagging is available from Library for \(draft.id, privacy: .public)")
            }
            AppLogger.file(.info, category: "recording", "recording stop id=\(draft.id) status=\(draft.status.rawValue) folder=\(draft.sessionFolderURL.path(percentEncoded: false)) mixed=\(mixedPreviewPath ?? "missing")")
        } catch {
            currentRecordingSource = nil
            autoStopSignalLostAt = nil
            applyError(error)
            AppLogger.recording.error("Failed to stop recording: \(String(describing: error), privacy: .public)")
            AppLogger.file(.error, category: "recording", "recording failure during stop error=\(String(describing: error))")
            throw error
        }
    }

    @discardableResult
    public func addMarker(_ kind: RecordingMarkerKind, createdAt: Date = Date()) -> RecordingMarker? {
        guard status == .recording else {
            AppLogger.file(.info, category: "recording", "ignored marker label=\(kind.label) reason=not_recording")
            return nil
        }

        let elapsedTime = recordingStartedAt.map { createdAt.timeIntervalSince($0) } ?? currentRecordingDuration
        let marker = RecordingMarker.make(
            kind: kind,
            elapsedTime: elapsedTime,
            createdAt: createdAt
        )
        activeMarkers.append(marker)
        AppLogger.recording.info("Added recording marker label=\(kind.label, privacy: .public) time_sec=\(marker.timeSec, privacy: .public)")
        AppLogger.file(.info, category: "recording", "marker added label=\(kind.label) time_sec=\(Int(marker.timeSec))")
        return marker
    }

    public func savePostCallDraft(_ draft: PostCallDraft) throws {
        try recordingStore.saveDraft(draft)
        postCallDraft = draft
        isPostCallPanelPresented = false
        try reloadRecordings()
        try reloadLastRecording()
        AppLogger.recording.info("Saved post-call tags for \(draft.id, privacy: .public)")
        AppLogger.file(.info, category: "recording", "saved post-call tags id=\(draft.id) status=\(draft.status.rawValue) tag_count=\(draft.tags.count)")
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

    public func reloadLastRecording() throws {
        lastRecording = try recordingStore.latestRecordingSummary()
    }

    public func updateRecording(_ recording: RecordingSummary, title: String, tags: [String]) throws {
        try recordingStore.updateRecording(id: recording.id, title: title, tags: tags)
        try reloadRecordings()
        try reloadLastRecording()
    }

    public func deleteLocalRecord(_ recording: RecordingSummary) throws {
        try recordingStore.deleteLocalRecord(recording)
        try reloadRecordings()
        try reloadLastRecording()
    }

    public func reprocessAudio(
        for recording: RecordingSummary,
        overwriteExisting: Bool
    ) async throws -> AudioReprocessResult {
        audioReprocessProgress = AudioReprocessProgress(
            completed: 0,
            total: 1,
            currentTitle: recording.title
        )
        defer {
            audioReprocessProgress = nil
        }

        let reprocessor = audioLevelingReprocessor()
        let result = try await reprocessor.reprocess(
            recording: recording,
            overwritePolicy: overwriteExisting ? .overwriteExisting : .skipExisting
        )
        audioReprocessLastSummary = AudioReprocessBatchSummary(results: [result])
        try reloadRecordings()
        try reloadLastRecording()
        return result
    }

    public func reprocessMissingBalancedAudio() async throws -> AudioReprocessBatchSummary {
        let allRecordings = try recordingStore.recordings(filters: RecordingListFilters())
        let candidates = allRecordings.filter {
            RecordingPlaybackResolver.nonEmptyFileSize(at: $0.balancedMixedAudioURL) == nil
        }
        let reprocessor = audioLevelingReprocessor()
        var results: [AudioReprocessResult] = []

        defer {
            audioReprocessProgress = nil
        }

        for (index, recording) in candidates.enumerated() {
            audioReprocessProgress = AudioReprocessProgress(
                completed: index,
                total: candidates.count,
                currentTitle: recording.title
            )
            do {
                let result = try await reprocessor.reprocess(
                    recording: recording,
                    overwritePolicy: .skipExisting
                )
                results.append(result)
            } catch {
                AppLogger.file(.warning, category: "recording", "audio reprocess batch item failed recording_id=\(recording.id) error=\(String(describing: error))")
                results.append(
                    AudioReprocessResult(
                        recordingID: recording.id,
                        title: recording.title,
                        status: .failed,
                        message: String(describing: error),
                        balancedAudioURL: recording.balancedMixedAudioURL,
                        analysisURL: recording.audioAnalysisURL
                    )
                )
            }
        }

        let summary = AudioReprocessBatchSummary(results: results)
        audioReprocessLastSummary = summary
        try reloadRecordings()
        try reloadLastRecording()
        return summary
    }

    public func setAutoStartEnabled(_ isEnabled: Bool) {
        updateAutoStartSettings { settings in
            settings.isEnabled = isEnabled
        }
    }

    public func setAutoStartMode(_ mode: AutoStartMode) {
        updateAutoStartSettings { settings in
            settings.mode = mode
        }
        if mode != .askFirst {
            pendingAutoStartPrompt = nil
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
                mode: settings.mode,
                whitelist: settings.whitelist,
                blacklist: settings.blacklist,
                cooldownSeconds: seconds,
                minDetectionDurationSeconds: settings.minDetectionDurationSeconds,
                shortRecordingThresholdSeconds: settings.shortRecordingThresholdSeconds,
                autoStopDelaySeconds: settings.autoStopDelaySeconds
            )
        }
    }

    public func setAutoStartMinDetectionDurationSeconds(_ seconds: TimeInterval) {
        updateAutoStartSettings { settings in
            settings = AutoStartSettings(
                mode: settings.mode,
                whitelist: settings.whitelist,
                blacklist: settings.blacklist,
                cooldownSeconds: settings.cooldownSeconds,
                minDetectionDurationSeconds: seconds,
                shortRecordingThresholdSeconds: settings.shortRecordingThresholdSeconds,
                autoStopDelaySeconds: settings.autoStopDelaySeconds
            )
        }
    }

    public func setShortRecordingThresholdSeconds(_ seconds: TimeInterval) {
        updateAutoStartSettings { settings in
            settings = AutoStartSettings(
                mode: settings.mode,
                whitelist: settings.whitelist,
                blacklist: settings.blacklist,
                cooldownSeconds: settings.cooldownSeconds,
                minDetectionDurationSeconds: settings.minDetectionDurationSeconds,
                shortRecordingThresholdSeconds: seconds,
                autoStopDelaySeconds: settings.autoStopDelaySeconds
            )
        }
    }

    public func setAutoStopDelaySeconds(_ seconds: TimeInterval) {
        updateAutoStartSettings { settings in
            settings = AutoStartSettings(
                mode: settings.mode,
                whitelist: settings.whitelist,
                blacklist: settings.blacklist,
                cooldownSeconds: settings.cooldownSeconds,
                minDetectionDurationSeconds: settings.minDetectionDurationSeconds,
                shortRecordingThresholdSeconds: settings.shortRecordingThresholdSeconds,
                autoStopDelaySeconds: AutoStartSettings.normalizeAutoStopDelay(seconds)
            )
        }
    }

    public func setSystemAudioEnabled(_ isEnabled: Bool) {
        recordingSettings.systemAudioEnabled = true
        refreshPermissionSnapshot()
        saveSettings()
    }

    public func setMixedPreviewEnabled(_ isEnabled: Bool) {
        recordingSettings.mixedPreviewEnabled = true
        saveSettings()
    }

    public func setAudioLevelingEnabled(_ isEnabled: Bool) {
        recordingSettings.audioLevelingEnabled = isEnabled
        saveSettings()
    }

    public func setAudioLevelingMode(_ mode: AudioLevelingMode) {
        guard mode.isImplemented else {
            return
        }

        recordingSettings.audioLevelingMode = mode
        saveSettings()
    }

    public func setAudioQualityPreset(_ preset: AudioQualityPreset) {
        recordingSettings.audioQualityPreset = preset
        saveSettings()
    }

    public func refreshMicrophoneDevices() {
        availableMicrophoneDevices = microphoneDeviceProvider()
        refreshSelectedMicrophone(allowSelectionChange: status != .recording)
    }

    public func refreshPermissionSnapshot() {
        var snapshot = permissionChecker.snapshot(
            outputFolderURL: outputFolderURL,
            screenSystemAudioSettingsOpened: screenSystemAudioSettingsOpened,
            lastErrorMessage: errorMessage
        )
        // While the system-audio permission request is in flight (macOS
        // prompt may still be on screen, or the post-prompt sample probe
        // has not finished), the snapshot MUST NOT report .granted. Real
        // audio frames have not yet been verified after a user choice.
        if isSystemAudioPermissionRequestInProgress {
            if snapshot.screenSystemAudio == .granted {
                snapshot.screenSystemAudio = .notDetermined
            }
        } else if (systemAudioPermissionVerifiedThisRun || systemAudioPermissionProbeSucceeded),
                  snapshot.screenSystemAudio != .denied,
                  snapshot.screenSystemAudio != .restartRequired {
            snapshot.screenSystemAudio = .granted
        }
        permissionSnapshot = snapshot
    }

    public func beginPermissionOnboarding(message: String) {
        permissionOnboardingFeedbackTask?.cancel()
        permissionOnboardingFeedbackTask = nil
        isPermissionOnboardingInProgress = true
        permissionOnboardingMessage = message
    }

    public func updatePermissionOnboardingMessage(_ message: String) {
        permissionOnboardingFeedbackTask?.cancel()
        permissionOnboardingFeedbackTask = nil
        permissionOnboardingMessage = message
    }

    public func completePermissionOnboarding(message: String, clearAfter delay: TimeInterval? = 4) {
        permissionOnboardingFeedbackTask?.cancel()
        permissionOnboardingFeedbackTask = nil
        isPermissionOnboardingInProgress = false
        permissionOnboardingMessage = message

        guard let delay else {
            return
        }

        let clearDelay = UInt64(max(0, delay) * 1_000_000_000)
        permissionOnboardingFeedbackTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: clearDelay)
            guard !Task.isCancelled,
                  self?.permissionOnboardingMessage == message else {
                return
            }
            self?.permissionOnboardingMessage = nil
            self?.permissionOnboardingFeedbackTask = nil
        }
    }

    public func clearPermissionOnboardingFeedback() {
        permissionOnboardingFeedbackTask?.cancel()
        permissionOnboardingFeedbackTask = nil
        isPermissionOnboardingInProgress = false
        permissionOnboardingMessage = nil
    }

    public func markScreenSystemAudioSettingsOpened() {
        screenSystemAudioSettingsOpened = true
        refreshPermissionSnapshot()
    }

    public func noteSystemAudioPermissionRequestStarted() {
        isSystemAudioPermissionRequestInProgress = true
        // Drop any stale verification flag so that the snapshot cannot
        // report .granted while the prompt is on screen.
        systemAudioPermissionVerifiedThisRun = false
        refreshPermissionSnapshot()
        AppLogger.file(.info, category: "permissions", "system audio permission request marked in-flight")
    }

    /// Drops cached "probe succeeded" flags (both in-run and persisted)
    /// for the explicit Diagnostics -> Force Recheck flow. The normal
    /// Fix Permissions path must not call this after a successful probe:
    /// macOS can otherwise show the same system-audio prompt again even
    /// when the user already granted the permission and restarted.
    public func invalidateSystemAudioPermissionCache() {
        systemAudioPermissionVerifiedThisRun = false
        systemAudioPermissionProbeSucceeded = false
        UserDefaults.standard.set(false, forKey: Self.systemAudioPermissionProbeSucceededKey)
        refreshPermissionSnapshot()
        AppLogger.file(.info, category: "permissions", "system audio permission cache invalidated for re-verification")
    }

    public func noteSystemAudioPermissionRequestSucceeded() {
        isSystemAudioPermissionRequestInProgress = false
        setSystemAudioPermissionProbeSucceeded(true)
        if let errorMessage,
           errorMessage.localizedCaseInsensitiveContains("system audio") {
            self.errorMessage = nil
        }
        if status == .error {
            status = .idle
        }
        systemAudioStatus = .idle
        refreshPermissionSnapshot()
    }

    public func noteSystemAudioPermissionRequestFailed(_ error: Error) {
        isSystemAudioPermissionRequestInProgress = false
        setSystemAudioPermissionProbeSucceeded(false)
        errorMessage = String(describing: error)
        systemAudioStatus = .permissionDenied
        refreshPermissionSnapshot()
    }

    /// Test-only entry point: forces the recording status into `.error` with
    /// a preflight-style message, simulating a previous failed start.
    internal func applyTestErrorForPreflight() {
        applyError(RecordingControllerError.preflightFailed("Microphone access is required before recording."))
    }

    /// Drops a previous `.error` recording status when current permissions
    /// are no longer blocking. Called after a successful permission
    /// onboarding flow so the UI exits the `Recording failed` panel.
    public func clearRecordingErrorIfPermissionsResolved() {
        guard status == .error else {
            return
        }
        // Use the same gating logic as the Start Recording button — if
        // nothing is blocking now, the previous error is stale.
        let reason = RecordingPermissionDisplay.blockingReason(
            permissionSnapshot,
            systemAudioEnabled: recordingSettings.systemAudioEnabled
        )
        guard reason == nil,
              selectedMicrophoneName != "No input device",
              !(isSystemAudioPermissionRequestInProgress
                && recordingSettings.systemAudioEnabled)
        else {
            return
        }

        if let message = errorMessage,
           message.localizedCaseInsensitiveContains("microphone")
            || message.localizedCaseInsensitiveContains("system audio")
            || message.localizedCaseInsensitiveContains("preflight")
            || message.localizedCaseInsensitiveContains("permission") {
            errorMessage = nil
        }
        status = .idle
        micStatus = .idle
        systemAudioStatus = .idle
        AppLogger.file(.info, category: "permissions", "cleared recording error after permissions resolved")
    }

    public func setPreferredMicrophoneDeviceID(_ deviceID: String?) {
        let normalizedDeviceID = deviceID?.isEmpty == true ? nil : deviceID
        if let normalizedDeviceID,
           let device = availableMicrophoneDevices.first(where: { $0.id == normalizedDeviceID }),
           DevicePriorityResolver.isBlockedInput(device) {
            recordingSettings.microphoneDeviceID = nil
        } else {
            recordingSettings.microphoneDeviceID = normalizedDeviceID
        }
        refreshSelectedMicrophone(allowSelectionChange: status != .recording)
        saveSettings()
    }

    public func microphoneDeviceLabel(for device: MicrophoneInputDevice) -> String {
        let recommendedDeviceID = Self.resolveMicrophoneSelection(
            devices: availableMicrophoneDevices,
            preferredDeviceID: nil
        )?.device.id
        return DevicePriorityResolver.displayLabel(
            for: device,
            recommendedDeviceID: recommendedDeviceID
        )
    }

    public func resetStorageRootToDefault() {
        setStorageRoot(RecordingPaths.defaultRoot)
    }

    public func setShowRecordingIndicator(_ isEnabled: Bool) {
        privacySettings.showRecordingIndicator = isEnabled
        saveSettings()
    }

    public func setShowDockIcon(_ isEnabled: Bool) {
        privacySettings.showDockIcon = isEnabled
        saveSettings()
    }

    public func setLaunchAtLoginPreference(_ isEnabled: Bool, errorMessage: String? = nil) {
        privacySettings.launchAtLogin = isEnabled
        launchAtLoginLastErrorMessage = errorMessage
        saveSettings()
    }

    public func setStorageRoot(_ url: URL) {
        outputFolderURL = url
        storageSettings.rootFolderPath = url.path(percentEncoded: false)
        recordingStore = FileSystemRecordingStore(rootURL: url)
        AppLogger.configureFileLogging(rootURL: url)
        refreshPermissionSnapshot()
        reloadRecordingsSilently()
        reloadLastRecordingSilently()
        reloadRecoverableRecordingsSilently()
        saveSettings()
    }

    public func startAutoStartMonitoring(
        pollIntervalSeconds: TimeInterval = AppState.defaultAutoStartMonitoringPollIntervalSeconds
    ) {
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

    public func startMicrophoneDeviceMonitoring(pollIntervalSeconds: TimeInterval = 5) {
        guard microphoneDeviceTask == nil else {
            return
        }

        let interval = UInt64(max(1, pollIntervalSeconds) * 1_000_000_000)
        microphoneDeviceTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                guard let self else {
                    return
                }

                self.refreshMicrophoneDevices()

                do {
                    try await Task.sleep(nanoseconds: interval)
                } catch {
                    return
                }
            }
        }
    }

    public func stopMicrophoneDeviceMonitoring() {
        microphoneDeviceTask?.cancel()
        microphoneDeviceTask = nil
    }

    public func evaluateAutoStartNow(now: Date = Date()) async {
        await evaluateAutoStart(
            activeApplication: activeApplicationDetector.activeApplication(),
            runningApplications: runningApplicationDetector.runningApplications(),
            audioActivity: audioActivityDetector.audioActivity(),
            now: now
        )
    }

    public func evaluateAutoStart(
        activeApplication: ActiveApplicationSnapshot?,
        runningApplications: [ActiveApplicationSnapshot] = [],
        audioActivity: AudioActivitySnapshot,
        now: Date
    ) async {
        if status == .recording {
            await evaluateAutoStop(
                activeApplication: activeApplication,
                runningApplications: runningApplications,
                audioActivity: audioActivity,
                now: now
            )
            return
        }

        let decision = autoStartEngine.evaluate(
            AutoStartEvaluationContext(
                activeApplication: activeApplication,
                runningApplications: runningApplications,
                audioActivity: audioActivity,
                isAlreadyRecording: status == .recording,
                lastStoppedAt: lastRecordingStoppedAt,
                now: now
            ),
            settings: autoStartSettings
        )

        applyAutoStartDecision(
            decision,
            activeApplication: activeApplication,
            audioActivity: audioActivity,
            now: now
        )

        if decision.action == .ask, let source = decision.recordingSource {
            pendingAutoStartPrompt = PendingAutoStartPrompt(
                source: source,
                message: decision.message,
                confidence: decision.confidence,
                detectedAt: now
            )
            return
        }

        if decision.action != .wait {
            pendingAutoStartPrompt = nil
        }

        guard decision.action == .start, let source = decision.recordingSource else {
            return
        }

        do {
            try await startRecording(source: source)
        } catch {
            applyError(error)
            AppLogger.recording.error("Auto-start failed: reason=\(decision.reason.rawValue, privacy: .public), confidence=\(decision.confidence, privacy: .public), app=\(source.appName, privacy: .public), bundle_id=\(source.bundleID, privacy: .public), error=\(String(describing: error), privacy: .public)")
            AppLogger.file(.error, category: "autostart", "auto-start failed reason=\(decision.reason.rawValue) confidence=\(decision.confidence) app=\(source.appName) bundle_id=\(source.bundleID) error=\(String(describing: error))")
        }
    }

    public func confirmPendingAutoStart() async throws {
        guard let prompt = pendingAutoStartPrompt else {
            return
        }

        pendingAutoStartPrompt = nil

        do {
            try await startRecording(source: prompt.source)
        } catch {
            applyError(error)
            AppLogger.recording.error("Ask-first auto-start failed: app=\(prompt.source.appName, privacy: .public), bundle_id=\(prompt.source.bundleID, privacy: .public), error=\(String(describing: error), privacy: .public)")
            AppLogger.file(.error, category: "autostart", "ask-first start failed app=\(prompt.source.appName) bundle_id=\(prompt.source.bundleID) error=\(String(describing: error))")
            throw error
        }
    }

    public func ignorePendingAutoStart(now: Date = Date()) {
        guard let prompt = pendingAutoStartPrompt else {
            return
        }

        pendingAutoStartPrompt = nil
        lastRecordingStoppedAt = now
        AppLogger.file(.info, category: "autostart", "ask-first ignored app=\(prompt.source.appName) bundle_id=\(prompt.source.bundleID) confidence=\(prompt.confidence)")
    }

    private func evaluateAutoStop(
        activeApplication: ActiveApplicationSnapshot?,
        runningApplications: [ActiveApplicationSnapshot],
        audioActivity: AudioActivitySnapshot,
        now: Date
    ) async {
        guard let source = currentRecordingSource,
              source.trigger == "autostart"
        else {
            return
        }

        let zoomTitles = (([activeApplication].compactMap { $0 } + runningApplications))
            .filter(isZoomApplication)
            .compactMap { $0.windowTitle }
            .joined(separator: "|")
        let zoomProcessAudioState = zoomProcessAudioLogState(audioActivity)
        if autoStartedCallStillLooksActive(
            source: source,
            activeApplication: activeApplication,
            runningApplications: runningApplications,
            audioActivity: audioActivity
        ) {
            if autoStopSignalLostAt != nil {
                AppLogger.file(
                    .info,
                    category: "autostart",
                    "auto-stop cancelled signal_restored active_app=\(activeApplication?.name ?? "none") mic_active=\(audioActivity.microphoneActive) system_active=\(audioActivity.systemAudioActive) zoom_process_audio=\(zoomProcessAudioState) zoom_titles=\(zoomTitles.isEmpty ? "<none>" : zoomTitles)"
                )
            }
            autoStopSignalLostAt = nil
            return
        }

        // Live delay from settings; clamped defensively in case future
        // migrations write something out of range.
        let configuredGrace = min(
            Self.autoStopSignalLostGracePeriodSecondsMax,
            max(0, autoStartSettings.autoStopDelaySeconds)
        )
        if autoStopSignalLostAt == nil {
            autoStopSignalLostAt = now
            AppLogger.file(
                .info,
                category: "autostart",
                "auto-stop waiting signal_lost grace_seconds=\(Int(configuredGrace)) active_app=\(activeApplication?.name ?? "none") source_app=\(source.appName) mic_active=\(audioActivity.microphoneActive) system_active=\(audioActivity.systemAudioActive) zoom_process_audio=\(zoomProcessAudioState) zoom_titles=\(zoomTitles.isEmpty ? "<none>" : zoomTitles)"
            )
            return
        }

        let signalLostAt = autoStopSignalLostAt ?? now
        let elapsed = now.timeIntervalSince(signalLostAt)
        guard elapsed >= configuredGrace else {
            return
        }

        do {
            AppLogger.file(
                .info,
                category: "autostart",
                "auto-stop recording signal_lost_elapsed=\(Int(elapsed.rounded(.down))) source_app=\(source.appName)"
            )
            try await stopRecording()
        } catch {
            applyError(error)
            AppLogger.recording.error("Auto-stop failed: \(String(describing: error), privacy: .public)")
            AppLogger.file(.error, category: "autostart", "auto-stop failed error=\(String(describing: error))")
        }
    }

    private func autoStartedCallStillLooksActive(
        source: RecordingSource,
        activeApplication: ActiveApplicationSnapshot?,
        runningApplications: [ActiveApplicationSnapshot],
        audioActivity: AudioActivitySnapshot
    ) -> Bool {
        if isZoomRecordingSource(source) {
            let zoomSnapshots = ([activeApplication].compactMap { $0 } + runningApplications)
                .filter(isZoomApplication)

            guard !zoomSnapshots.isEmpty else {
                return false
            }

            if let zoomMeetingWindowIsActive = zoomMeetingWindowLooksActive(zoomSnapshots) {
                if zoomMeetingWindowIsActive {
                    return true
                }

                if let zoomProcessAudioIsActive = zoomProcessAudioLooksActive(audioActivity) {
                    return zoomProcessAudioIsActive
                }

                return false
            }

            if let zoomProcessAudioIsActive = zoomProcessAudioLooksActive(audioActivity) {
                return zoomProcessAudioIsActive
            }

            // Window titles are unavailable and Core Audio process activity is
            // unavailable. In this fallback mode, microphone activity is not
            // reliable because the recorder itself may keep input devices
            // marked as running; use global system-audio activity as the
            // remaining call signal.
            return audioActivity.systemAudioActive
        }

        if isTeamsRecordingSource(source) {
            let teamsSnapshots = ([activeApplication].compactMap { $0 } + runningApplications)
                .filter(isTeamsApplication)

            guard !teamsSnapshots.isEmpty else {
                return false
            }

            if let teamsMeetingWindowIsActive = meetingWindowLooksActive(teamsSnapshots) {
                if teamsMeetingWindowIsActive {
                    return true
                }

                if let teamsProcessAudioIsActive = teamsProcessAudioLooksActive(audioActivity) {
                    return teamsProcessAudioIsActive
                }

                return false
            }

            if let teamsProcessAudioIsActive = teamsProcessAudioLooksActive(audioActivity) {
                return teamsProcessAudioIsActive
            }

            return audioActivity.microphoneActive || audioActivity.systemAudioActive
        }

        if isTelemostRecordingSource(source) {
            let telemostSnapshots = ([activeApplication].compactMap { $0 } + runningApplications)
                .filter(isTelemostApplication)

            guard !telemostSnapshots.isEmpty else {
                return false
            }

            if let telemostMeetingWindowIsActive = meetingWindowLooksActive(telemostSnapshots) {
                if telemostMeetingWindowIsActive {
                    return true
                }

                if let telemostProcessAudioIsActive = telemostProcessAudioLooksActive(audioActivity) {
                    return telemostProcessAudioIsActive
                }

                return false
            }

            if let telemostProcessAudioIsActive = telemostProcessAudioLooksActive(audioActivity) {
                return telemostProcessAudioIsActive
            }

            return false
        }

        if isGenericKnownCallRecordingSource(source) {
            return genericKnownCallProcessAudioLooksActive(source: source, audioActivity: audioActivity) ?? false
        }

        return audioActivity.microphoneActive || audioActivity.systemAudioActive
    }

    private func zoomProcessAudioLooksActive(_ audioActivity: AudioActivitySnapshot) -> Bool? {
        guard audioActivity.processActivityAvailable else {
            return nil
        }

        return audioActivity.processActivities.contains { activity in
            isZoomToken(activity.bundleID) && activity.isRunningAudio
        }
    }

    private func teamsProcessAudioLooksActive(_ audioActivity: AudioActivitySnapshot) -> Bool? {
        guard audioActivity.processActivityAvailable else {
            return nil
        }

        return audioActivity.processActivities.contains { activity in
            isTeamsToken(activity.bundleID) && activity.isRunningAudio
        }
    }

    private func telemostProcessAudioLooksActive(_ audioActivity: AudioActivitySnapshot) -> Bool? {
        guard audioActivity.processActivityAvailable else {
            return nil
        }

        return audioActivity.processActivities.contains { activity in
            isTelemostToken(activity.bundleID) && activity.isRunningInput
        }
    }

    private func genericKnownCallProcessAudioLooksActive(
        source: RecordingSource,
        audioActivity: AudioActivitySnapshot
    ) -> Bool? {
        guard audioActivity.processActivityAvailable else {
            return nil
        }

        return audioActivity.processActivities.contains { activity in
            genericKnownCallBundleID(activity.bundleID, matches: source)
                && activity.isRunningInput
                && activity.isRunningOutput
        }
    }

    private func zoomProcessAudioLogState(_ audioActivity: AudioActivitySnapshot) -> String {
        guard audioActivity.processActivityAvailable else {
            return "unavailable"
        }

        let zoomActivities = audioActivity.processActivities.filter { isZoomToken($0.bundleID) }
        guard !zoomActivities.isEmpty else {
            return "missing"
        }

        if zoomActivities.contains(where: \.isRunningAudio) {
            return "active"
        }

        return "idle"
    }

    private func isZoomRecordingSource(_ source: RecordingSource) -> Bool {
        isZoomToken(source.appName) || isZoomToken(source.bundleID)
    }

    private func isTeamsRecordingSource(_ source: RecordingSource) -> Bool {
        isTeamsToken(source.appName) || isTeamsToken(source.bundleID)
    }

    private func isTelemostRecordingSource(_ source: RecordingSource) -> Bool {
        isTelemostToken(source.appName) || isTelemostToken(source.bundleID)
    }

    private func isGenericKnownCallRecordingSource(_ source: RecordingSource) -> Bool {
        isTelegramToken(source.appName)
            || isTelegramToken(source.bundleID)
            || isDiscordToken(source.appName)
            || isDiscordToken(source.bundleID)
    }

    private func isZoomApplication(_ application: ActiveApplicationSnapshot) -> Bool {
        isZoomToken(application.name) || isZoomToken(application.bundleID)
    }

    private func isTeamsApplication(_ application: ActiveApplicationSnapshot) -> Bool {
        isTeamsToken(application.name) || isTeamsToken(application.bundleID)
    }

    private func isTelemostApplication(_ application: ActiveApplicationSnapshot) -> Bool {
        isTelemostToken(application.name) || isTelemostToken(application.bundleID)
    }

    private func isZoomToken(_ value: String) -> Bool {
        let normalizedValue = value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        return normalizedValue == "zoom"
            || normalizedValue == "zoom.us"
            || normalizedValue == "us.zoom.xos"
            || normalizedValue.hasPrefix("us.zoom.")
            || normalizedValue.contains(".zoom.")
            || normalizedValue.contains("zoom workplace")
    }

    private func isTeamsToken(_ value: String) -> Bool {
        let normalizedValue = value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        return normalizedValue == "microsoft teams"
            || normalizedValue == "teams"
            || normalizedValue == "com.microsoft.teams"
            || normalizedValue == "com.microsoft.teams2"
            || normalizedValue.hasPrefix("com.microsoft.teams")
    }

    private func isTelemostToken(_ value: String) -> Bool {
        let normalizedValue = value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        return normalizedValue == "yandex telemost"
            || normalizedValue == "telemost"
            || normalizedValue == "яндекс телемост"
            || normalizedValue == "телемост"
            || normalizedValue == "ru.yandex.desktop.telemost"
            || normalizedValue.contains("telemost")
    }

    private func genericKnownCallBundleID(_ bundleID: String, matches source: RecordingSource) -> Bool {
        if isTelegramToken(source.appName) || isTelegramToken(source.bundleID) {
            return isTelegramToken(bundleID)
        }

        if isDiscordToken(source.appName) || isDiscordToken(source.bundleID) {
            return isDiscordToken(bundleID)
        }

        return false
    }

    private func isTelegramToken(_ value: String) -> Bool {
        let normalizedValue = value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        return normalizedValue == "telegram"
            || normalizedValue == "ru.keepcoder.telegram"
            || normalizedValue == "org.telegram.desktop"
            || normalizedValue.contains("telegram")
    }

    private func isDiscordToken(_ value: String) -> Bool {
        let normalizedValue = value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        return normalizedValue == "discord"
            || normalizedValue == "com.hnc.discord"
            || normalizedValue.contains("discord")
    }

    private func zoomMeetingWindowLooksActive(_ applications: [ActiveApplicationSnapshot]) -> Bool? {
        meetingWindowLooksActive(applications)
    }

    private func meetingWindowLooksActive(_ applications: [ActiveApplicationSnapshot]) -> Bool? {
        let titles = applications
            .compactMap(\.windowTitle)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        guard !titles.isEmpty else {
            return nil
        }

        return titles.contains { title in
            let normalizedTitle = title.lowercased()
            return normalizedTitle.contains("meeting")
                || normalizedTitle.contains("conference")
                || normalizedTitle.contains("конференц")
                || normalizedTitle.contains("встреч")
                || normalizedTitle.contains("waiting room")
                || normalizedTitle.contains("зал ожидания")
                || normalizedTitle.contains("participants")
                || normalizedTitle.contains("участник")
                || normalizedTitle.contains("share screen")
                || normalizedTitle.contains("поделиться")
        }
    }

    public func reloadRecoverableRecordings() throws {
        guard status != .recording else {
            return
        }

        recoverableRecordings = try recordingStore.recoverableSessions()
    }

    @discardableResult
    public func clearEmptyRecoverableRecordings() throws -> Int {
        let removed = try recordingStore.clearEmptyRecoverableSessions()
        try reloadRecoverableRecordings()
        AppLogger.storage.info("Cleared \(removed, privacy: .public) empty recoverable recording folders")
        AppLogger.file(.info, category: "storage", "cleared empty recoverables count=\(removed)")
        return removed
    }

    public func recoverRecording(_ summary: RecoverableRecordingSummary) async throws {
        do {
            let draft = try await RecordingRecoveryController(store: recordingStore).recover(summary)
            postCallDraft = draft
            mixedPreviewPath = mixedPreviewPath(for: draft)
            isPostCallPanelPresented = false
            try reloadRecordings()
            try reloadLastRecording()
            try reloadRecoverableRecordings()
            errorMessage = nil
            AppLogger.recording.info("Recovered interrupted recording \(summary.id, privacy: .public)")
            AppLogger.file(.info, category: "recording", "recovered recording id=\(summary.id) folder=\(summary.folderURL.path(percentEncoded: false))")
        } catch {
            applyError(error)
            AppLogger.recording.error("Failed to recover recording \(summary.id, privacy: .public): \(String(describing: error), privacy: .public)")
            AppLogger.file(.error, category: "recording", "failed to recover recording id=\(summary.id) error=\(String(describing: error))")
            throw error
        }
    }

    public func editLastRecordingTags() {
        guard let lastRecording else {
            return
        }

        do {
            postCallDraft = try draft(
                id: lastRecording.id,
                sessionFolderURL: lastRecording.sessionFolderURL,
                metadataURL: lastRecording.metadataURL
            )
            isPostCallPanelPresented = true
            errorMessage = nil
        } catch {
            applyError(error)
            AppLogger.storage.error("Failed to open last recording tags: \(String(describing: error), privacy: .public)")
            AppLogger.file(.error, category: "storage", "failed to open last recording tags error=\(String(describing: error))")
        }
    }

    public func draft(for recording: RecordingSummary) throws -> PostCallDraft {
        try draft(
            id: recording.id,
            sessionFolderURL: recording.sessionFolderURL,
            metadataURL: recording.metadataURL
        )
    }

    private func apply(_ update: RecordingControllerUpdate) {
        status = update.status
        micStatus = update.micStatus
        systemAudioStatus = update.systemAudioStatus
        if let session = update.session {
            currentSessionFolderURL = session.folderURL
        } else if update.status != .recording {
            currentSessionFolderURL = nil
        }

        if let duration = update.duration {
            currentRecordingDuration = duration
        }
    }

    private func applyAutoStartDecision(
        _ decision: AutoStartDecision,
        activeApplication: ActiveApplicationSnapshot?,
        audioActivity: AudioActivitySnapshot,
        now: Date
    ) {
        autoStartLastDecision = "\(decision.reason.rawValue): \(decision.message)"
        let logKey = "\(decision.action)-\(decision.reason)-\(decision.message)"
        guard decision.action == .start || logKey != lastAutoStartDecisionLogKey else {
            return
        }

        lastAutoStartDecisionLogKey = logKey
        let cooldownRemaining = lastRecordingStoppedAt.map {
            max(0, autoStartSettings.cooldownSeconds - now.timeIntervalSince($0))
        } ?? 0
        AppLogger.recording.info("Auto-start decision: action=\(String(describing: decision.action), privacy: .public), reason=\(decision.reason.rawValue, privacy: .public), confidence=\(decision.confidence, privacy: .public), active_app=\(activeApplication?.name ?? "none", privacy: .public), bundle_id=\(activeApplication?.bundleID ?? "", privacy: .public), mic_active=\(audioActivity.microphoneActive, privacy: .public), system_active=\(audioActivity.systemAudioActive, privacy: .public), cooldown_remaining=\(Int(cooldownRemaining.rounded(.up)), privacy: .public), message=\(decision.message, privacy: .public)")
        AppLogger.file(.info, category: "autostart", "decision action=\(decision.action) reason=\(decision.reason.rawValue) confidence=\(decision.confidence) active_app=\(activeApplication?.name ?? "none") bundle_id=\(activeApplication?.bundleID ?? "") mic_active=\(audioActivity.microphoneActive) system_active=\(audioActivity.systemAudioActive) cooldown_remaining=\(Int(cooldownRemaining.rounded(.up))) message=\(decision.message)")
    }

    private func applyError(_ error: Error) {
        status = .error
        micStatus = Self.captureStatus(for: error)
        systemAudioStatus = Self.systemAudioStatus(for: error)
        if Self.systemAudioStatus(for: error) == .permissionDenied {
            setSystemAudioPermissionProbeSucceeded(false)
        }
        microphoneLevel = 0
        systemAudioLevel = 0
        errorMessage = String(describing: error)
        refreshPermissionSnapshot()
        stopDurationClock()
    }

    private func setSystemAudioPermissionProbeSucceeded(_ isSucceeded: Bool) {
        systemAudioPermissionProbeSucceeded = isSucceeded
        systemAudioPermissionVerifiedThisRun = isSucceeded
        UserDefaults.standard.set(isSucceeded, forKey: Self.systemAudioPermissionProbeSucceededKey)
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
        case .preflightFailed:
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
        case .preflightFailed:
            return .idle
        default:
            return .error
        }
    }

    private func reloadRecordingsSilently() {
        do {
            try reloadRecordings()
        } catch {
            AppLogger.storage.error("Failed to reload recordings: \(String(describing: error), privacy: .public)")
            AppLogger.file(.error, category: "storage", "failed to reload recordings error=\(String(describing: error))")
        }
    }

    private func reloadLastRecordingSilently() {
        do {
            try reloadLastRecording()
        } catch {
            AppLogger.storage.error("Failed to reload last recording: \(String(describing: error), privacy: .public)")
            AppLogger.file(.error, category: "storage", "failed to reload last recording error=\(String(describing: error))")
        }
    }

    private func reloadRecoverableRecordingsSilently() {
        do {
            try reloadRecoverableRecordings()
        } catch {
            AppLogger.storage.error("Failed to reload recoverable recordings: \(String(describing: error), privacy: .public)")
            AppLogger.file(.error, category: "storage", "failed to reload recoverable recordings error=\(String(describing: error))")
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
            mode: settings.mode,
            whitelist: normalizedAppList(settings.whitelist),
            blacklist: normalizedAppList(settings.blacklist),
            cooldownSeconds: settings.cooldownSeconds,
            minDetectionDurationSeconds: settings.minDetectionDurationSeconds,
            shortRecordingThresholdSeconds: settings.shortRecordingThresholdSeconds,
            autoStopDelaySeconds: settings.autoStopDelaySeconds
        )
        autoStartEngine.resetCandidate()
        saveSettings()
    }

    private func recordingRuntimeSettings() -> RecordingRuntimeSettings {
        RecordingRuntimeSettings(
            audioQualityPreset: recordingSettings.audioQualityPreset,
            systemAudioEnabled: recordingSettings.systemAudioEnabled,
            mixedPreviewEnabled: recordingSettings.mixedPreviewEnabled,
            audioLevelingEnabled: recordingSettings.audioLevelingEnabled,
            audioLevelingMode: recordingSettings.audioLevelingMode,
            shortRecordingThresholdSeconds: autoStartSettings.shortRecordingThresholdSeconds,
            preferredMicrophoneDeviceID: Self.allowedPreferredMicrophoneDeviceID(
                recordingSettings.microphoneDeviceID,
                devices: availableMicrophoneDevices
            )
        )
    }

    private func recordingPreflightContext() -> RecordingPreflightContext {
        RecordingPreflightContext(
            permissionSnapshot: permissionSnapshot,
            systemAudioEnabled: recordingSettings.systemAudioEnabled,
            outputFolderURL: outputFolderURL,
            availableMicrophoneDevices: availableMicrophoneDevices,
            preferredMicrophoneDeviceID: Self.allowedPreferredMicrophoneDeviceID(
                recordingSettings.microphoneDeviceID,
                devices: availableMicrophoneDevices
            ),
            systemAudioCaptureAvailable: ScreenCaptureKitSystemAudioRecorder.isSystemAudioCaptureAvailable,
            isRecordingActive: status == .recording
        )
    }

    private func audioLevelingReprocessor() -> AudioLevelingReprocessor {
        AudioLevelingReprocessor(
            store: recordingStore,
            qualityPreset: recordingSettings.audioQualityPreset,
            mode: recordingSettings.audioLevelingMode
        )
    }

    private func refreshSelectedMicrophone(allowSelectionChange: Bool = true) {
        let recommendedSelection = Self.resolveMicrophoneSelection(
            devices: availableMicrophoneDevices,
            preferredDeviceID: nil
        )
        recommendedMicrophoneName = recommendedSelection?.device.name ?? "No input device"

        guard allowSelectionChange else {
            return
        }

        let previousPreferredMicrophoneDeviceID = recordingSettings.microphoneDeviceID
        recordingSettings.microphoneDeviceID = Self.allowedPreferredMicrophoneDeviceID(
            recordingSettings.microphoneDeviceID,
            devices: availableMicrophoneDevices
        )
        if previousPreferredMicrophoneDeviceID != recordingSettings.microphoneDeviceID,
           let previousPreferredMicrophoneDeviceID {
            AppLogger.file(
                .warning,
                category: "recording",
                "blocked preferred microphone cleared device_id=\(previousPreferredMicrophoneDeviceID)"
            )
        }

        let selection = Self.resolveMicrophoneSelection(
            devices: availableMicrophoneDevices,
            preferredDeviceID: recordingSettings.microphoneDeviceID
        )
        selectedMicrophoneName = selection?.device.name ?? "No input device"
        microphoneInputWarning = selection?.warning
        microphoneSelectionReason = DevicePriorityResolver.selectionReason(
            devices: availableMicrophoneDevices,
            selection: selection,
            preferredDeviceID: recordingSettings.microphoneDeviceID
        )
        logSelectedMicrophoneIfNeeded()
    }

    private func logSelectedMicrophoneIfNeeded() {
        guard selectedMicrophoneName != lastLoggedSelectedMicrophoneName else {
            return
        }

        lastLoggedSelectedMicrophoneName = selectedMicrophoneName
        AppLogger.file(.info, category: "recording", "selected mic=\(selectedMicrophoneName) recommended=\(recommendedMicrophoneName) reason=\(microphoneSelectionReason)")

        if let microphoneInputWarning {
            AppLogger.file(.warning, category: "recording", microphoneInputWarning)
        }
    }

    private static func resolveMicrophoneSelection(
        devices: [MicrophoneInputDevice],
        preferredDeviceID: String?
    ) -> MicrophoneDeviceSelection? {
        DevicePriorityResolver.resolve(
            devices: devices,
            preferredDeviceID: preferredDeviceID
        )
    }

    private static func allowedPreferredMicrophoneDeviceID(
        _ preferredDeviceID: String?,
        devices: [MicrophoneInputDevice]
    ) -> String? {
        guard let preferredDeviceID,
              !preferredDeviceID.isEmpty
        else {
            return nil
        }

        guard let preferredDevice = devices.first(where: { $0.id == preferredDeviceID }) else {
            return preferredDeviceID
        }

        return DevicePriorityResolver.isBlockedInput(preferredDevice) ? nil : preferredDeviceID
    }

    private static func sanitizedPermissionCacheComponent(_ value: String) -> String {
        value
            .replacingOccurrences(of: " ", with: "_")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: ":", with: "_")
    }

    private func draft(
        id: String,
        sessionFolderURL: URL,
        metadataURL: URL
    ) throws -> PostCallDraft {
        let metadata = try recordingStore.readMetadata(at: metadataURL)
        return PostCallDraft(
            id: id,
            title: metadata.title,
            category: metadata.category,
            participant: metadata.participants.first ?? "",
            tags: metadata.tags,
            status: metadata.status,
            sessionFolderURL: sessionFolderURL,
            metadataURL: metadataURL
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
                self.refreshAudioLevels()

                do {
                    try await Task.sleep(for: .milliseconds(250))
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
        microphoneLevel = 0
        systemAudioLevel = 0
    }

    private func refreshDuration() {
        guard status == .recording, let recordingStartedAt else {
            return
        }

        currentRecordingDuration = Date().timeIntervalSince(recordingStartedAt)
    }

    private func refreshAudioLevels() {
        guard status == .recording else {
            microphoneLevel = 0
            systemAudioLevel = 0
            return
        }

        let levels = recordingController.currentAudioLevels()
        microphoneLevel = levels.microphoneLevel
        systemAudioLevel = levels.systemAudioLevel
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
