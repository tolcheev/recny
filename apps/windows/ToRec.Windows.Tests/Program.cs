using ToRec.Windows.Core.Recording;
using ToRec.Windows.Core.Storage;

namespace ToRec.Windows.Tests;

internal static class Program
{
    private static int Main()
    {
        var tests = new (string Name, Action Run)[]
        {
            ("recording paths create expected layout", RecordingPathsCreateExpectedLayout),
            ("metadata writer persists json", MetadataWriterPersistsJson),
            ("recording scanner sorts newest first", RecordingScannerSortsNewestFirst)
        };

        foreach (var test in tests)
        {
            try
            {
                test.Run();
                Console.WriteLine($"PASS {test.Name}");
            }
            catch (Exception ex)
            {
                Console.Error.WriteLine($"FAIL {test.Name}: {ex}");
                return 1;
            }
        }

        return 0;
    }

    private static void RecordingPathsCreateExpectedLayout()
    {
        var root = TempRoot();
        var startedAt = new DateTimeOffset(2026, 5, 31, 16, 30, 0, TimeSpan.Zero);
        var session = RecordingPaths.CreateSession(root, startedAt);

        Assert(session.SessionDirectory.StartsWith(Path.Combine(root, "Library", "2026", "05")));
        Assert(session.MicWavPath.EndsWith(Path.Combine("source", "mic.wav")));
        Assert(session.SystemWavPath.EndsWith(Path.Combine("source", "system.wav")));
        Assert(session.MixedWavPath.EndsWith(Path.Combine("export", "mixed.wav")));
        Assert(session.MetadataPath.EndsWith("metadata.json"));
    }

    private static void MetadataWriterPersistsJson()
    {
        var root = TempRoot();
        var session = RecordingPaths.CreateSession(root, DateTimeOffset.UtcNow);
        Directory.CreateDirectory(session.SourceDirectory);
        Directory.CreateDirectory(session.ExportDirectory);
        File.WriteAllText(session.MicWavPath, "mic");
        File.WriteAllText(session.SystemWavPath, "system");
        File.WriteAllText(session.MixedWavPath, "mixed");

        var result = new AudioPostProcessResult
        {
            MixedWavCreated = true
        };
        var metadata = RecordingMetadataFactory.Create(
            session,
            session.StartedAt.AddMinutes(3),
            TimeSpan.FromMinutes(3),
            "completed",
            result,
            null);

        MetadataWriter.Write(session.MetadataPath, metadata);
        var read = MetadataWriter.Read(session.MetadataPath);

        Assert(read.Id == session.Id);
        Assert(read.Status == "completed");
        Assert(read.Files.MicWav == "source/mic.wav");
        Assert(read.Files.SystemWav == "source/system.wav");
        Assert(read.Files.MixedWav == "export/mixed.wav");
    }

    private static void RecordingScannerSortsNewestFirst()
    {
        var root = TempRoot();
        var older = WriteMetadata(root, new DateTimeOffset(2026, 5, 30, 10, 0, 0, TimeSpan.Zero));
        var newer = WriteMetadata(root, new DateTimeOffset(2026, 5, 31, 10, 0, 0, TimeSpan.Zero));

        var recordings = RecordingScanner.Scan(root);

        Assert(recordings.Count == 2);
        Assert(recordings[0].Id == newer.Id);
        Assert(recordings[1].Id == older.Id);
    }

    private static RecordingSession WriteMetadata(string root, DateTimeOffset startedAt)
    {
        var session = RecordingPaths.CreateSession(root, startedAt);
        Directory.CreateDirectory(session.SourceDirectory);
        Directory.CreateDirectory(session.ExportDirectory);
        File.WriteAllText(session.MicWavPath, "mic");
        File.WriteAllText(session.SystemWavPath, "system");
        File.WriteAllText(session.MixedWavPath, "mixed");
        var metadata = RecordingMetadataFactory.Create(
            session,
            startedAt.AddMinutes(1),
            TimeSpan.FromMinutes(1),
            "completed",
            new AudioPostProcessResult { MixedWavCreated = true },
            null);
        MetadataWriter.Write(session.MetadataPath, metadata);
        return session;
    }

    private static string TempRoot()
    {
        var path = Path.Combine(Path.GetTempPath(), "torec-windows-tests", Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(path);
        return path;
    }

    private static void Assert(bool condition)
    {
        if (!condition)
        {
            throw new InvalidOperationException("Assertion failed.");
        }
    }
}
