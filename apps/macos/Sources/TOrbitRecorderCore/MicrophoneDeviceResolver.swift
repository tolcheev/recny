import Foundation

#if canImport(AVFoundation)
import AVFoundation
#endif

#if canImport(CoreAudio)
import CoreAudio
#endif

public struct MicrophoneInputDevice: Codable, Equatable, Identifiable, Sendable {
    public let id: String
    public let name: String

    public init(id: String, name: String) {
        self.id = id
        self.name = name
    }
}

public struct MicrophoneDeviceSelection: Equatable, Sendable {
    public let device: MicrophoneInputDevice
    public let isBluetoothFallback: Bool
    public let warning: String?

    public init(device: MicrophoneInputDevice, isBluetoothFallback: Bool, warning: String?) {
        self.device = device
        self.isBluetoothFallback = isBluetoothFallback
        self.warning = warning
    }
}

public enum DevicePriorityCategory: Int, Sendable {
    case preferredExternal = 0
    case builtIn = 1
    case otherInput = 2
    case bluetoothHeadset = 3
}

public enum DevicePriorityResolver {
    public static let autoRecommendedID = ""
    public static let bluetoothFallbackWarning = "Bluetooth microphone is used. Audio quality may be degraded."

    public static func resolve(
        devices: [MicrophoneInputDevice],
        preferredDeviceID: String?
    ) -> MicrophoneDeviceSelection? {
        let available = devices.filter { !$0.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        guard !available.isEmpty else {
            return nil
        }

        let nonBluetooth = available.filter { !isBluetoothHeadset($0) }
        if let preferredDeviceID,
           !preferredDeviceID.isEmpty,
           let preferred = available.first(where: { $0.id == preferredDeviceID }),
           !isBluetoothHeadset(preferred) || nonBluetooth.isEmpty {
            return selection(for: preferred, hasNonBluetoothAlternative: !nonBluetooth.isEmpty)
        }

        if !nonBluetooth.isEmpty {
            return nonBluetooth
                .sorted(by: sortByPriority)
                .first
                .map { selection(for: $0, hasNonBluetoothAlternative: true) }
        }

        return available
            .sorted(by: sortByPriority)
            .first
            .map { selection(for: $0, hasNonBluetoothAlternative: false) }
    }

    public static func category(for device: MicrophoneInputDevice) -> DevicePriorityCategory {
        if isPreferredExternal(device) {
            return .preferredExternal
        }

        if isBuiltIn(device) {
            return .builtIn
        }

        if isBluetoothHeadset(device) {
            return .bluetoothHeadset
        }

        return .otherInput
    }

    public static func displayLabel(
        for device: MicrophoneInputDevice,
        recommendedDeviceID: String?
    ) -> String {
        if device.id == recommendedDeviceID {
            return category(for: device) == .bluetoothHeadset ? "Bluetooth fallback" : "Recommended"
        }

        switch category(for: device) {
        case .preferredExternal:
            return "Available"
        case .builtIn:
            return "Built-in"
        case .bluetoothHeadset:
            return "Bluetooth fallback"
        case .otherInput:
            return "Available"
        }
    }

    public static func selectionReason(
        devices: [MicrophoneInputDevice],
        selection: MicrophoneDeviceSelection?,
        preferredDeviceID: String?
    ) -> String {
        guard let selection else {
            return "No microphone input devices are available."
        }

        let available = devices.filter { !$0.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        let hasBluetooth = available.contains(where: isBluetoothHeadset)
        let selectedCategory = category(for: selection.device)
        let preferredWasRequested = preferredDeviceID?.isEmpty == false
        let preferredDevice = preferredWasRequested
            ? available.first(where: { $0.id == preferredDeviceID })
            : nil

        if selection.isBluetoothFallback {
            return "Only Bluetooth microphone is available."
        }

        if let preferredDeviceID,
           !preferredDeviceID.isEmpty,
           selection.device.id == preferredDeviceID {
            return "Manual microphone selection is available."
        }

        if preferredWasRequested, preferredDevice == nil {
            switch selectedCategory {
            case .preferredExternal:
                return "Preferred microphone is unavailable; auto selected an external microphone."
            case .builtIn:
                return "Preferred microphone is unavailable; auto selected the built-in microphone."
            case .otherInput:
                return "Preferred microphone is unavailable; auto selected the best available input."
            case .bluetoothHeadset:
                return "Preferred microphone is unavailable; only Bluetooth microphone is available."
            }
        }

        if hasBluetooth, selectedCategory == .preferredExternal {
            return "AirPods microphone avoided because external microphone is available."
        }

        if hasBluetooth, selectedCategory == .builtIn {
            return "AirPods microphone avoided because built-in microphone is available."
        }

        switch selectedCategory {
        case .preferredExternal:
            return "Auto selected the best external microphone."
        case .builtIn:
            return "Auto selected the built-in microphone."
        case .otherInput:
            return "Auto selected the best available input."
        case .bluetoothHeadset:
            return "Only Bluetooth microphone is available."
        }
    }

    public static func isBluetoothHeadset(_ device: MicrophoneInputDevice) -> Bool {
        let name = normalize(device.name)
        return [
            "airpods",
            "airpods pro",
            "airpods max",
            "bluetooth headset",
            "hands-free",
            "handsfree",
            "headset",
            "hfp"
        ].contains { name.contains($0) }
    }

    private static func selection(
        for device: MicrophoneInputDevice,
        hasNonBluetoothAlternative: Bool
    ) -> MicrophoneDeviceSelection {
        let isBluetooth = isBluetoothHeadset(device)
        return MicrophoneDeviceSelection(
            device: device,
            isBluetoothFallback: isBluetooth && !hasNonBluetoothAlternative,
            warning: isBluetooth && !hasNonBluetoothAlternative ? bluetoothFallbackWarning : nil
        )
    }

    private static func sortByPriority(_ lhs: MicrophoneInputDevice, _ rhs: MicrophoneInputDevice) -> Bool {
        let lhsCategory = category(for: lhs)
        let rhsCategory = category(for: rhs)
        if lhsCategory != rhsCategory {
            return lhsCategory.rawValue < rhsCategory.rawValue
        }

        return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
    }

    private static func isPreferredExternal(_ device: MicrophoneInputDevice) -> Bool {
        let name = normalize(device.name)
        if isBuiltIn(device) || isBluetoothHeadset(device) {
            return false
        }

        return [
            "shure",
            "mv7",
            "hollyland",
            "usb",
            "audio interface",
            "interface",
            "external",
            "microphone",
            "mic"
        ].contains { name.contains($0) }
    }

    private static func isBuiltIn(_ device: MicrophoneInputDevice) -> Bool {
        let name = normalize(device.name)
        return name.contains("macbook pro microphone")
            || name.contains("built-in microphone")
            || name.contains("built in microphone")
    }

    private static func normalize(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}

public enum MicrophoneDeviceResolver {
    public static let autoRecommendedID = DevicePriorityResolver.autoRecommendedID
    public static let bluetoothFallbackWarning = DevicePriorityResolver.bluetoothFallbackWarning

    public static func resolve(
        devices: [MicrophoneInputDevice],
        preferredDeviceID: String?
    ) -> MicrophoneDeviceSelection? {
        DevicePriorityResolver.resolve(
            devices: devices,
            preferredDeviceID: preferredDeviceID
        )
    }
}

public enum MicrophoneDeviceProvider {
    public static func availableInputDevices() -> [MicrophoneInputDevice] {
        #if canImport(CoreAudio)
        let coreAudioDevices = CoreAudioInputDeviceOverride.availableInputDevices()
        if !coreAudioDevices.isEmpty {
            return coreAudioDevices
        }
        #endif

        #if canImport(AVFoundation)
        return AVCaptureDevice.DiscoverySession(
            deviceTypes: [.microphone],
            mediaType: .audio,
            position: .unspecified
        )
        .devices
            .map { MicrophoneInputDevice(id: $0.uniqueID, name: $0.localizedName) }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        #else
        return []
        #endif
    }
}

public enum MicrophoneInputRestorePolicy {
    public static func restoreTarget(
        devices: [MicrophoneInputDevice],
        originalDeviceID: String?,
        currentSelectedDeviceID: String?
    ) -> MicrophoneInputDevice? {
        let available = devices.filter { !$0.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        guard !available.isEmpty else {
            return nil
        }

        let hasNonBluetooth = available.contains { !DevicePriorityResolver.isBluetoothHeadset($0) }
        if let originalDeviceID,
           let original = available.first(where: { $0.id == originalDeviceID }),
           !DevicePriorityResolver.isBluetoothHeadset(original) || !hasNonBluetooth {
            return original
        }

        if let currentSelectedDeviceID,
           let currentSelected = available.first(where: { $0.id == currentSelectedDeviceID }),
           !DevicePriorityResolver.isBluetoothHeadset(currentSelected) {
            return currentSelected
        }

        return DevicePriorityResolver.resolve(
            devices: available,
            preferredDeviceID: nil
        )?.device
    }

    public static func restoreReason(
        devices: [MicrophoneInputDevice],
        target: MicrophoneInputDevice?,
        originalDeviceID: String?
    ) -> String {
        guard let target else {
            return "No input device is available for microphone restore."
        }

        let original = originalDeviceID.flatMap { originalID in
            devices.first(where: { $0.id == originalID })
        }

        if let original, original.id == target.id {
            return "Restored original microphone input."
        }

        if let original,
           DevicePriorityResolver.isBluetoothHeadset(original),
           !DevicePriorityResolver.isBluetoothHeadset(target) {
            return "Original Bluetooth microphone avoided during restore because a non-Bluetooth input is available."
        }

        if original == nil, originalDeviceID?.isEmpty == false {
            return "Original microphone is unavailable; restored best available input."
        }

        return "Restored best available microphone input."
    }
}

#if canImport(CoreAudio)
public final class CoreAudioInputDeviceOverride {
    private let originalDeviceID: AudioDeviceID?
    private let selectedDeviceID: AudioDeviceID
    private var didChangeDefaultInput = false

    public init(selectedDeviceUID: String) throws {
        guard let selectedDeviceID = Self.deviceID(forUID: selectedDeviceUID) else {
            throw RecordingControllerError.recorderSetupFailed("Selected microphone device is unavailable")
        }

        self.selectedDeviceID = selectedDeviceID
        self.originalDeviceID = Self.defaultInputDeviceID()

        guard originalDeviceID != selectedDeviceID else {
            return
        }

        try Self.setDefaultInputDeviceID(selectedDeviceID)
        didChangeDefaultInput = true
    }

    deinit {
        restore()
    }

    public func restore() {
        guard didChangeDefaultInput, let originalDeviceID else {
            return
        }

        let devices = Self.availableInputDevices()
        let originalDeviceUID = Self.deviceUID(for: originalDeviceID)
        let currentSelectedDeviceUID = Self.deviceUID(for: selectedDeviceID)
        let target = MicrophoneInputRestorePolicy.restoreTarget(
            devices: devices,
            originalDeviceID: originalDeviceUID,
            currentSelectedDeviceID: currentSelectedDeviceUID
        )
        let targetDeviceID = target.flatMap { Self.deviceID(forUID: $0.id) } ?? originalDeviceID

        do {
            try Self.setDefaultInputDeviceID(targetDeviceID)
            AppLogger.file(
                .info,
                category: "recording",
                "microphone input restore target=\(target?.name ?? "original") reason=\(MicrophoneInputRestorePolicy.restoreReason(devices: devices, target: target, originalDeviceID: originalDeviceUID))"
            )
        } catch {
            AppLogger.file(.warning, category: "recording", "microphone input restore failed error=\(String(describing: error))")
        }
        didChangeDefaultInput = false
    }

    public static func availableInputDevices() -> [MicrophoneInputDevice] {
        allAudioDeviceIDs()
            .compactMap { deviceID -> MicrophoneInputDevice? in
                guard inputChannelCount(for: deviceID) > 0,
                      let uid = deviceUID(for: deviceID),
                      let name = deviceName(for: deviceID),
                      !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                else {
                    return nil
                }

                return MicrophoneInputDevice(id: uid, name: name)
            }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private static func defaultInputDeviceID() -> AudioDeviceID? {
        var deviceID = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        guard AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            &size,
            &deviceID
        ) == noErr, deviceID != 0 else {
            return nil
        }

        return deviceID
    }

    private static func setDefaultInputDeviceID(_ deviceID: AudioDeviceID) throws {
        var mutableDeviceID = deviceID
        let size = UInt32(MemoryLayout<AudioDeviceID>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        let status = AudioObjectSetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            size,
            &mutableDeviceID
        )

        guard status == noErr else {
            throw RecordingControllerError.recorderSetupFailed("Failed to select microphone input device. CoreAudio status=\(status)")
        }
    }

    private static func deviceID(forUID uid: String) -> AudioDeviceID? {
        for deviceID in allAudioDeviceIDs() {
            guard let deviceUID = deviceUID(for: deviceID), deviceUID == uid else {
                continue
            }

            return deviceID
        }

        return nil
    }

    private static func allAudioDeviceIDs() -> [AudioDeviceID] {
        var size: UInt32 = 0
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        guard AudioObjectGetPropertyDataSize(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            &size
        ) == noErr else {
            return []
        }

        let count = Int(size) / MemoryLayout<AudioDeviceID>.size
        var devices = Array(repeating: AudioDeviceID(0), count: count)
        guard AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            &size,
            &devices
        ) == noErr else {
            return []
        }

        return devices
    }

    private static func deviceUID(for deviceID: AudioDeviceID) -> String? {
        cfStringProperty(
            selector: kAudioDevicePropertyDeviceUID,
            deviceID: deviceID
        )
    }

    private static func deviceName(for deviceID: AudioDeviceID) -> String? {
        cfStringProperty(
            selector: kAudioObjectPropertyName,
            deviceID: deviceID
        )
    }

    private static func cfStringProperty(
        selector: AudioObjectPropertySelector,
        deviceID: AudioDeviceID
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
                deviceID,
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

    private static func inputChannelCount(for deviceID: AudioDeviceID) -> Int {
        var size: UInt32 = 0
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreamConfiguration,
            mScope: kAudioDevicePropertyScopeInput,
            mElement: kAudioObjectPropertyElementMain
        )

        guard AudioObjectGetPropertyDataSize(
            deviceID,
            &address,
            0,
            nil,
            &size
        ) == noErr, size > 0 else {
            return 0
        }

        let rawPointer = UnsafeMutableRawPointer.allocate(
            byteCount: Int(size),
            alignment: MemoryLayout<AudioBufferList>.alignment
        )
        defer {
            rawPointer.deallocate()
        }

        let bufferListPointer = rawPointer.bindMemory(to: AudioBufferList.self, capacity: 1)
        guard AudioObjectGetPropertyData(
            deviceID,
            &address,
            0,
            nil,
            &size,
            bufferListPointer
        ) == noErr else {
            return 0
        }

        return UnsafeMutableAudioBufferListPointer(bufferListPointer)
            .reduce(0) { count, buffer in
                count + Int(buffer.mNumberChannels)
            }
    }
}
#endif
