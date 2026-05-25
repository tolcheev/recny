import AVFoundation
import SwiftUI
import TOrbitRecorderCore

@MainActor
final class AudioPlayerViewModel: ObservableObject {
    @Published var isPlaying = false
    @Published var currentTime: TimeInterval = 0
    @Published var duration: TimeInterval = 0
    @Published var errorMessage: String?

    let url: URL
    let title: String

    private let player: AVPlayer
    private var timeObserver: Any?

    init(url: URL, title: String, autoplays: Bool = false) {
        self.url = url
        self.title = title.isEmpty ? url.lastPathComponent : title
        self.player = AVPlayer(url: url)
        configureDuration()
        addTimeObserver()
        if autoplays {
            play()
        }
    }

    func togglePlayback() {
        if isPlaying {
            pause()
        } else {
            play()
        }
    }

    func play() {
        player.play()
        isPlaying = true
    }

    func pause() {
        player.pause()
        isPlaying = false
    }

    func seek(to seconds: TimeInterval) {
        let bounded = max(0, min(seconds, duration))
        player.seek(to: CMTime(seconds: bounded, preferredTimescale: 600))
        currentTime = bounded
    }

    func revealInFinder() {
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    private func configureDuration() {
        Task {
            do {
                let asset = AVURLAsset(url: url)
                let loadedDuration = try await asset.load(.duration)
                await MainActor.run {
                    self.duration = max(0, loadedDuration.seconds.isFinite ? loadedDuration.seconds : 0)
                }
            } catch {
                await MainActor.run {
                    self.errorMessage = "Could not read audio duration."
                }
                AppLogger.file(.warning, category: "playback", "duration load failed path=\(url.path(percentEncoded: false)) error=\(String(describing: error))")
            }
        }
    }

    private func addTimeObserver() {
        timeObserver = player.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: 0.2, preferredTimescale: 600),
            queue: .main
        ) { [weak self] time in
            guard let self else {
                return
            }
            Task { @MainActor in
                self.currentTime = max(0, time.seconds.isFinite ? time.seconds : 0)
                if self.duration > 0,
                   self.currentTime >= self.duration - 0.1 {
                    self.isPlaying = false
                }
            }
        }
    }
}

struct AudioPlayerView: View {
    @StateObject private var viewModel: AudioPlayerViewModel

    init(url: URL, title: String) {
        _viewModel = StateObject(wrappedValue: AudioPlayerViewModel(url: url, title: title))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Playback")
                    .font(.title3.weight(.semibold))
                Text(viewModel.title)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            if let errorMessage = viewModel.errorMessage {
                Label(errorMessage, systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }

            HStack(spacing: 12) {
                Button {
                    viewModel.togglePlayback()
                } label: {
                    Label(viewModel.isPlaying ? "Pause" : "Play", systemImage: viewModel.isPlaying ? "pause.fill" : "play.fill")
                }
                .keyboardShortcut(.space, modifiers: [])
                .accessibilityLabel(viewModel.isPlaying ? "Pause recording playback" : "Play recording playback")

                Text(RecordingDisplayFormatter.duration(viewModel.currentTime))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .frame(width: 44, alignment: .trailing)

                Slider(
                    value: Binding(
                        get: { viewModel.currentTime },
                        set: { viewModel.seek(to: $0) }
                    ),
                    in: 0...max(viewModel.duration, 1)
                )
                .accessibilityLabel("Playback position")

                Text(RecordingDisplayFormatter.duration(viewModel.duration))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .frame(width: 44, alignment: .leading)
            }

            HStack {
                Button {
                    viewModel.revealInFinder()
                } label: {
                    Label("Show File", systemImage: "finder")
                }

                Spacer()
            }
        }
        .padding(20)
        .frame(minWidth: 460, idealWidth: 520, minHeight: 160)
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

struct InlineAudioPlayerView: View {
    @StateObject private var viewModel: AudioPlayerViewModel

    init(url: URL, title: String, autoplays: Bool = true) {
        _viewModel = StateObject(wrappedValue: AudioPlayerViewModel(url: url, title: title, autoplays: autoplays))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Button {
                    viewModel.togglePlayback()
                } label: {
                    Label(
                        viewModel.isPlaying ? "Pause" : "Play",
                        systemImage: viewModel.isPlaying ? "pause.fill" : "play.fill"
                    )
                }
                .buttonStyle(.bordered)
                .accessibilityLabel(viewModel.isPlaying ? "Pause inline playback" : "Play inline playback")

                Text(RecordingDisplayFormatter.duration(viewModel.currentTime))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .frame(width: 44, alignment: .trailing)

                Slider(
                    value: Binding(
                        get: { viewModel.currentTime },
                        set: { viewModel.seek(to: $0) }
                    ),
                    in: 0...max(viewModel.duration, 1)
                )
                .accessibilityLabel("Inline playback position")

                Text(RecordingDisplayFormatter.duration(viewModel.duration))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .frame(width: 44, alignment: .leading)

                Button {
                    viewModel.revealInFinder()
                } label: {
                    Image(systemName: "doc.badge.magnifyingglass")
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)
                .help("Reveal audio file")
                .accessibilityLabel("Reveal playback file in Finder")
            }

            if let errorMessage = viewModel.errorMessage {
                Label(errorMessage, systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }
        .padding(.top, 4)
    }
}
