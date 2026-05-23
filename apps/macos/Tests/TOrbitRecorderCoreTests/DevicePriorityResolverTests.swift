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
    func bluetoothHeadsetIsOnlyFallbackWhenNoOtherInputExists() throws {
        let devices = [
            MicrophoneInputDevice(id: "airpods", name: "AirPods Pro")
        ]

        let selection = try #require(DevicePriorityResolver.resolve(devices: devices, preferredDeviceID: nil))

        #expect(selection.device.id == "airpods")
        #expect(selection.isBluetoothFallback)
        #expect(selection.warning == DevicePriorityResolver.bluetoothFallbackWarning)
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
    func preferredExternalDeviceIsHonored() throws {
        let devices = [
            MicrophoneInputDevice(id: "usb", name: "USB Microphone"),
            MicrophoneInputDevice(id: "hollyland", name: "Hollyland Lark M2")
        ]

        let selection = try #require(DevicePriorityResolver.resolve(devices: devices, preferredDeviceID: "hollyland"))

        #expect(selection.device.id == "hollyland")
    }

    @Test
    func categorizesBluetoothHandsFreeProfileAsBluetoothFallback() {
        let category = DevicePriorityResolver.category(
            for: MicrophoneInputDevice(id: "hfp", name: "Bluetooth Headset Hands-Free")
        )

        #expect(category == .bluetoothHeadset)
    }
}
