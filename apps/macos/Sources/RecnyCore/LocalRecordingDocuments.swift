import CryptoKit
import Foundation

public enum LocalDocumentError: Error, LocalizedError, Sendable {
    case invalidTranscript, invalidNotes, unsafePath, sourceChanged, missingTranscript, editConflict
    public var errorDescription: String? {
        switch self {
        case .invalidTranscript: "Transcript is empty, malformed, or contains invalid timestamps."
        case .invalidNotes: "The local model returned invalid notes. Existing notes were preserved."
        case .unsafePath: "Recording documents must stay inside the existing recording folder."
        case .sourceChanged: "Audio changed during processing. Retry using the current recording."
        case .missingTranscript: "Transcribe this recording before generating notes."
        case .editConflict: "Notes changed since they were opened. Reload before saving."
        }
    }
}

public enum LocalNotesPreset: String, Codable, CaseIterable, Sendable {
    case meeting, interview, mentoring
    public var title: String {
        switch self { case .meeting: "Meeting"; case .interview: "Interview"; case .mentoring: "Mentoring" }
    }
}

public struct LocalAudioIdentity: Codable, Equatable, Sendable {
    public var filename: String
    public var sha256: String
    public static func read(_ url: URL) throws -> Self {
        let file = try FileHandle(forReadingFrom: url)
        defer { try? file.close() }
        var hash = SHA256()
        while let data = try file.read(upToCount: 1_048_576), !data.isEmpty {
            try Task.checkCancellation()
            hash.update(data: data)
        }
        return Self(filename: url.lastPathComponent, sha256: hash.finalize().map { String(format: "%02x", $0) }.joined())
    }
}

public struct LocalTranscriptSegment: Codable, Identifiable, Equatable, Sendable {
    public let id: String
    public let text: String
    public let start: Double?
    public let end: Double?
    public init(id: String, text: String, start: Double? = nil, end: Double? = nil) {
        self.id = id; self.text = text; self.start = start; self.end = end
    }
}

public struct LocalRecordingTranscript: Codable, Equatable, Sendable {
    public var schemaVersion = 1
    public var source: LocalAudioIdentity?
    public var segments: [LocalTranscriptSegment]
    public init(source: LocalAudioIdentity?, segments: [LocalTranscriptSegment]) {
        self.source = source; self.segments = segments
    }
    public var contentSHA256: String { Self.digest(segments) }
    public static func digest(_ segments: [LocalTranscriptSegment]) -> String {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(segments) else { return "" }
        return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
    public func validate(duration: Double? = nil) throws {
        guard schemaVersion == 1, !segments.isEmpty, segments.count <= 100_000,
              Set(segments.map(\.id)).count == segments.count else { throw LocalDocumentError.invalidTranscript }
        for s in segments {
            guard !s.id.isEmpty, s.id.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "_") }),
                  !s.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, s.text.utf8.count <= 1_000_000,
                  (s.start == nil) == (s.end == nil) else { throw LocalDocumentError.invalidTranscript }
            if let start = s.start, let end = s.end {
                guard start.isFinite, end.isFinite, start >= 0, end >= start,
                      duration == nil || end <= duration! + 0.5 else { throw LocalDocumentError.invalidTranscript }
            }
        }
    }
}

