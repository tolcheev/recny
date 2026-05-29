@preconcurrency import AVFoundation
import AudioToolbox
import CoreAudio
@preconcurrency import CoreMedia
import Foundation
@preconcurrency import ScreenCaptureKit

public struct SystemAudioRecordingResult: Equatable, Sendable {
    public let duration: TimeInterval
    public let sampleCount: Int
    public let fileSize: Int64
}

struct SystemAudioPermissionProbeRunner: Sendable {
    /// Default upper bound for polling real audio frames after `startCapture`
    /// returns. macOS may show the TCC prompt asynchronously, so the probe
    /// keeps polling until either real frames arrive or the bound elapses.
    static let defaultMaxWaitNanoseconds: UInt64 = 8_000_000_000
    /// Default polling interval while waiting for the first audio frame.
    static let defaultPollIntervalNanoseconds: UInt64 = 200_000_000

    let temporaryDirectory: URL
    let startCapture: @Sendable (URL) throws -> Void
    let stopCapture: @Sendable () -> Void
    let cleanupOutput: @Sendable (URL) -> Void
    let sleepNanoseconds: @Sendable (UInt64) async throws -> Void
    let frameCount: @Sendable () -> Int64
    let pollIntervalNanoseconds: UInt64
    let maxWaitNanoseconds: UInt64

    init(
        temporaryDirectory: URL,
        startCapture: @escaping @Sendable (URL) throws -> Void,
        stopCapture: @escaping @Sendable () -> Void,
        cleanupOutput: @escaping @Sendable (URL) -> Void,
        sleepNanoseconds: @escaping @Sendable (UInt64) async throws -> Void,
        frameCount: @escaping @Sendable () -> Int64,
        pollIntervalNanoseconds: UInt64 = SystemAudioPermissionProbeRunner.defaultPollIntervalNanoseconds,
        maxWaitNanoseconds: UInt64 = SystemAudioPermissionProbeRunner.defaultMaxWaitNanoseconds
    ) {
        self.temporaryDirectory = temporaryDirectory
        self.startCapture = startCapture
        self.stopCapture = stopCapture
        self.cleanupOutput = cleanupOutput
        self.sleepNanoseconds = sleepNanoseconds
        self.frameCount = frameCount
        self.pollIntervalNanoseconds = pollIntervalNanoseconds
        self.maxWaitNanoseconds = maxWaitNanoseconds
    }

    func requestAccess() async throws {
        let outputURL = temporaryDirectory
            .appendingPathComponent("torbit-system-audio-permission-\(UUID().uuidString).m4a")
        try startCapture(outputURL)
        defer {
            stopCapture()
            cleanupOutput(outputURL)
        }

        // Poll for actual audio frames. Creating the tap can succeed (and
        // even return cached TCC approval) before the user dismisses the
        // system prompt, but macOS will not deliver real audio bytes until
        // the user clicks Allow. Treat sample arrival as the only proof.
        let interval = max(UInt64(1), pollIntervalNanoseconds)
        var elapsedNanoseconds: UInt64 = 0
        while elapsedNanoseconds < maxWaitNanoseconds {
            try await sleepNanoseconds(interval)
            elapsedNanoseconds &+= interval
            if frameCount() > 0 {
                return
            }
        }

        throw RecordingControllerError.systemAudioPermissionDenied(
            "Core Audio system audio permission probe captured no samples within \(maxWaitNanoseconds / 1_000_000) ms; macOS prompt may still be pending or permission was denied."
        )
    }
}

public final class ScreenCaptureKitSystemAudioRecorder: NSObject, @unchecked Sendable {
    public static let sampleRate: Double = 48_000
    public static let channels: Int = 2
    public static let bitrate: Int = 128_000
    public static let captureBackendName = "Core Audio process tap"
    static let audioFileWriteOperationName = "ExtAudioFileWrite"
    public static let requiresScreenCaptureKitPermissionRequest = false

    public static var isSystemAudioCaptureAvailable: Bool {
        true
    }

