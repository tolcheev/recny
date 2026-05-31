using System.Windows.Forms;
using ToRec.Windows.Core.Recording;
using ToRec.Windows.Core.Storage;

namespace ToRec.Windows;

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

        logger.Write("ToRec Windows starting");
        Application.Run(new TrayAppContext(controller, storageRoot, logger));
        logger.Write("ToRec Windows stopped");
    }
}
