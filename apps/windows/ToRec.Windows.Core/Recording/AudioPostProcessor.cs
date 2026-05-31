using NAudio.MediaFoundation;
using NAudio.Wave;
using NAudio.Wave.SampleProviders;

namespace ToRec.Windows.Core.Recording;

public static class AudioPostProcessor
{
    public static AudioPostProcessResult Process(RecordingSession session, Action<string> log)
    {
        var warnings = new List<string>();

        var mixedWavCreated = TryCreateMixedWav(session.MicWavPath, session.SystemWavPath, session.MixedWavPath, warnings, log);
        var micM4ACreated = TryEncodeAac(session.MicWavPath, session.MicM4APath, warnings, log);
        var systemM4ACreated = TryEncodeAac(session.SystemWavPath, session.SystemM4APath, warnings, log);
        var mixedM4ACreated = mixedWavCreated && TryEncodeAac(session.MixedWavPath, session.MixedM4APath, warnings, log);

        var result = new AudioPostProcessResult
        {
            MixedWavCreated = mixedWavCreated,
            MicM4ACreated = micM4ACreated,
            SystemM4ACreated = systemM4ACreated,
            MixedM4ACreated = mixedM4ACreated
        };
        result.Warnings.AddRange(warnings);
        return result;
    }

    private static bool TryCreateMixedWav(
        string micPath,
        string systemPath,
        string outputPath,
        ICollection<string> warnings,
        Action<string> log)
    {
        if (!File.Exists(micPath) || !File.Exists(systemPath))
        {
            warnings.Add("Cannot create mixed.wav because one or more source WAV files are missing.");
            return false;
        }

        try
        {
            Directory.CreateDirectory(Path.GetDirectoryName(outputPath)!);

            using var micReader = new AudioFileReader(micPath);
            using var systemReader = new AudioFileReader(systemPath);

            var targetFormat = WaveFormat.CreateIeeeFloatWaveFormat(48_000, 2);
            var mixer = new MixingSampleProvider(targetFormat)
            {
                ReadFully = false
            };

            mixer.AddMixerInput(ConvertToTargetFormat(micReader, targetFormat));
            mixer.AddMixerInput(ConvertToTargetFormat(systemReader, targetFormat));

            WaveFileWriter.CreateWaveFile16(outputPath, mixer);
            log($"mixed wav created path={outputPath}");
            return true;
        }
        catch (Exception ex)
        {
            var message = $"mixed wav failed: {ex.Message}";
            warnings.Add(message);
            log(message);
            return false;
        }
    }

    private static ISampleProvider ConvertToTargetFormat(ISampleProvider source, WaveFormat targetFormat)
    {
        ISampleProvider converted = source;

        if (converted.WaveFormat.Channels == 1 && targetFormat.Channels == 2)
        {
            converted = new MonoToStereoSampleProvider(converted);
        }
        else if (converted.WaveFormat.Channels == 2 && targetFormat.Channels == 1)
        {
            converted = new StereoToMonoSampleProvider(converted);
        }
        else if (converted.WaveFormat.Channels != targetFormat.Channels)
        {
            throw new InvalidOperationException($"Unsupported channel conversion from {converted.WaveFormat.Channels} to {targetFormat.Channels}.");
        }

        if (converted.WaveFormat.SampleRate != targetFormat.SampleRate)
        {
            converted = new WdlResamplingSampleProvider(converted, targetFormat.SampleRate);
        }

        return converted;
    }

    private static bool TryEncodeAac(string inputPath, string outputPath, ICollection<string> warnings, Action<string> log)
    {
        if (!File.Exists(inputPath))
        {
            warnings.Add($"Cannot encode missing file: {Path.GetFileName(inputPath)}.");
            return false;
        }

        try
        {
            Directory.CreateDirectory(Path.GetDirectoryName(outputPath)!);
            MediaFoundationApi.Startup();
            using var reader = new AudioFileReader(inputPath);
            MediaFoundationEncoder.EncodeToAac(reader, outputPath, 128_000);
            log($"aac encoded path={outputPath}");
            return File.Exists(outputPath);
        }
        catch (Exception ex)
        {
            var message = $"aac encode failed for {Path.GetFileName(inputPath)}: {ex.Message}";
            warnings.Add(message);
            log(message);
            return false;
        }
    }
}
