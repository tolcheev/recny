import Foundation
import Testing
@testable import TOrbitRecorderCore

struct RecordingMarkerTests {
    @Test
    func markerFactoryStoresElapsedSecondsAndQuickTag() {
        let createdAt = Date(timeIntervalSince1970: 1_716_468_123.456)

        let marker = RecordingMarker.make(
            kind: .objection,
            elapsedTime: 123.8,
            createdAt: createdAt,
            id: "marker-test"
        )

        #expect(marker.id == "marker-test")
        #expect(marker.timeSec == 123)
        #expect(marker.label == "Objection")
        #expect(marker.tags == ["objection"])
        #expect(marker.createdAt.hasPrefix("2024-05-23T"))
    }

    @Test
    func markerFactoryClampsNegativeElapsedTime() {
        let marker = RecordingMarker.make(
            kind: .badAudio,
            elapsedTime: -4,
            createdAt: Date(timeIntervalSince1970: 1_716_468_000),
            id: "marker-negative"
        )

        #expect(marker.timeSec == 0)
        #expect(marker.label == "Bad audio")
        #expect(marker.tags == ["bad_audio"])
    }

    @Test
    func oldMetadataDefaultsToNoMarkers() throws {
        let json = """
        {
          "id": "rec_old",
          "started_at": "2024-05-23T12:00:00.000Z",
          "ended_at": "2024-05-23T12:01:00.000Z"
        }
        """

        let metadata = try JSONDecoder().decode(
            RecordingMetadata.self,
            from: Data(json.utf8)
        )

        #expect(metadata.markers.isEmpty)
    }
}
