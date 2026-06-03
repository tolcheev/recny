using System.Reflection;
using System.Text.Json;
using System.Text.Json.Serialization;

namespace ToRec.Windows.Core.Updates;

public sealed record AppUpdateRelease(
    [property: JsonPropertyName("version")] string Version,
    [property: JsonPropertyName("display_version")] string DisplayVersion,
    [property: JsonPropertyName("build")] string? Build,
    [property: JsonPropertyName("release_url")] string ReleaseUrl,
    [property: JsonPropertyName("download_url")] string DownloadUrl,
    [property: JsonPropertyName("sha256_url")] string? Sha256Url,
    [property: JsonPropertyName("notes")] string? Notes);

public sealed record AppUpdateManifest(
    [property: JsonPropertyName("schema_version")] int SchemaVersion,
    [property: JsonPropertyName("generated_at")] string? GeneratedAt,
    [property: JsonPropertyName("macos")] AppUpdateRelease MacOS,
    [property: JsonPropertyName("windows")] AppUpdateRelease Windows);

public sealed record AppUpdateCheckResult(string CurrentVersion, AppUpdateRelease LatestRelease)
{
    public bool IsUpdateAvailable => AppVersion.Parse(CurrentVersion) < AppVersion.Parse(LatestRelease.Version);

    public string DisplayText => IsUpdateAvailable
        ? $"Update available: {LatestRelease.DisplayVersion}"
        : $"You are on the latest version: {LatestRelease.DisplayVersion}";
}

public readonly record struct AppVersion(int Major, int Minor, int Patch, string? Prerelease)
    : IComparable<AppVersion>
{
    public static AppVersion Parse(string rawValue)
    {
        var trimmed = rawValue.Trim();
        if (trimmed.StartsWith("v", StringComparison.OrdinalIgnoreCase))
        {
            trimmed = trimmed[1..];
        }

        var parts = trimmed.Split('-', 2, StringSplitOptions.TrimEntries);
        var numbers = parts[0].Split('.', StringSplitOptions.TrimEntries);

        return new AppVersion(
            ParsePart(numbers, 0),
            ParsePart(numbers, 1),
            ParsePart(numbers, 2),
            parts.Length > 1 ? parts[1] : null);
    }

    public int CompareTo(AppVersion other)
    {
        var major = Major.CompareTo(other.Major);
        if (major != 0)
        {
            return major;
        }

        var minor = Minor.CompareTo(other.Minor);
        if (minor != 0)
        {
            return minor;
        }

        var patch = Patch.CompareTo(other.Patch);
        if (patch != 0)
        {
            return patch;
        }

        if (Prerelease is null && other.Prerelease is null)
        {
            return 0;
        }

        if (Prerelease is null)
        {
            return 1;
        }

        if (other.Prerelease is null)
        {
            return -1;
        }

        return string.Compare(Prerelease, other.Prerelease, StringComparison.OrdinalIgnoreCase);
    }

    public static bool operator <(AppVersion left, AppVersion right) => left.CompareTo(right) < 0;

    public static bool operator >(AppVersion left, AppVersion right) => left.CompareTo(right) > 0;

    private static int ParsePart(string[] numbers, int index)
    {
        return numbers.Length > index && int.TryParse(numbers[index], out var value) ? value : 0;
    }
}

public sealed class AppUpdateChecker
{
    public const string DefaultManifestUrl = "https://raw.githubusercontent.com/tolcheev/torec-releases/main/latest.json";
    public const string CurrentWindowsVersion = "0.2.3-beta";

    private readonly HttpClient _httpClient;
    private readonly string _manifestUrl;

    public AppUpdateChecker(HttpClient? httpClient = null, string manifestUrl = DefaultManifestUrl)
    {
        _httpClient = httpClient ?? new HttpClient();
        _manifestUrl = manifestUrl;
    }

    public async Task<AppUpdateCheckResult> CheckWindowsAsync(CancellationToken cancellationToken = default)
    {
        var json = await _httpClient.GetStringAsync(_manifestUrl, cancellationToken);
        var manifest = DecodeManifest(json);
        return new AppUpdateCheckResult(CurrentWindowsVersion, manifest.Windows);
    }

    public static AppUpdateManifest DecodeManifest(string json)
    {
        var manifest = JsonSerializer.Deserialize<AppUpdateManifest>(
            json,
            new JsonSerializerOptions(JsonSerializerDefaults.Web));

        if (manifest is null)
        {
            throw new InvalidOperationException("Update manifest is empty.");
        }

        if (manifest.SchemaVersion != 1)
        {
            throw new InvalidOperationException($"Unsupported update manifest schema {manifest.SchemaVersion}.");
        }

        return manifest;
    }

    public static string EntryAssemblyDisplayVersion()
    {
        var assembly = Assembly.GetEntryAssembly();
        var informational = assembly?
            .GetCustomAttribute<AssemblyInformationalVersionAttribute>()?
            .InformationalVersion;

        if (!string.IsNullOrWhiteSpace(informational))
        {
            return informational;
        }

        return assembly?.GetName().Version?.ToString() ?? CurrentWindowsVersion;
    }
}
