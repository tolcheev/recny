using System.Windows.Forms;
using Recny.Windows.Core.Recording;
using Recny.Windows.Core.Storage;

namespace Recny.Windows;

internal static class Program
{
    [STAThread]
    private static void Main()
    {
        ApplicationConfiguration.Initialize();

        var storageRoot = RecordingPaths.DefaultRoot;
        Directory.CreateDirectory(storageRoot);

        using var logger = new FileLogger(Path.Combine(storageRoot, "logs", "app.log"));
        using var controller = new RecordingController(storageRoot, logger.Write);

        logger.Write("Recny Windows starting");
        Application.Run(new TrayAppContext(controller, storageRoot, logger));
        logger.Write("Recny Windows stopped");
    }
}