    public static func requestSystemAudioAccess() async throws {
        let recorder = CoreAudioProcessTapSystemAudioRecorder()
        let runner = SystemAudioPermissionProbeRunner(
            temporaryDirectory: FileManager.default.temporaryDirectory,
            startCapture: { outputURL in
                try recorder.start(outputURL: outputURL, qualityPreset: .standard)
            },
            stopCapture: {
                recorder.stopPermissionProbe()
            },
            cleanupOutput: { outputURL in
                try? FileManager.default.removeItem(at: outputURL)
            },
            sleepNanoseconds: { nanoseconds in
                try await Task.sleep(nanoseconds: nanoseconds)
            },
            frameCount: {
                recorder.frameCountSnapshot()
            }
        )

        try await runner.requestAccess()
        AppLogger.file(.info, category: "permissions", "system audio permission capture probe succeeded backend=core_audio_process_tap frames=\(recorder.frameCountSnapshot())")
    }

    // Kept for legacy diagnostics/tests. The MVP recorder uses Core Audio taps
    // and must not require ScreenCaptureKit screen-recording permission.
    private static func requestScreenCaptureKitAccess() async throws {
        do {
            AppLogger.file(.info, category: "permissions", "system audio permission request via ScreenCaptureKit started")
            _ = try await SCShareableContent.excludingDesktopWindows(
                false,
                onScreenWindowsOnly: true
            )
            AppLogger.file(.info, category: "permissions", "system audio permission request via ScreenCaptureKit finished")
        } catch {
            throw RecordingControllerError.systemAudioPermissionDenied(
                "Screen & System Audio Recording permission is unavailable: \(String(describing: error))"
            )
        }
    }

    public static var assetWriterAudioSettings: [String: Any] {
        assetWriterAudioSettings(for: .standard)
    }

    public static func assetWriterAudioSettings(for preset: AudioQualityPreset) -> [String: Any] {
        [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: sampleRate,
            AVNumberOfChannelsKey: channels,
            AVEncoderBitRateKey: preset.systemAudioBitrate
        ]
    }

    public static func streamConfiguration() -> SCStreamConfiguration {
        let configuration = SCStreamConfiguration()
        configuration.width = 2
        configuration.height = 2
        configuration.minimumFrameInterval = CMTime(value: 1, timescale: 1)
        configuration.queueDepth = 1
        configuration.showsCursor = false
        configuration.capturesAudio = true
        configuration.captureMicrophone = false
        configuration.sampleRate = Int(Self.sampleRate)
        configuration.channelCount = Self.channels
        configuration.excludesCurrentProcessAudio = false
        return configuration
    }

    private let backend = CoreAudioProcessTapSystemAudioRecorder()

    public func start(
        outputURL: URL,
        qualityPreset: AudioQualityPreset = .standard
    ) async throws {
        try backend.start(outputURL: outputURL, qualityPreset: qualityPreset)
    }

    public func stop() async throws -> SystemAudioRecordingResult {
        try backend.stop()
    }

    public func currentLevel() -> Float {
        backend.currentLevel()
    }
}

private final class CoreAudioProcessTapSystemAudioRecorder: @unchecked Sendable {
    private static let aggregateDeviceName = "TOrbitRecorder System Audio"
    private static let tapName = "TOrbitRecorder System Audio Tap"
    private static let ioProc: AudioDeviceIOProc = { _, _, inputData, inputTime, _, _, clientData in
        guard let clientData else {
            return noErr
        }

        let recorder = Unmanaged<CoreAudioProcessTapSystemAudioRecorder>
            .fromOpaque(clientData)
            .takeUnretainedValue()
        recorder.handleInputData(inputData, inputTime: inputTime)
        return noErr
    }

    private let lock = NSLock()
    private var tapID = AudioObjectID(0)
    private var aggregateDeviceID = AudioObjectID(0)
    private var ioProcID: AudioDeviceIOProcID?
    private var audioFile: ExtAudioFileRef?
    private var outputURL: URL?
    private var inputFormat = AudioStreamBasicDescription()
    private var writtenFrames: Int64 = 0
    private var firstSampleTime: Float64?
    private var lastSampleTime: Float64?
    private var lastSampleWallClock: Date?
    private var writeError: OSStatus = noErr

