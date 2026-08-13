import Testing
@testable import RecnyCore

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
    func builtInWinsOverVirtualMeetingAudioDevices() throws {
        let devices = [
            MicrophoneInputDevice(id: "teams", name: "Microsoft Teams Audio"),
            MicrophoneInputDevice(id: "zoom", name: "ZoomAudioDevice"),
            MicrophoneInputDevice(id: "builtin", name: "MacBook Pro Microphone")
        ]

        let selection = try #require(DevicePriorityResolver.resolve(devices: devices, preferredDeviceID: nil))

        #expect(selection.device.id == "builtin")
        #expect(selection.warning == nil)
        #expect(DevicePriorityResolver.displayLabel(for: devices[0], recommendedDeviceID: nil) == "Blocked")
        #expect(DevicePriorityResolver.displayLabel(for: devices[1], recommendedDeviceID: nil) == "Blocked")
        #expect(
            DevicePriorityResolver.selectionReason(
                devices: devices,
                selection: selection,
                preferredDeviceID: nil
            ) == "Virtual meeting microphone avoided because built-in microphone is available."
        )
    }

    @Test
    func preferredVirtualMeetingAudioDeviceIsIgnoredWhenBuiltInExists() throws {
        let devices = [
            MicrophoneInputDevice(id: "teams", name: "Microsoft Teams Audio"),
            MicrophoneInputDevice(id: "builtin", name: "Built-in Microphone")
        ]

        let selection = try #require(DevicePriorityResolver.resolve(devices: devices, preferredDeviceID: "teams"))

        #expect(selection.device.id == "builtin")
        #expect(selection.warning == nil)
        #expect(DevicePriorityResolver.isBlockedInput(devices[0]))
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
    func bluetoothHeadsetIsRejectedWhenNoOtherInputExists() {
        let devices = [
            MicrophoneInputDevice(id: "airpods", name: "AirPods Pro")
        ]

        let selection = DevicePriorityResolver.resolve(devices: devices, preferredDeviceID: nil)

        #expect(selection == nil)
        #expect(
            DevicePriorityResolver.selectionReason(
                devices: devices,
                selection: selection,
                preferredDeviceID: nil
            ) == "AirPods/Bluetooth microphone is blocked for recording. Connect the MacBook or USB microphone."
        )
        #expect(DevicePriorityResolver.displayLabel(for: devices[0], recommendedDeviceID: nil) == "Blocked")
    }

    @Test
    func virtualMeetingAudioDeviceIsRejectedWhenNoOtherInputExists() {
        let devices = [
            MicrophoneInputDevice(id: "teams", name: "Microsoft Teams Audio")
        ]

        let selection = DevicePriorityResolver.resolve(devices: devices, preferredDeviceID: nil)

        #expect(selection == nil)
        #expect(
            DevicePriorityResolver.selectionReason(
                devices: devices,
                selection: selection,
                preferredDeviceID: nil
            ) == DevicePriorityResolver.virtualInputBlockedWarning
        )
        #expect(DevicePriorityResolver.displayLabel(for: devices[0], recommendedDeviceID: nil) == "Blocked")
    }

    @Test
    func preferredAirPodsAreRejectedEvenWhenNoOtherInputExists() {
        let devices = [
            MicrophoneInputDevice(id: "airpods", name: "AirPods")
        ]

        let selection = DevicePriorityResolver.resolve(devices: devices, preferredDeviceID: "airpods")

        #expect(selection == nil)
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
    func restoreDoesNotTargetAirPodsWhenNoNonBluetoothInputExists() {
        let devices = [
            MicrophoneInputDevice(id: "airpods", name: "AirPods Pro 2")
        ]

        let target = MicrophoneInputRestorePolicy.restoreTarget(
            devices: devices,
            originalDeviceID: "airpods",
            currentSelectedDeviceID: nil
        )

        #expect(target == nil)
        #expect(
            MicrophoneInputRestorePolicy.restoreReason(
                devices: devices,
                target: target,
                originalDeviceID: "airpods"
            ) == "No non-Bluetooth microphone input is available for restore."
        )
    }

    @Test
    func restoreDoesNotTargetVirtualMeetingAudioDeviceWhenBuiltInExists() throws {
        let devices = [
            MicrophoneInputDevice(id: "teams", name: "Microsoft Teams Audio"),
            MicrophoneInputDevice(id: "builtin", name: "MacBook Pro Microphone")
        ]

        let target = try #require(
            MicrophoneInputRestorePolicy.restoreTarget(
                devices: devices,
                originalDeviceID: "teams",
                currentSelectedDeviceID: "teams"
            )
        )

        #expect(target.id == "builtin")
        #expect(
            MicrophoneInputRestorePolicy.restoreReason(
                devices: devices,
                target: target,
                originalDeviceID: "teams"
            ) == "Original virtual meeting microphone avoided during restore because a non-virtual input is available."
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
    func categorizesTeamsAudioAsBlockedVirtualInput() {
        let category = DevicePriorityResolver.category(
            for: MicrophoneInputDevice(id: "teams", name: "Microsoft Teams Audio")
        )

        #expect(category == .virtualMeetingInput)
    }

    @Test
    func labelsBuiltInDeviceForSettingsList() {
        let device = MicrophoneInputDevice(id: "builtin", name: "Built-in Microphone")

        #expect(DevicePriorityResolver.displayLabel(for: device, recommendedDeviceID: "shure") == "Built-in")
    }
}
