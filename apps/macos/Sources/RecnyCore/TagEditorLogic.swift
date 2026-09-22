import Foundation

public enum TagEditorLogic {
    public static func resolvedSaveStatus(
        originalStatus: TaggingStatus,
        selectedStatus: TaggingStatus
    ) -> TaggingStatus {
        switch originalStatus {
        case .failed, .shortRecording:
            return originalStatus
        case .needsTagging, .saved, .needsReview, .reviewed:
            return selectedStatus
        }
    }

    public static func isTechnicalStatusLocked(_ status: TaggingStatus) -> Bool {
        switch status {
        case .failed, .shortRecording:
            return true
        case .needsTagging, .saved, .needsReview, .reviewed:
            return false
        }
    }

    public static func toggled(_ tag: String, in tags: [String]) -> [String] {
        let normalized = normalizedTag(tag)
        guard !normalized.isEmpty else {
            return tags
        }

        if tags.contains(normalized) {
            return tags.filter { $0 != normalized }
        }

        return normalizedTags(tags + [normalized])
    }

    public static func normalizedCustomTags(_ value: String) -> [String] {
        let rawTags = value
            .components(separatedBy: CharacterSet(charactersIn: ",;\n\t "))
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }

        return normalizedTags(rawTags)
    }

    public static func normalizedTags(_ tags: [String]) -> [String] {
        var seen = Set<String>()
        return tags.compactMap { rawTag in
            let normalized = normalizedTag(rawTag)
            guard !normalized.isEmpty, seen.insert(normalized).inserted else {
                return nil
            }
            return normalized
        }
    }

    private static func normalizedTag(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return ""
        }

        let withoutHash = trimmed
            .trimmingCharacters(in: CharacterSet(charactersIn: "#"))
            .lowercased()
        guard !withoutHash.isEmpty else {
            return ""
        }

        return "#\(withoutHash)"
    }
}