    func start(
        outputURL: URL,
        qualityPreset: AudioQualityPreset
    ) throws {
        guard audioFile == nil,
              tapID == 0,
              aggregateDeviceID == 0,
              ioProcID == nil
        else {
            throw RecordingControllerError.alreadyRecording
        }

        try FileManager.default.removeItemIfExists(at: outputURL)

        do {
            let tapID = try createProcessTap()
            self.tapID = tapID

            let tapUID = try Self.tapUID(for: tapID)
            let aggregateDeviceID = try createAggregateDevice(tapUID: tapUID)
            self.aggregateDeviceID = aggregateDeviceID

            inputFormat = try Self.deviceStreamFormat(for: aggregateDeviceID)
            audioFile = try Self.createAudioFile(
                outputURL: outputURL,
                inputFormat: inputFormat,
                qualityPreset: qualityPreset
            )

            var createdIOProcID: AudioDeviceIOProcID?
            let ioProcStatus = AudioDeviceCreateIOProcID(
                aggregateDeviceID,
                Self.ioProc,
                Unmanaged.passUnretained(self).toOpaque(),
                &createdIOProcID
            )
            guard ioProcStatus == noErr, let createdIOProcID else {
                throw RecordingControllerError.systemAudioSetupFailed(
                    Self.osStatusMessage(ioProcStatus, operation: "AudioDeviceCreateIOProcID")
                )
            }
            ioProcID = createdIOProcID

            lock.withLock {
                self.outputURL = outputURL
                self.writtenFrames = 0
                self.firstSampleTime = nil
                self.lastSampleTime = nil
                self.lastSampleWallClock = nil
                self.writeError = noErr
            }

            let startStatus = AudioDeviceStart(aggregateDeviceID, createdIOProcID)
            guard startStatus == noErr else {
                throw RecordingControllerError.systemAudioSetupFailed(
                    Self.osStatusMessage(startStatus, operation: "AudioDeviceStart")
                )
            }

            AppLogger.recording.info("System audio capture started with Core Audio process tap: \(outputURL.path(percentEncoded: false), privacy: .public)")
            AppLogger.file(.info, category: "recording", "system audio capture started backend=core_audio_process_tap output=\(outputURL.path(percentEncoded: false))")
        } catch {
            cleanup()
            throw Self.mapCoreAudioStartError(error)
        }
    }

    func stop() throws -> SystemAudioRecordingResult {
        guard let outputURL,
              let activeAudioFile = audioFile
        else {
            throw RecordingControllerError.notRecording
        }

        if aggregateDeviceID != 0, let ioProcID {
            let stopStatus = AudioDeviceStop(aggregateDeviceID, ioProcID)
            if stopStatus != noErr {
                AppLogger.file(.warning, category: "recording", Self.osStatusMessage(stopStatus, operation: "AudioDeviceStop"))
            }
        }

        let snapshot = lock.withLock { () -> (Int64, Float64?, Float64?, OSStatus) in
            (writtenFrames, firstSampleTime, lastSampleTime, writeError)
        }

        let disposeStatus = ExtAudioFileDispose(activeAudioFile)
        audioFile = nil
        if disposeStatus != noErr {
            cleanup()
            throw RecordingControllerError.systemAudioWriteFailed(
                Self.osStatusMessage(disposeStatus, operation: "ExtAudioFileDispose")
            )
        }

        cleanup(keepAudioFile: false)

        guard snapshot.3 == noErr else {
            throw RecordingControllerError.systemAudioWriteFailed(
                Self.osStatusMessage(snapshot.3, operation: ScreenCaptureKitSystemAudioRecorder.audioFileWriteOperationName)
            )
        }

        let attributes = try FileManager.default.attributesOfItem(atPath: outputURL.path(percentEncoded: false))
        let fileSize = (attributes[.size] as? NSNumber)?.int64Value ?? 0

        guard snapshot.0 > 0 else {
            throw RecordingControllerError.systemAudioNoSamples
        }

        guard fileSize > 0 else {
            throw RecordingControllerError.systemAudioWriteFailed("Empty file at \(outputURL.path(percentEncoded: false))")
        }

        let duration = Self.duration(
            frames: snapshot.0,
            firstSampleTime: snapshot.1,
            lastSampleTime: snapshot.2,
            sampleRate: inputFormat.mSampleRate
        )
        AppLogger.recording.info("System audio capture stopped after \(duration, privacy: .public) seconds")
        AppLogger.file(.info, category: "recording", "system audio capture stopped backend=core_audio_process_tap duration=\(duration) frames=\(snapshot.0) output=\(outputURL.path(percentEncoded: false))")

        return SystemAudioRecordingResult(
            duration: duration,
            sampleCount: Int(min(snapshot.0, Int64(Int.max))),
            fileSize: fileSize
        )
    }

