using System.Drawing;

namespace Recny.Windows;

internal static class TrayIconFactory
{
    public static Icon Create(bool recording, bool updateAvailable = false)
    {
        var bitmap = new Bitmap(32, 32);
        using var graphics = Graphics.FromImage(bitmap);
        graphics.Clear(Color.Transparent);
        graphics.SmoothingMode = System.Drawing.Drawing2D.SmoothingMode.AntiAlias;

        if (recording)
        {
            using var brush = new SolidBrush(Color.FromArgb(220, 28, 28));
            graphics.FillEllipse(brush, 7, 7, 18, 18);
        }
        else
        {
            using var pen = new Pen(Color.White, 4)
            {
                StartCap = System.Drawing.Drawing2D.LineCap.Round,
                EndCap = System.Drawing.Drawing2D.LineCap.Round,
                LineJoin = System.Drawing.Drawing2D.LineJoin.Round
            };
            var points = new[]
            {
                new Point(11, 8),
                new Point(22, 16),
                new Point(11, 24)
            };
            graphics.DrawLines(pen, points);

            if (updateAvailable)
            {
                using var brush = new SolidBrush(Color.FromArgb(0, 122, 255));
                graphics.FillEllipse(brush, 22, 5, 7, 7);
            }
        }

        var handle = bitmap.GetHicon();
        return Icon.FromHandle(handle);
    }
}
