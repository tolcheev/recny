import Foundation

public enum RecordingPaths {
    public static var defaultRoot: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Recordings", isDirectory: true)
            .appendingPathComponent("TOrbitRecorder", isDirectory: true)
    }
}