    func stopPermissionProbe() {
        if aggregateDeviceID != 0, let ioProcID {
            let stopStatus = AudioDeviceStop(aggregateDeviceID, ioProcID)
            if stopStatus != noErr {
                AppLogger.file(.warning, category: "permissions", Self.osStatusMessage(stopStatus, operation: "AudioDeviceStop(permissionProbe)"))
            }
        }
        cleanup(keepAudioFile: false)
    }

    /// Snapshot of how many audio frames have been written so far.
    /// Used by the permission probe to verify that macOS is actually
    /// delivering real samples (i.e. user clicked Allow on the TCC prompt).
    func frameCountSnapshot() -> Int64 {
        lock.withLock { writtenFrames }
    }

    func currentLevel() -> Float {
        lock.withLock {
            guard let lastSampleWallClock,
                  Date().timeIntervalSince(lastSampleWallClock) < 1.25
            else {
                return 0
            }

            return 0.55
        }
    }

    private func handleInputData(
        _ inputData: UnsafePointer<AudioBufferList>?,
        inputTime: UnsafePointer<AudioTimeStamp>
    ) {
        guard let inputData else {
            return
        }

        let frameCount = Self.frameCount(
            from: inputData,
            bytesPerFrame: inputFormat.mBytesPerFrame
        )
        guard frameCount > 0 else {
            return
        }

        lock.withLock {
            guard let audioFile,
                  writeError == noErr
            else {
                return
            }

            // Sync writes avoid kExtAudioFileError_AsyncWriteBufferOverflow on
            // longer calls, where the async AAC encoder queue can lag behind.
            let status = ExtAudioFileWrite(audioFile, frameCount, inputData)
            if status == noErr {
                if firstSampleTime == nil,
                   inputTime.pointee.mFlags.contains(.sampleTimeValid) {
                    firstSampleTime = inputTime.pointee.mSampleTime
                }
                if inputTime.pointee.mFlags.contains(.sampleTimeValid) {
                    lastSampleTime = inputTime.pointee.mSampleTime
                }
                writtenFrames += Int64(frameCount)
                lastSampleWallClock = Date()
            } else {
                writeError = status
            }
        }
    }

    private func createProcessTap() throws -> AudioObjectID {
        var tapID = AudioObjectID(0)
        let description = CATapDescription(stereoGlobalTapButExcludeProcesses: [])
        description.name = Self.tapName
        description.isPrivate = true
        description.muteBehavior = .unmuted

        let status = AudioHardwareCreateProcessTap(description, &tapID)
        guard status == noErr, tapID != 0 else {
            throw RecordingControllerError.systemAudioPermissionDenied(
                "Core Audio system audio access denied or unavailable: \(Self.osStatusMessage(status, operation: "AudioHardwareCreateProcessTap"))"
            )
        }

        return tapID
    }

