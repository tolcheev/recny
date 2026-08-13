import Foundation

public struct RecordingMetadataCodec: Sendable {
    public init() {}

    public func encode(_ metadata: RecordingMetadata) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(metadata)
    }

    public func decode(_ data: Data) throws -> RecordingMetadata {
        try JSONDecoder().decode(RecordingMetadata.self, from: data)
    }

    public func write(_ metadata: RecordingMetadata, to url: URL) throws {
        let data = try encode(metadata)
        try data.write(to: url, options: [.atomic])
    }

    public func read(from url: URL) throws -> RecordingMetadata {
        let data = try Data(contentsOf: url)
        return try decode(data)
    }
}