public enum LocalTranscriptParser {
    public static func plainText(_ text: String) throws -> [LocalTranscriptSegment] {
        let paragraphs = text.components(separatedBy: .newlines).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        let result = paragraphs.enumerated().map { LocalTranscriptSegment(id: "s\($0.offset + 1)", text: $0.element) }
        try LocalRecordingTranscript(source: nil, segments: result).validate()
        return result
    }
    public static func srt(_ text: String, duration: Double? = nil) throws -> [LocalTranscriptSegment] {
        let normalized = text.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
        var result: [LocalTranscriptSegment] = []
        for block in normalized.components(separatedBy: "\n\n") {
            let lines = block.split(separator: "\n", omittingEmptySubsequences: true).map(String.init)
            if lines.isEmpty { continue }
            guard lines.count >= 3, Int(lines[0].trimmingCharacters(in: .whitespacesAndNewlines)) != nil else { throw LocalDocumentError.invalidTranscript }
            let times = lines[1].components(separatedBy: " --> ")
            guard times.count == 2, let start = timestamp(times[0]), let end = timestamp(times[1]) else { throw LocalDocumentError.invalidTranscript }
            result.append(.init(id: "s\(result.count + 1)", text: lines.dropFirst(2).joined(separator: " "), start: start, end: end))
        }
        try LocalRecordingTranscript(source: nil, segments: result).validate(duration: duration)
        return result
    }
    private static func timestamp(_ input: String) -> Double? {
        let parts = input.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: ".").split(separator: ":")
        guard parts.count == 3, let hours = Double(parts[0]), let minutes = Double(parts[1]), let seconds = Double(parts[2]),
              hours >= 0, minutes >= 0, minutes < 60, seconds >= 0, seconds < 60 else { return nil }
        return hours * 3600 + minutes * 60 + seconds
    }
}

public struct LocalNoteItem: Codable, Equatable, Sendable {
    public var text: String
    public var sourceIDs: [String]
    public init(text: String, sourceIDs: [String]) { self.text = text; self.sourceIDs = sourceIDs }
}
public struct LocalNoteSection: Codable, Equatable, Sendable {
    public var title: String
    public var items: [LocalNoteItem]
    public init(title: String, items: [LocalNoteItem]) { self.title = title; self.items = items }
}
public struct LocalStructuredNotes: Codable, Equatable, Sendable {
    public var schemaVersion: Int
    public var model: String
    public var revision: String
    public var promptVersion: Int
    public var preset: LocalNotesPreset?
    public var source: LocalAudioIdentity?
    public var transcriptSHA256: String?
    public var sections: [LocalNoteSection]
    public init(model: String, revision: String, preset: LocalNotesPreset, sections: [LocalNoteSection]) {
        schemaVersion = 1; self.model = model; self.revision = revision; promptVersion = 1
        self.preset = preset; self.sections = sections
    }
    public func validate(segments: [LocalTranscriptSegment]) throws {
        let ids = Set(segments.map(\.id))
        guard schemaVersion == 1, promptVersion > 0, !model.isEmpty, !revision.isEmpty,
              !sections.isEmpty, sections.count <= 256 else { throw LocalDocumentError.invalidNotes }
        for section in sections {
            guard !section.title.isEmpty, section.title.count <= 500, section.items.count <= 8_192 else { throw LocalDocumentError.invalidNotes }
            for item in section.items {
                guard !item.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, item.text.count <= 20_000,
                      !item.sourceIDs.isEmpty, item.sourceIDs.count <= ids.count,
                      item.sourceIDs.allSatisfy(ids.contains) else { throw LocalDocumentError.invalidNotes }
            }
        }
    }
    public var markdown: String {
        sections.map { section in
            "## \(section.title)\n\n" + section.items.map { item in
                "- \(item.text) " + item.sourceIDs.map { "[\($0)](recny-segment:\($0))" }.joined(separator: " ")
            }.joined(separator: "\n")
        }.joined(separator: "\n\n") + "\n"
    }
}

public enum LocalDocumentFreshness {
    public static func transcriptIsCurrent(_ transcript: LocalRecordingTranscript?, currentAudio: LocalAudioIdentity?) -> Bool {
        guard let source = transcript?.source, let currentAudio else { return false }
        return source == currentAudio
    }
    public static func referencesAreCurrent(transcript: LocalRecordingTranscript?, notes: LocalStructuredNotes?, currentAudio: LocalAudioIdentity?) -> Bool {
        guard let transcript, let notes, transcriptIsCurrent(transcript, currentAudio: currentAudio),
              notes.source == transcript.source, let digest = notes.transcriptSHA256, !digest.isEmpty else { return false }
        return digest == transcript.contentSHA256
    }
}
