import Testing
@testable import TOrbitRecorderCore

struct DevicePriorityResolverTests {
    @Test
    func externalMicrophonesWinOverBuiltInAndAirPods() throws {
        let devices = [
            MicrophoneInputDevice(id: "airpods", name: "Vlad's AirPods Pro"),
            MicrophoneInputDevice(id: "builtin", name: "MacBook Pro Microphone"),
            MicrophoneInputDevice(id: "shure", name: "Shure MV7")
        ]

        let selection = try #require(DevicePriorityResolver.resolve(devices: devices, preferredDeviceID: nil))

        #expect(selection.device.id == "shure")
        #expect(!selection.isBluetoothFallback)
        #expect(selection.warning == nil)
    }

    @Test
    func builtInWinsOverBluetoothHeadset() throws {
        let devices = [
            MicrophoneInputDevice(id: "airpods", name: "AirPods Max"),
            MicrophoneInputDevice(id: "builtin", name: "Built-in Microphone")
        ]

        let selection = try #require(DevicePriorityResolver.resolve(devices: devices, preferredDeviceID: nil))

        #expect(selection.device.id == "builtin")
        #expect(selection.warning == nil)
    }

    @Test
    func airPodsAndMacBookSelectsMacBookWithAvoidanceReason() throws {
        let devices = [
            MicrophoneInputDevice(id: "airpods", name: "AirPods Pro 2"),
            MicrophoneInputDevice(id: "builtin", name: "MacBook Pro Microphone")
        ]

        let selection = try #require(DevicePriorityResolver.resolve(devices: devices, preferredDeviceID: nil))

        #expect(selection.device.id == "builtin")
        #expect(selection.warning == nil)
        #expect(DevicePriorityResolver.selectionReason(devices: devices, selection: selection, preferredDeviceID: nil) == "AirPods microphone avoided because built-in microphone is available.")
    }

    @Test
    func airPodsAndShureSelectsShure() throws {
        let devices = [
            MicrophoneInputDevice(id: "airpods", name: "AirPods"),
            MicrophoneInputDevice(id: "shure", name: "Shure MV7")
        ]

        let selection = try #require(DevicePriorityResolver.resolve(devices: devices, preferredDeviceID: nil))

        #expect(selection.device.id == "shure")
        #expect(DevicePriorityResolver.selectionReason(devices: devices, selection: selection, preferredDeviceID: nil) == "AirPods microphone avoided because external microphone is available.")
    }

    @Test
    func bluetoothHeadsetIsOnlyFallbackWhenNoOtherInputExists() throws {
        let devices = [
            MicrophoneInputDevice(id: "airpods", name: "AirPods Pro")
        ]

        let selection = try #require(DevicePriorityResolver.resolve(devices: devices, preferredDeviceID: nil))

        #expect(selection.device.id == "airpods")
        #expect(selection.isBluetoothFallback)
        #expect(selection.warning == DevicePriorityResolver.bluetoothFallbackWarning)
        #expect(selection.warning == "Bluetooth microphone is used. Audio quality may be degraded.")
        #expect(DevicePriorityResolver.displayLabel(for: selection.device, recommendedDeviceID: selection.device.id) == "Bluetooth fallback")
    }

    @Test
    func preferredAirPodsAreIgnoredWhenBuiltInExists() throws {
        let devices = [
            MicrophoneInputDevice(id: "airpods", name: "AirPods"),
            MicrophoneInputDevice(id: "builtin", name: "MacBook Pro Microphone")
        ]

        let selection = try #require(DevicePriorityResolver.resolve(devices: devices, preferredDeviceID: "airpods"))

        #expect(selection.device.id == "builtin")
        #expect(selection.warning == nil)
    }

    @Test
    func hollylandWinsOverMacBook() throws {
        let devices = [
            MicrophoneInputDevice(id: "builtin", name: "MacBook Pro Microphone"),
            MicrophoneInputDevice(id: "hollyland", name: "Hollyland Lark M2")
        ]

        let selection = try #require(DevicePriorityResolver.resolve(devices: devices, preferredDeviceID: nil))

        #expect(selection.device.id == "hollyland")
        #expect(DevicePriorityResolver.displayLabel(for: selection.device, recommendedDeviceID: selection.device.id) == "Recommended")
    }

