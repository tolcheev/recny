import SwiftUI
import TOrbitRecorderCore

enum StatusTone {
    case neutral
    case ready
    case recording
    case warning
    case danger

    var color: Color {
        switch self {
        case .neutral:
            return .secondary
        case .ready:
            return .green
        case .recording:
            return .red
        case .warning:
            return .orange
        case .danger:
            return .red
        }
    }

    var background: Color {
        color.opacity(0.12)
    }
}

struct StatusBadge: View {
    let text: String
    let tone: StatusTone

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(tone.color)
                .frame(width: 7, height: 7)

            Text(text)
                .font(.caption.weight(.medium))
                .lineLimit(1)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 5)
        .background(tone.background, in: Capsule())
        .foregroundStyle(tone.color)
        .accessibilityLabel(text)
    }
}

struct RecorderCard<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            content
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color(nsColor: .separatorColor).opacity(0.32), lineWidth: 1)
        )
    }
}

struct InfoRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(label)
                .font(.callout.weight(.medium))
                .foregroundStyle(.secondary)
                .frame(width: 92, alignment: .leading)

            Text(value)
                .font(.callout)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label), \(value)")
    }
}

func tone(for status: TaggingStatus) -> StatusTone {
    switch status {
    case .failed:
        return .danger
    case .shortRecording, .needsTagging, .needsReview:
        return .warning
    default:
        return .ready
    }
}
