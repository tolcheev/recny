import Foundation

public enum RecordingPaths {
    public static var defaultRoot: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Recordings", isDirectory: true)
            // Keep the historical folder so existing local recordings remain available.
            .appendingPathComponent("TOrbitRecorder", isDirectory: true)
    }
}
