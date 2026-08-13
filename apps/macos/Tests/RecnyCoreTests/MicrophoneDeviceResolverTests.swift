import Testing
@testable import RecnyCore

struct MicrophoneDeviceResolverTests {
    @Test
    func prefersExternalMicrophoneOverBuiltInAndAirPods() throws {
        let devices = [
            MicrophoneInputDevice(id: "airpods", name: "Vlad's AirPods Pro"),
            MicrophoneInputDevice(id: "builtin", name: "MacBook Pro Microphone"),
            MicrophoneInputDevice(id: "shure", name: "Shure MV7")
        ]

        let selection = try #require(MicrophoneDeviceResolver.resolve(devices: devices, preferredDeviceID: nil))

        #expect(selection.device.id == "shure")
        #expect(selection.warning == nil)
        #expect(!selection.isBluetoothFallback)
    }

    @Test
    func usesBuiltInMicrophoneBeforeAirPods() throws {
        let devices = [
            MicrophoneInputDevice(id: "airpods", name: "AirPods Max"),
            MicrophoneInputDevice(id: "builtin", name: "Built-in Microphone")
        ]

        let selection = try #require(MicrophoneDeviceResolver.resolve(devices: devices, preferredDeviceID: nil))

        #expect(selection.device.id == "builtin")
        #expect(selection.warning == nil)
    }

    @Test
    func rejectsAirPodsWhenNoOtherInputExists() {
        let devices = [
            MicrophoneInputDevice(id: "airpods", name: "AirPods Pro")
        ]

        let selection = MicrophoneDeviceResolver.resolve(devices: devices, preferredDeviceID: nil)

        #expect(selection == nil)
    }

    @Test
    func ignoresPreferredAirPodsWhenBuiltInExists() throws {
        let devices = [
            MicrophoneInputDevice(id: "airpods", name: "AirPods"),
            MicrophoneInputDevice(id: "builtin", name: "MacBook Pro Microphone")
        ]

        let selection = try #require(MicrophoneDeviceResolver.resolve(devices: devices, preferredDeviceID: "airpods"))

        #expect(selection.device.id == "builtin")
        #expect(selection.warning == nil)
    }

    @Test
    func rejectsPreferredAirPodsEvenWhenNoOtherInputExists() {
        let devices = [
            MicrophoneInputDevice(id: "airpods", name: "AirPods")
        ]

        let selection = MicrophoneDeviceResolver.resolve(devices: devices, preferredDeviceID: "airpods")

        #expect(selection == nil)
    }

    @Test
    func honorsPreferredExternalMicrophone() throws {
        let devices = [
            MicrophoneInputDevice(id: "usb", name: "USB Microphone"),
            MicrophoneInputDevice(id: "hollyland", name: "Hollyland Lark M2")
        ]

        let selection = try #require(MicrophoneDeviceResolver.resolve(devices: devices, preferredDeviceID: "hollyland"))

        #expect(selection.device.id == "hollyland")
    }
}
