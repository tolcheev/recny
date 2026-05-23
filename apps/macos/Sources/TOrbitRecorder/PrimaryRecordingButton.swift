import SwiftUI
import TOrbitRecorderCore

struct PrimaryRecordingButton: View {
    let status: RecordingStatus
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: iconName)
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 11)
        }
        .buttonStyle(.borderedProminent)
        .tint(status == .recording ? .red : .accentColor)
        .accessibilityLabel(title)
        .accessibilityHint(accessibilityHint)
    }

    private var title: String {
        status == .recording ? "Stop Recording" : "Start Recording"
    }

    private var iconName: String {
        status == .recording ? "stop.fill" : "record.circle"
    }

    private var accessibilityHint: String {
        status == .recording
            ? "Stops the current audio recording."
            : "Starts a new microphone and system audio recording."
    }
}
