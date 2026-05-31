namespace ToRec.Windows;

public sealed class FileLogger : IDisposable
{
    private readonly string _path;
    private readonly object _sync = new();

    public FileLogger(string path)
    {
        _path = path;
        Directory.CreateDirectory(Path.GetDirectoryName(path)!);
    }

    public void Write(string message)
    {
        var line = $"{DateTimeOffset.Now:O} {message}{Environment.NewLine}";
        lock (_sync)
        {
            File.AppendAllText(_path, line);
        }
    }

    public void Dispose()
    {
    }
}
