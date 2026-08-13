import Foundation

public enum AppRestartCommand {
    public static func shellCommand(
        currentProcessID: Int32,
        bundlePath: String,
        maxWaitAttempts: Int = 80
    ) -> String {
        let attempts = max(1, maxWaitAttempts)
        let quotedPath = shellQuoted(bundlePath)
        return """
        ( /bin/sleep 0.4; attempts=0; while /bin/kill -0 \(currentProcessID) 2>/dev/null && [ "$attempts" -lt \(attempts) ]; do /bin/sleep 0.1; attempts=$((attempts + 1)); done; /usr/bin/open -n \(quotedPath) ) >/dev/null 2>&1 &
        """
    }

    private static func shellQuoted(_ value: String) -> String {
        "'\(value.replacingOccurrences(of: "'", with: "'\\''"))'"
    }
}