    private func createAggregateDevice(tapUID: String) throws -> AudioObjectID {
        var aggregateDeviceID = AudioObjectID(0)
        let aggregateUID = "com.torbit.recorder.system-audio.\(UUID().uuidString)"
        let subTapDescription: [String: Any] = [
            kAudioSubTapUIDKey: tapUID,
            kAudioSubTapDriftCompensationKey: true,
            kAudioSubTapDriftCompensationQualityKey: kAudioAggregateDriftCompensationHighQuality
        ]
        let aggregateDescription: [String: Any] = [
            kAudioAggregateDeviceNameKey: Self.aggregateDeviceName,
            kAudioAggregateDeviceUIDKey: aggregateUID,
            kAudioAggregateDeviceIsPrivateKey: true,
            kAudioAggregateDeviceTapListKey: [subTapDescription],
            kAudioAggregateDeviceTapAutoStartKey: false
        ]

        let status = AudioHardwareCreateAggregateDevice(
            aggregateDescription as CFDictionary,
            &aggregateDeviceID
        )
        guard status == noErr, aggregateDeviceID != 0 else {
            throw RecordingControllerError.systemAudioSetupFailed(
                Self.osStatusMessage(status, operation: "AudioHardwareCreateAggregateDevice")
            )
        }

        return aggregateDeviceID
    }

    private func cleanup(keepAudioFile: Bool = false) {
        if aggregateDeviceID != 0, let ioProcID {
            _ = AudioDeviceDestroyIOProcID(aggregateDeviceID, ioProcID)
            self.ioProcID = nil
        }
        if !keepAudioFile, let audioFile {
            _ = ExtAudioFileDispose(audioFile)
            self.audioFile = nil
        }
        if aggregateDeviceID != 0 {
            _ = AudioHardwareDestroyAggregateDevice(aggregateDeviceID)
            aggregateDeviceID = 0
        }
        if tapID != 0 {
            _ = AudioHardwareDestroyProcessTap(tapID)
            tapID = 0
        }
        outputURL = nil
    }

    private static func createAudioFile(
        outputURL: URL,
        inputFormat: AudioStreamBasicDescription,
        qualityPreset: AudioQualityPreset
    ) throws -> ExtAudioFileRef {
        var outputFormat = AudioStreamBasicDescription(
            mSampleRate: ScreenCaptureKitSystemAudioRecorder.sampleRate,
            mFormatID: kAudioFormatMPEG4AAC,
            mFormatFlags: 0,
            mBytesPerPacket: 0,
            mFramesPerPacket: 1024,
            mBytesPerFrame: 0,
            mChannelsPerFrame: UInt32(ScreenCaptureKitSystemAudioRecorder.channels),
            mBitsPerChannel: 0,
            mReserved: 0
        )
        var audioFile: ExtAudioFileRef?
        let createStatus = ExtAudioFileCreateWithURL(
            outputURL as CFURL,
            kAudioFileM4AType,
            &outputFormat,
            nil,
            AudioFileFlags.eraseFile.rawValue,
            &audioFile
        )
        guard createStatus == noErr, let audioFile else {
            throw RecordingControllerError.systemAudioWriteFailed(
                osStatusMessage(createStatus, operation: "ExtAudioFileCreateWithURL")
            )
        }

        var clientFormat = inputFormat
        let setClientStatus = ExtAudioFileSetProperty(
            audioFile,
            kExtAudioFileProperty_ClientDataFormat,
            UInt32(MemoryLayout<AudioStreamBasicDescription>.size),
            &clientFormat
        )
        guard setClientStatus == noErr else {
            _ = ExtAudioFileDispose(audioFile)
            throw RecordingControllerError.systemAudioWriteFailed(
                osStatusMessage(setClientStatus, operation: "ExtAudioFileSetProperty(ClientDataFormat)")
            )
        }

        Self.configureBitrate(
            audioFile: audioFile,
            bitrate: UInt32(qualityPreset.systemAudioBitrate)
        )

        return audioFile
    }

    private static func configureBitrate(
        audioFile: ExtAudioFileRef,
        bitrate: UInt32
    ) {
        var converter: AudioConverterRef?
        var size = UInt32(MemoryLayout<AudioConverterRef?>.size)
        let getStatus = ExtAudioFileGetProperty(
            audioFile,
            kExtAudioFileProperty_AudioConverter,
            &size,
            &converter
        )
        guard getStatus == noErr, let converter else {
            return
        }

        var mutableBitrate = bitrate
        _ = AudioConverterSetProperty(
            converter,
            kAudioConverterEncodeBitRate,
            UInt32(MemoryLayout<UInt32>.size),
            &mutableBitrate
        )
    }

