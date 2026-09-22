import Foundation

public struct RunningAppInstance: Equatable, Sendable {
    public let processID: Int32
    public let bundlePath: String?

    public init(processID: Int32, bundlePath: String?) {
        self.processID = processID
        self.bundlePath = bundlePath
    }
}

public enum AppInstanceDecision: Equatable, Sendable {
    case continueCurrent
    case terminateCurrentAndActivateExisting(RunningAppInstance)
}

public enum AppInstancePolicy {
    public static func decision(
        currentProcessID: Int32,
        runningInstances: [RunningAppInstance]
    ) -> AppInstanceDecision {
        let otherInstances = runningInstances.filter { $0.processID != currentProcessID }
        guard let preferredExisting = otherInstances.max(by: { priorityScore(for: $0.bundlePath) < priorityScore(for: $1.bundlePath) }) else {
            return .continueCurrent
        }

        return .terminateCurrentAndActivateExisting(preferredExisting)
    }

    public static func userFacingBundlePathList(
        currentProcessID: Int32,
        runningInstances: [RunningAppInstance]
    ) -> [String] {
        runningInstances
            .filter { $0.processID != currentProcessID }
            .compactMap(\.bundlePath)
            .sorted()
    }

    private static func priorityScore(for bundlePath: String?) -> Int {
        guard let bundlePath else {
            return 0
        }

        if bundlePath.hasPrefix("/Applications/Recny.app") {
            return 30
        }

        if bundlePath.contains("/dist/Recny.app") {
            return 20
        }

        if bundlePath.contains("/.build/app/Recny.app") {
            return 10
        }

        return 1
    }
}
