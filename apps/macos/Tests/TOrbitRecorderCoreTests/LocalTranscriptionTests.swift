import Foundation
import Testing
@testable import TOrbitRecorderCore

struct LocalTranscriptionTests {
    @Test
    func artifactPathsStayInsideRecordingFolder() {
        let sessionFolder = URL(fileURLWithPath: "/tmp/rec", isDirectory: true)

        let paths = LocalTranscriptionArtifactPaths(sessionFolderURL: sessionFolder)

        #expect(paths.folderURL.lastPathComponent == "transcript")
        #expect(paths.textURL.path(percentEncoded: false) == "/tmp/rec/transcript/transcript.txt")
        #expect(paths.noteMarkdownURL.path(percentEncoded: false) == "/tmp/rec/transcript/call_note.md")
    }

    @Test
    func noteMarkdownContainsReviewPromptAndTranscript() {
        let recording = RecordingSummary(
            id: "rec_2026-05-28_14-33-35_65f8bc87",
            title: "Untitled recording",
            category: "unsorted",
            participant: "Ivan",
            tags: ["#скрининг"],
            status: .needsTagging,
            sourceApp: "Zoom",
            startedAt: "2026-05-28T14:33:35.338Z",
            endedAt: "2026-05-28T14:40:32.703Z",
            durationSec: 417,
            metadataURL: URL(fileURLWithPath: "/tmp/rec/metadata.json"),
            sessionFolderURL: URL(fileURLWithPath: "/tmp/rec", isDirectory: true)
        )

        let markdown = LocalTranscriptionNoteFormatter.markdown(
            recording: recording,
            provider: .parakeetMLX,
            audioURL: URL(fileURLWithPath: "/tmp/rec/export/mixed_balanced.m4a"),
            transcriptText: "Здравствуйте. Обсудили условия и следующий шаг.",
            generatedAt: Date(timeIntervalSince1970: 1_779_969_600)
        )

        #expect(markdown.contains("# Call Note"))
        #expect(markdown.contains("Provider: parakeet-mlx"))
        #expect(markdown.contains("Source: Zoom"))
        #expect(markdown.contains("Participant: Ivan"))
        #expect(markdown.contains("Tags: #скрининг"))
        #expect(markdown.contains("## Codex Review Prompt"))
        #expect(markdown.contains("ЖОСКО"))
        #expect(markdown.contains("Здравствуйте. Обсудили условия и следующий шаг."))
    }

    @Test
    func parakeetInstallHintMentionsRequiredTools() {
        #expect(LocalTranscriptionError.noLocalTranscriptionToolInstalled.description.contains("brew install uv ffmpeg"))
        #expect(LocalTranscriptionError.parakeetMLXNotInstalled.description.contains("uv tool install parakeet-mlx -U"))
        #expect(LocalTranscriptionError.whisperKitCLINotInstalled.description.contains("brew install whisperkit-cli"))
        #expect(LocalTranscriptionError.ffmpegNotInstalled.description.contains("brew install ffmpeg"))
        #expect(LocalTranscriptionError.modelNotPrepared.description.contains("Settings -> Local Transcription"))
    }

    @Test
    func setupStatusRequiresToolsBeforeModelDownload() throws {
        let root = try temporaryDirectory()
        let home = root.appendingPathComponent("home", isDirectory: true)
        let bin = root.appendingPathComponent("bin", isDirectory: true)
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: bin, withIntermediateDirectories: true)

        let status = LocalTranscriptionSetupInspector.status(
            environment: [
                "HOME": home.path(percentEncoded: false),
                "PATH": bin.path(percentEncoded: false)
            ]
        )

        if case .missingTools(let tools) = status {
            #expect(tools.contains("parakeet-mlx"))
        } else {
            Issue.record("Expected missing local transcription tools before model preparation.")
        }
        #expect(!status.canTranscribeWithoutSetup)
    }

    @Test
    func setupStatusRequiresCachedParakeetModelBeforeRecordsCanTranscribe() throws {
        let root = try temporaryDirectory()
        let home = root.appendingPathComponent("home", isDirectory: true)
        let bin = root.appendingPathComponent("bin", isDirectory: true)
        try FileManager.default.createDirectory(at: bin, withIntermediateDirectories: true)
        try makeExecutable(named: "parakeet-mlx", in: bin)
        try makeExecutable(named: "ffmpeg", in: bin)

        let environment = [
            "HOME": home.path(percentEncoded: false),
            "PATH": bin.path(percentEncoded: false)
        ]

        #expect(LocalTranscriptionSetupInspector.status(environment: environment) == .needsModelDownload)

        let snapshot = home
            .appendingPathComponent(".cache/huggingface/hub/models--mlx-community--parakeet-tdt-0.6b-v3/snapshots/abc", isDirectory: true)
        try FileManager.default.createDirectory(at: snapshot, withIntermediateDirectories: true)
        try Data("{}".utf8).write(to: snapshot.appendingPathComponent("config.json"))
        try Data(repeating: 1, count: 4).write(to: snapshot.appendingPathComponent("model.safetensors"))

        #expect(LocalTranscriptionSetupInspector.status(environment: environment) == .ready(.parakeetMLX))
        #expect(LocalTranscriptionSetupInspector.status(environment: environment).canTranscribeWithoutSetup)
    }

    @Test
    func transcribeDoesNotDownloadModelFromRecordsWhenSetupIsIncomplete() async throws {
        let root = try temporaryDirectory()
        let home = root.appendingPathComponent("home", isDirectory: true)
        let bin = root.appendingPathComponent("bin", isDirectory: true)
        try FileManager.default.createDirectory(at: bin, withIntermediateDirectories: true)
        try makeExecutable(named: "parakeet-mlx", in: bin)
        try makeExecutable(named: "ffmpeg", in: bin)
        let audioURL = root.appendingPathComponent("mixed.m4a")
        try Data(repeating: 1, count: 4).write(to: audioURL)
        let recording = RecordingSummary(
            id: "rec",
            title: "Recording",
            category: "unsorted",
            participant: "",
            tags: [],
            status: .needsTagging,
            sourceApp: "Zoom",
            startedAt: "2026-05-29T10:00:00Z",
            endedAt: "2026-05-29T10:01:00Z",
            durationSec: 60,
            metadataURL: root.appendingPathComponent("metadata.json"),
            sessionFolderURL: root
        )
        let runner = LocalTranscriptionRunner(
            environment: [
                "HOME": home.path(percentEncoded: false),
                "PATH": bin.path(percentEncoded: false)
            ]
        )

        do {
            _ = try await runner.transcribe(recording: recording, audioURL: audioURL)
            Issue.record("Expected transcription to require Settings preparation first.")
        } catch LocalTranscriptionError.modelNotPrepared {
        }
    }

    private func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("torbit-local-transcription-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func makeExecutable(named name: String, in directory: URL) throws {
        let url = directory.appendingPathComponent(name)
        try Data("#!/bin/sh\nexit 0\n".utf8).write(to: url)
        try FileManager.default.setAttributes(
            [.posixPermissions: NSNumber(value: Int16(0o755))],
            ofItemAtPath: url.path(percentEncoded: false)
        )
    }
}
