import OSLog

public enum AppLogger {
    public static let subsystem = "com.torbit.recorder"

    public static let app = Logger(subsystem: subsystem, category: "app")
    public static let recording = Logger(subsystem: subsystem, category: "recording")
    public static let storage = Logger(subsystem: subsystem, category: "storage")
}
