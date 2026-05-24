import Combine
import Foundation

@MainActor
public final class AppState: ObservableObject {
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
    @Published public private(set) var autoStartNotificationMessage: String?
    @Published public private(set) var outputFolderURL: URL
    @Published public private(set) var availableMicrophoneDevices: [MicrophoneInputDevice]
    @Published public private(set) var selectedMicrophoneName: String
    @Published public private(set) var recommendedMicrophoneName: String
    @Published public private(set) var microphoneInputWarning: String?
    @Published public private(set) var microphoneSelectionReason: String
    @Published public private(set) var permissionSnapshot: RecorderPermissionSnapshot

    private let recordingController: RecordingController
    private let permissionChecker: RecordingPermissionChecking
    private let microphoneDeviceProvider: () -> [MicrophoneInputDevice]
    private var recordingStore: FileSystemRecordingStore
    private let activeApplicationDetector: ActiveApplicationDetecting
    private let audioActivityDetector: AudioActivityDetecting
    private var recordingStartedAt: Date?
    private var durationTask: Task<Void, Never>?
    private var autoStartTask: Task<Void, Never>?
    private var microphoneDeviceTask: Task<Void, Never>?
    private var autoStartEngine: AutoStartEngine
    private var lastRecordingStoppedAt: Date?
    private var lastAutoStartDecisionLogKey: String?
    private var lastLoggedSelectedMicrophoneName: String?
    private var screenSystemAudioSettingsOpened = false

    public var outputFolderPath: String {
        outputFolderURL.path(percentEncoded: false)
    }

    public var formattedDuration: String {
        Self.formatDuration(currentRecordingDuration)
    }

    public var shouldShowPermissionsOnboarding: Bool {
        RecordingPermissionDisplay.shouldShowOnboarding(
            permissionSnapshot,
            systemAudioEnabled: recordingSettings.systemAudioEnabled
        )
    }

    public var isRecordingStartAllowed: Bool {
        status != .recording
            && selectedMicrophoneName != "No input device"
            && RecordingPermissionDisplay.canStartRecording(
                permissionSnapshot,
                systemAudioEnabled: recordingSettings.systemAudioEnabled
            )
    }

    public var recordingStartBlockingReason: String? {
        if selectedMicrophoneName == "No input device" {
            return "No microphone input device is available."
        }

        return RecordingPermissionDisplay.blockingReason(
            permissionSnapshot,
            systemAudioEnabled: recordingSettings.systemAudioEnabled
        )
    }

