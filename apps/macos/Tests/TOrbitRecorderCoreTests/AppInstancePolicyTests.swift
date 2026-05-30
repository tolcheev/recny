import Testing
@testable import TOrbitRecorderCore

struct AppInstancePolicyTests {
    @Test
    func continuesWhenNoOtherInstanceExists() {
        let decision = AppInstancePolicy.decision(
            currentProcessID: 100,
            runningInstances: [
                RunningAppInstance(processID: 100, bundlePath: "/Applications/ToRec.app")
            ]
        )

        #expect(decision == .continueCurrent)
    }

    @Test
    func terminatesDuplicateAndPrefersApplicationsInstance() {
        let applicationsInstance = RunningAppInstance(
            processID: 200,
            bundlePath: "/Applications/ToRec.app"
        )
        let decision = AppInstancePolicy.decision(
            currentProcessID: 100,
            runningInstances: [
                RunningAppInstance(processID: 100, bundlePath: "/Users/vladislavtolcheev/Projects/t-orbit-recorder/dist/ToRec.app"),
                RunningAppInstance(processID: 300, bundlePath: "/Users/vladislavtolcheev/Projects/t-orbit-recorder/apps/macos/.build/app/ToRec.app"),
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
                RunningAppInstance(processID: 100, bundlePath: "/Applications/ToRec.app"),
                RunningAppInstance(processID: 200, bundlePath: "/tmp/ToRec.app"),
                RunningAppInstance(processID: 300, bundlePath: nil)
            ]
        )

        #expect(paths == ["/tmp/ToRec.app"])
    }
}
