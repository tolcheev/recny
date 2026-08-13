import Foundation

public enum LibraryRecordingFilter {
    public static func matches(
        _ recording: RecordingSummary,
        query: String = "",
        dateFromText: String = "",
        dateToText: String = ""
    ) -> Bool {
        matchesQuery(recording, query: query)
            && matchesDateRange(recording, fromText: dateFromText, toText: dateToText)
    }

    public static func matchesAudioHealth(
        _ status: AudioHealthStatus,
        selectedStatus: AudioHealthStatus?
    ) -> Bool {
        guard let selectedStatus else {
            return true
        }

        return status == selectedStatus
    }

    private static func matchesQuery(_ recording: RecordingSummary, query: String) -> Bool {
        let tokens = query
            .split(whereSeparator: { $0.isWhitespace })
            .map { $0.lowercased() }

        guard !tokens.isEmpty else {
            return true
        }

        let haystack = [
            recording.title,
            recording.participant,
            recording.sourceApp,
            recording.category,
            recording.tags.joined(separator: " ")
        ]
        .joined(separator: " ")
        .lowercased()

        return tokens.allSatisfy { haystack.contains($0) }
    }

    private static func matchesDateRange(
        _ recording: RecordingSummary,
        fromText: String,
        toText: String
    ) -> Bool {
        let trimmedFrom = fromText.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedTo = toText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedFrom.isEmpty || !trimmedTo.isEmpty else {
            return true
        }

        guard let startedAt = parseISO8601(recording.startedAt) else {
            return false
        }

        if let from = parseDay(trimmedFrom), startedAt < from {
            return false
        }

        if let to = parseDay(trimmedTo).map(endOfDay), startedAt > to {
            return false
        }

        return true
    }

    private static func parseISO8601(_ value: String) -> Date? {
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = fractional.date(from: value) {
            return date
        }

        return ISO8601DateFormatter().date(from: value)
    }

    private static func parseDay(_ value: String) -> Date? {
        guard !value.isEmpty else {
            return nil
        }

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.date(from: value)
    }

    private static func endOfDay(_ date: Date) -> Date {
        date.addingTimeInterval(86_400 - 0.001)
    }
}