    @Test
    func preferredExternalDeviceIsHonored() throws {
        let devices = [
            MicrophoneInputDevice(id: "usb", name: "USB Microphone"),
            MicrophoneInputDevice(id: "hollyland", name: "Hollyland Lark M2")
        ]

        let selection = try #require(DevicePriorityResolver.resolve(devices: devices, preferredDeviceID: "hollyland"))

        #expect(selection.device.id == "hollyland")
        #expect(DevicePriorityResolver.selectionReason(devices: devices, selection: selection, preferredDeviceID: "hollyland") == "Manual microphone selection is available.")
    }

    @Test
    func missingPreferredExternalFallsBackToBuiltInInsteadOfAirPods() throws {
        let devices = [
            MicrophoneInputDevice(id: "airpods", name: "AirPods Pro 2"),
            MicrophoneInputDevice(id: "builtin", name: "MacBook Pro Microphone")
        ]

        let selection = try #require(DevicePriorityResolver.resolve(devices: devices, preferredDeviceID: "shure"))

        #expect(selection.device.id == "builtin")
        #expect(selection.warning == nil)
        #expect(
            DevicePriorityResolver.selectionReason(
                devices: devices,
                selection: selection,
                preferredDeviceID: "shure"
            ) == "Preferred microphone is unavailable; auto selected the built-in microphone."
        )
    }

    @Test
    func restoreAvoidsOriginalAirPodsWhenBuiltInInputExists() throws {
        let devices = [
            MicrophoneInputDevice(id: "airpods", name: "AirPods Pro 2"),
            MicrophoneInputDevice(id: "builtin", name: "MacBook Pro Microphone")
        ]

        let target = try #require(
            MicrophoneInputRestorePolicy.restoreTarget(
                devices: devices,
                originalDeviceID: "airpods",
                currentSelectedDeviceID: "builtin"
            )
        )

        #expect(target.id == "builtin")
        #expect(
            MicrophoneInputRestorePolicy.restoreReason(
                devices: devices,
                target: target,
                originalDeviceID: "airpods"
            ) == "Original Bluetooth microphone avoided during restore because a non-Bluetooth input is available."
        )
    }

    @Test
    func restoreKeepsOriginalExternalWhenStillAvailable() throws {
        let devices = [
            MicrophoneInputDevice(id: "builtin", name: "MacBook Pro Microphone"),
            MicrophoneInputDevice(id: "shure", name: "Shure MV7")
        ]

        let target = try #require(
            MicrophoneInputRestorePolicy.restoreTarget(
                devices: devices,
                originalDeviceID: "shure",
                currentSelectedDeviceID: "builtin"
            )
        )

        #expect(target.id == "shure")
    }

    @Test
    func restoreUsesBuiltInWhenOriginalExternalWasUnplugged() throws {
        let devices = [
            MicrophoneInputDevice(id: "airpods", name: "AirPods Pro 2"),
            MicrophoneInputDevice(id: "builtin", name: "MacBook Pro Microphone")
        ]

        let target = try #require(
            MicrophoneInputRestorePolicy.restoreTarget(
                devices: devices,
                originalDeviceID: "shure",
                currentSelectedDeviceID: "builtin"
            )
        )

        #expect(target.id == "builtin")
        #expect(
            MicrophoneInputRestorePolicy.restoreReason(
                devices: devices,
                target: target,
                originalDeviceID: "shure"
            ) == "Original microphone is unavailable; restored best available input."
        )
    }

    @Test
    func categorizesBluetoothHandsFreeProfileAsBluetoothFallback() {
        let category = DevicePriorityResolver.category(
            for: MicrophoneInputDevice(id: "hfp", name: "Bluetooth Headset Hands-Free")
        )

        #expect(category == .bluetoothHeadset)
    }

    @Test
    func labelsBuiltInDeviceForSettingsList() {
        let device = MicrophoneInputDevice(id: "builtin", name: "Built-in Microphone")

        #expect(DevicePriorityResolver.displayLabel(for: device, recommendedDeviceID: "shure") == "Built-in")
    }
}
