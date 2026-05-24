import Foundation

public struct RecordingPreflightContext: Equatable, Sendable {
    public let permissionSnapshot: RecorderPermissionSnapshot
    public let systemAudioEnabled: Bool
    public let outputFolderURL: URL
    public let availableMicrophoneDevices: [MicrophoneInputDevice]
    public let preferredMicrophoneDeviceID: String?
    public let systemAudioCaptureAvailable: Bool
    public let isRecordingActive: Bool

    public init(
        permissionSnapshot: RecorderPermissionSnapshot,
        systemAudioEnabled: Bool,
        outputFolderURL: URL,
        availableMicrophoneDevices: [MicrophoneInputDevice],
        preferredMicrophoneDeviceID: String?,
        systemAudioCaptureAvailable: Bool = true,
        isRecordingActive: Bool
    ) {
        self.permissionSnapshot = permissionSnapshot
        self.systemAudioEnabled = systemAudioEnabled
        self.outputFolderURL = outputFolderURL
        self.availableMicrophoneDevices = availableMicrophoneDevices
        self.preferredMicrophoneDeviceID = preferredMicrophoneDeviceID
        self.systemAudioCaptureAvailable = systemAudioCaptureAvailable
        self.isRecordingActive = isRecordingActive
    }
}

public protocol RecordingPreflightChecking: Sendable {
    func validate(_ context: RecordingPreflightContext) throws
}

public final class DefaultRecordingPreflightChecker: RecordingPreflightChecking, @unchecked Sendable {
    public static let defaultMinimumFreeDiskSpaceBytes: Int64 = 2 * 1024 * 1024 * 1024

    private let minimumFreeDiskSpaceBytes: Int64
    private let fileManager: FileManager

    public init(
        minimumFreeDiskSpaceBytes: Int64 = DefaultRecordingPreflightChecker.defaultMinimumFreeDiskSpaceBytes,
        fileManager: FileManager = .default
    ) {
        self.minimumFreeDiskSpaceBytes = max(0, minimumFreeDiskSpaceBytes)
        self.fileManager = fileManager
    }

    public func validate(_ context: RecordingPreflightContext) throws {
        if context.isRecordingActive {
            throw RecordingControllerError.alreadyRecording
        }

        if let blockingReason = RecordingPermissionDisplay.blockingReason(
            context.permissionSnapshot,
            systemAudioEnabled: context.systemAudioEnabled
        ) {
            throw RecordingControllerError.preflightFailed(blockingReason)
        }

        if context.systemAudioEnabled && !context.systemAudioCaptureAvailable {
            throw RecordingControllerError.preflightFailed("System audio capture is not available on this Mac.")
        }

        guard DevicePriorityResolver.resolve(
            devices: context.availableMicrophoneDevices,
            preferredDeviceID: context.preferredMicrophoneDeviceID
        ) != nil else {
            throw RecordingControllerError.preflightFailed("No microphone input device is available.")
        }

        try validateWritableOutputRoot(context.outputFolderURL)
        try validateFreeDiskSpace(context.outputFolderURL)
    }

    private func validateWritableOutputRoot(_ url: URL) throws {
        do {
            try fileManager.createDirectory(at: url, withIntermediateDirectories: true)
            let testURL = url.appendingPathComponent(".torbit-preflight-write-test")
            try Data().write(to: testURL, options: [.atomic])
            try? fileManager.removeItem(at: testURL)
        } catch {
            AppLogger.file(.error, category: "preflight", "output root is not writable path=\(url.path(percentEncoded: false)) error=\(String(describing: error))")
            throw RecordingControllerError.preflightFailed("The recordings folder must be writable before recording.")
        }
    }

    private func validateFreeDiskSpace(_ url: URL) throws {
        let freeBytes = try availableDiskSpaceBytes(at: url)
        guard freeBytes >= minimumFreeDiskSpaceBytes else {
            AppLogger.file(.error, category: "preflight", "free disk space below minimum path=\(url.path(percentEncoded: false)) free_bytes=\(freeBytes) minimum_bytes=\(minimumFreeDiskSpaceBytes)")
            throw RecordingControllerError.preflightFailed("At least 2 GB of free disk space is required before recording.")
        }
    }

    private func availableDiskSpaceBytes(at url: URL) throws -> Int64 {
        do {
            let values = try url.resourceValues(forKeys: [
                .volumeAvailableCapacityForImportantUsageKey,
                .volumeAvailableCapacityKey
            ])

            if let importantUsageCapacity = values.volumeAvailableCapacityForImportantUsage {
                return importantUsageCapacity
            }

            if let capacity = values.volumeAvailableCapacity {
                return Int64(capacity)
            }

            return .max
        } catch {
            AppLogger.file(.error, category: "preflight", "failed to read free disk space path=\(url.path(percentEncoded: false)) error=\(String(describing: error))")
            throw RecordingControllerError.preflightFailed("Unable to check free disk space before recording.")
        }
    }
}
