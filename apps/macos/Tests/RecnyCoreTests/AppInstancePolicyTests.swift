import Testing
@testable import RecnyCore

struct AppInstancePolicyTests {
    @Test
    func continuesWhenNoOtherInstanceExists() {
        let decision = AppInstancePolicy.decision(
            currentProcessID: 100,
            runningInstances: [
                RunningAppInstance(processID: 100, bundlePath: "/Applications/Recny.app")
            ]
        )

        #expect(decision == .continueCurrent)
    }

    @Test
    func terminatesDuplicateAndPrefersApplicationsInstance() {
        let applicationsInstance = RunningAppInstance(
            processID: 200,
            bundlePath: "/Applications/Recny.app"
        )
        let decision = AppInstancePolicy.decision(
            currentProcessID: 100,
            runningInstances: [
                RunningAppInstance(processID: 100, bundlePath: "/Users/vladislavtolcheev/Projects/recny/dist/Recny.app"),
                RunningAppInstance(processID: 300, bundlePath: "/Users/vladislavtolcheev/Projects/recny/apps/macos/.build/app/Recny.app"),
                applicationsInstance
            ]
        )

        #expect(decision == .terminateCurrentAndActivateExisting(applicationsInstance))
    }

    @Test
    func exposesDuplicateBundlePathsForUserMessage() {
        let paths = AppInstancePolicy.userFacingBundlePathList(
            currentProcessID: 100,
            runningInstances: [
                RunningAppInstance(processID: 100, bundlePath: "/Applications/Recny.app"),
                RunningAppInstance(processID: 200, bundlePath: "/tmp/Recny.app"),
                RunningAppInstance(processID: 300, bundlePath: nil)
            ]
        )

        #expect(paths == ["/tmp/Recny.app"])
    }
}
