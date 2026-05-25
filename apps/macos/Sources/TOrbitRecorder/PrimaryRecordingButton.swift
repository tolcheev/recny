import SwiftUI
import TOrbitRecorderCore

struct PrimaryRecordingButton: View {
    let status: RecordingStatus
    var isBusy = false
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
        .disabled(isBusy)
        .accessibilityLabel(title)
        .accessibilityHint(accessibilityHint)
    }

    private var title: String {
        if status == .recording, isBusy {
            return "Stopping..."
        }

        return status == .recording ? "Stop Recording" : "Start Recording"
    }

    private var iconName: String {
        if status == .recording, isBusy {
            return "hourglass"
        }

        return status == .recording ? "stop.fill" : "record.circle"
    }

    private var accessibilityHint: String {
        if status == .recording, isBusy {
            return "Finalizing the current audio recording."
        }

        return status == .recording
            ? "Stops the current audio recording."
            : "Starts a new microphone and system audio recording."
    }
}