    public init(
        recordingController: RecordingController? = nil,
        outputFolderURL: URL? = nil,
        activeApplicationDetector: ActiveApplicationDetecting? = nil,
        audioActivityDetector: AudioActivityDetecting? = nil,
        permissionChecker: RecordingPermissionChecking? = nil,
        microphoneDeviceProvider: @escaping () -> [MicrophoneInputDevice] = MicrophoneDeviceProvider.availableInputDevices,
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
        self.permissionChecker = permissionChecker ?? SystemRecordingPermissionChecker()
        self.outputFolderURL = resolvedSettings.storage.rootFolderURL
        self.activeApplicationDetector = activeApplicationDetector ?? WorkspaceActiveApplicationDetector()
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
        self.autoStartNotificationMessage = nil
        let availableMicrophoneDevices = microphoneDeviceProvider()
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
        self.autoStartEngine = AutoStartEngine()
        self.recordingStore = FileSystemRecordingStore(rootURL: resolvedSettings.storage.rootFolderURL)
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
        guard status != .recording else {
            throw RecordingControllerError.alreadyRecording
        }

        do {
            refreshMicrophoneDevices()
            refreshPermissionSnapshot()

            guard isRecordingStartAllowed else {
                let message = recordingStartBlockingReason ?? "Required recording permissions are not ready."
                let error = RecordingControllerError.preflightFailed(message)
                applyError(error)
                AppLogger.recording.error("Recording preflight failed before session creation: \(message, privacy: .public)")
                AppLogger.file(.error, category: "permissions", "recording preflight failed: \(message)")
                throw error
            }

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
            activeMarkers = []
            mixedPreviewPath = nil
            errorMessage = nil
            startDurationClock()
            AppLogger.recording.info("Recording state changed to recording. trigger=\(source.trigger, privacy: .public), app=\(source.appName, privacy: .public), bundle_id=\(source.bundleID, privacy: .public), rule_id=\(source.ruleID, privacy: .public)")
            AppLogger.file(.info, category: "recording", "recording start trigger=\(source.trigger) app=\(source.appName) bundle_id=\(source.bundleID) rule_id=\(source.ruleID) output_root=\(outputFolderPath) selected_mic=\(selectedMicrophoneName)")
        } catch {
            applyError(error)
            AppLogger.recording.error("Failed to start recording: \(String(describing: error), privacy: .public)")
            AppLogger.file(.error, category: "recording", "recording failure during start error=\(String(describing: error))")
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
            if !activeMarkers.isEmpty {
                try recordingStore.appendMarkers(activeMarkers, to: draft)
                AppLogger.recording.info("Saved \(self.activeMarkers.count, privacy: .public) recording markers for \(draft.id, privacy: .public)")
                AppLogger.file(.info, category: "recording", "saved recording markers id=\(draft.id) count=\(activeMarkers.count)")
                activeMarkers = []
            }
            mixedPreviewPath = mixedPreviewPath(for: draft)
            isPostCallPanelPresented = draft.status != .shortRecording && draft.status != .failed
            lastRecordingStoppedAt = Date()
            try reloadRecordings()
            try reloadLastRecording()
            try reloadRecoverableRecordings()
            errorMessage = nil
            if draft.status == .shortRecording {
                AppLogger.recording.info("Recording stopped as short_recording; post-call tagging skipped for \(draft.id, privacy: .public)")
            } else {
                AppLogger.recording.info("Recording stopped; post-call tagging required for \(draft.id, privacy: .public)")
            }
            AppLogger.file(.info, category: "recording", "recording stop id=\(draft.id) status=\(draft.status.rawValue) folder=\(draft.sessionFolderURL.path(percentEncoded: false)) mixed=\(mixedPreviewPath ?? "missing")")
        } catch {
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
        AppLogger.file(.info, category: "recording", "saved post-call tags id=\(draft.id) status=\(draft.status.rawValue) tags=\(draft.tags.joined(separator: ","))")
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

    public func setAutoStartEnabled(_ isEnabled: Bool) {
        updateAutoStartSettings { settings in
            settings.isEnabled = isEnabled
        }
    }

    public func setAutoStartMode(_ mode: AutoStartMode) {
        updateAutoStartSettings { settings in
            settings.mode = mode
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
                shortRecordingThresholdSeconds: settings.shortRecordingThresholdSeconds
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
                shortRecordingThresholdSeconds: settings.shortRecordingThresholdSeconds
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
                shortRecordingThresholdSeconds: seconds
            )
        }
    }

    public func setSystemAudioEnabled(_ isEnabled: Bool) {
        recordingSettings.systemAudioEnabled = isEnabled
        refreshPermissionSnapshot()
        saveSettings()
    }

    public func setMixedPreviewEnabled(_ isEnabled: Bool) {
        recordingSettings.mixedPreviewEnabled = isEnabled
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
        permissionSnapshot = permissionChecker.snapshot(
            outputFolderURL: outputFolderURL,
            screenSystemAudioSettingsOpened: screenSystemAudioSettingsOpened,
            lastErrorMessage: errorMessage
        )
    }

    public func markScreenSystemAudioSettingsOpened() {
        screenSystemAudioSettingsOpened = true
        refreshPermissionSnapshot()
    }

    public func setPreferredMicrophoneDeviceID(_ deviceID: String?) {
        recordingSettings.microphoneDeviceID = deviceID?.isEmpty == true ? nil : deviceID
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

    public func setLaunchAtLoginPreference(_ isEnabled: Bool) {
        privacySettings.launchAtLogin = isEnabled
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

        applyAutoStartDecision(
            decision,
            activeApplication: activeApplication,
            audioActivity: audioActivity,
            now: now
        )

        if decision.action == .ask, let source = decision.recordingSource {
            publishAutoStartNotification("Call detected: \(source.appName)")
            return
        }

        guard decision.action == .start, let source = decision.recordingSource else {
            return
        }

        do {
            try await startRecording(source: source)
            publishAutoStartNotification(notificationMessage(for: source))
        } catch {
            applyError(error)
            AppLogger.recording.error("Auto-start failed: reason=\(decision.reason.rawValue, privacy: .public), confidence=\(decision.confidence, privacy: .public), app=\(source.appName, privacy: .public), bundle_id=\(source.bundleID, privacy: .public), error=\(String(describing: error), privacy: .public)")
            AppLogger.file(.error, category: "autostart", "auto-start failed reason=\(decision.reason.rawValue) confidence=\(decision.confidence) app=\(source.appName) bundle_id=\(source.bundleID) error=\(String(describing: error))")
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
            isPostCallPanelPresented = draft.status != .failed
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

    private func publishAutoStartNotification(_ message: String) {
        autoStartNotificationMessage = nil
        autoStartNotificationMessage = message
    }

    private func notificationMessage(for source: RecordingSource) -> String {
        if source.ruleID.contains("browser") {
            return "Recording started: browser call detected"
        }

        return "Recording started: \(source.appName)"
    }

    private func applyError(_ error: Error) {
        status = .error
        micStatus = Self.captureStatus(for: error)
        systemAudioStatus = Self.systemAudioStatus(for: error)
        microphoneLevel = 0
        systemAudioLevel = 0
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
            shortRecordingThresholdSeconds: settings.shortRecordingThresholdSeconds
        )
        autoStartEngine.resetCandidate()
        saveSettings()
    }

    private func recordingRuntimeSettings() -> RecordingRuntimeSettings {
        RecordingRuntimeSettings(
            audioQualityPreset: recordingSettings.audioQualityPreset,
            systemAudioEnabled: recordingSettings.systemAudioEnabled,
            mixedPreviewEnabled: recordingSettings.mixedPreviewEnabled,
            shortRecordingThresholdSeconds: autoStartSettings.shortRecordingThresholdSeconds,
            preferredMicrophoneDeviceID: recordingSettings.microphoneDeviceID
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