    private static func tapUID(for tapID: AudioObjectID) throws -> String {
        guard let uid = cfStringProperty(selector: kAudioTapPropertyUID, objectID: tapID) else {
            throw RecordingControllerError.systemAudioSetupFailed("Core Audio process tap did not expose a UID")
        }

        return uid
    }

    private static func deviceStreamFormat(for deviceID: AudioDeviceID) throws -> AudioStreamBasicDescription {
        var format = AudioStreamBasicDescription()
        var size = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreamFormat,
            mScope: kAudioDevicePropertyScopeInput,
            mElement: kAudioObjectPropertyElementMain
        )

        let status = AudioObjectGetPropertyData(
            deviceID,
            &address,
            0,
            nil,
            &size,
            &format
        )
        guard status == noErr,
              format.mSampleRate > 0,
              format.mChannelsPerFrame > 0
        else {
            throw RecordingControllerError.systemAudioSetupFailed(
                osStatusMessage(status, operation: "AudioObjectGetPropertyData(StreamFormat)")
            )
        }

        return format
    }

    private static func cfStringProperty(
        selector: AudioObjectPropertySelector,
        objectID: AudioObjectID
    ) -> String? {
        var value: CFString?
        var size = UInt32(MemoryLayout<CFString?>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        let status = withUnsafeMutablePointer(to: &value) { pointer in
            AudioObjectGetPropertyData(
                objectID,
                &address,
                0,
                nil,
                &size,
                pointer
            )
        }

        guard status == noErr, let value else {
            return nil
        }

        return value as String
    }

    private static func frameCount(
        from inputData: UnsafePointer<AudioBufferList>,
        bytesPerFrame: UInt32
    ) -> UInt32 {
        let buffers = UnsafeMutableAudioBufferListPointer(
            UnsafeMutablePointer(mutating: inputData)
        )
        guard let firstBuffer = buffers.first,
              firstBuffer.mDataByteSize > 0
        else {
            return 0
        }

        let divisor = max(1, bytesPerFrame)
        return firstBuffer.mDataByteSize / divisor
    }

    private static func duration(
        frames: Int64,
        firstSampleTime: Float64?,
        lastSampleTime: Float64?,
        sampleRate: Double
    ) -> TimeInterval {
        if let firstSampleTime,
           let lastSampleTime,
           sampleRate > 0 {
            return max(0, (lastSampleTime - firstSampleTime) / sampleRate)
        }

        return sampleRate > 0 ? Double(frames) / sampleRate : 0
    }

    private static func mapCoreAudioStartError(_ error: Error) -> RecordingControllerError {
        if let recordingError = error as? RecordingControllerError {
            return recordingError
        }

        return RecordingControllerError.systemAudioSetupFailed(String(describing: error))
    }

    private static func osStatusMessage(_ status: OSStatus, operation: String) -> String {
        guard status != noErr else {
            return "\(operation) succeeded"
        }

        let code = UInt32(bitPattern: status)
        let chars = [
            UInt8((code >> 24) & 0xff),
            UInt8((code >> 16) & 0xff),
            UInt8((code >> 8) & 0xff),
            UInt8(code & 0xff)
        ]
        let fourCC = chars.allSatisfy { $0 >= 32 && $0 <= 126 }
            ? String(bytes: chars, encoding: .macOSRoman)
            : nil
        let suffix = fourCC.map { " '\($0)'" } ?? ""
        return "\(operation) failed with CoreAudio OSStatus \(status)\(suffix)"
    }
}

private extension FileManager {
    func removeItemIfExists(at url: URL) throws {
        let path = url.path(percentEncoded: false)
        if fileExists(atPath: path) {
            try removeItem(at: url)
        }
    }
}
