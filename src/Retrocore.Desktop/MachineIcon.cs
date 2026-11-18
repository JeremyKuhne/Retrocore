// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using Avalonia.Controls;
using Avalonia.Controls.Shapes;
using Avalonia.Media;
using Path = Avalonia.Controls.Shapes.Path;

namespace Retrocore.Desktop;

/// <summary>
///  The extension's machine icons (<c>extension/media</c>): a small monitor showing the machine's screen while it
///  runs, and dark while it is off, and the activity bar's computer.
/// </summary>
internal static class MachineIcon
{
    /// <summary>
    ///  The frame's colour: the extension's dark and light icons' strokes.
    /// </summary>
    internal const string Frame = "Retrocore.MachineIconFrame";

    // What each machine's screen shows, by the launch's machine option, as the extension's icons draw them: the
    // Model III, 4 and the Altair's terminal glow white like the Model I, and the Model II green like the IIe.
    private static readonly Dictionary<string, (string Glass, string Text, bool Cursor)> s_screens = new()
    {
        ["apple2"] = ("#173404", "#97C459", false),
        ["apple3"] = ("#173404", "#97C459", false),
        ["trs80-model2"] = ("#173404", "#97C459", false),
        ["apple1"] = ("#2C2C2A", "#E6F1FB", true),
        ["coco"] = ("#3FB23F", "#0B2A0B", false),
        ["bbc"] = ("#3FB23F", "#0B2A0B", false),
        ["trs80-model1"] = ("#2C2C2A", "#E6F1FB", false),
        ["trs80-model3"] = ("#2C2C2A", "#E6F1FB", false),
        ["altair"] = ("#2C2C2A", "#E6F1FB", false),
    };

    /// <summary>
    ///  Draws a machine's icon.
    /// </summary>
    /// <param name="machine">The launch's machine option, such as <c>apple2</c>.</param>
    /// <param name="lit">Whether its screen is lit, as while it runs.</param>
    /// <returns>A 16 by 16 icon.</returns>
    internal static Control Create(string machine, bool lit)
    {
        (string glass, string text, bool cursor) = s_screens.TryGetValue(machine, out var screen) ? screen : s_screens["apple2"];
        Canvas canvas = new() { Width = 16, Height = 16, IsHitTestVisible = false };
        canvas.Children.Add(Stroked(new Rectangle
        {
            Width = 13,
            Height = 9.5,
            RadiusX = 2,
            RadiusY = 2,
            Fill = Brush(lit ? glass : "#2C2C2A"),
            [Canvas.LeftProperty] = 1.5,
            [Canvas.TopProperty] = 2.5,
        }));

        if (lit)
        {
            canvas.Children.Add(new Path
            {
                Data = Geometry.Parse(cursor ? "M4 5.5h6M4 7.5h8M4 9.5h2" : "M4 5.5h6M4 7.5h8M4 9.5h4"),
                Stroke = Brush(text),
                StrokeThickness = 1,
            });

            if (cursor)
            {
                canvas.Children.Add(new Rectangle
                {
                    Width = 2, Height = 2, Fill = Brush(text), [Canvas.LeftProperty] = 7.0, [Canvas.TopProperty] = 8.5
                });
            }
        }

        canvas.Children.Add(Stroked(new Path { Data = Geometry.Parse("M5.5 14.5h5") }));
        return canvas;
    }

    /// <summary>
    ///  Draws the activity bar's computer, as the extension's <c>retrocore.svg</c>.
    /// </summary>
    /// <param name="colour">The theme colour it is drawn in.</param>
    /// <returns>A 24 by 24 icon.</returns>
    internal static Control Activity(string colour)
    {
        Path path = new()
        {
            Data = Geometry.Parse("M5.75 3.75h12.5a2 2 0 0 1 2 2v7.5a2 2 0 0 1 -2 2h-12.5a2 2 0 0 1 -2 -2v-7.5a2 2 0 0 1 2 -2z"
                + "M7 7.5h5M7 10h7M7 12.5h3M2.75 17.75h18.5l-1.5 2.5H4.25zM7 19h1.5M10.5 19h1.5"),
            StrokeThickness = 1.5,
            StrokeLineCap = PenLineCap.Round,
            StrokeJoin = PenLineJoin.Round,
            Width = 24,
            Height = 24,
            IsHitTestVisible = false,
        };

        return path.Themed(Shape.StrokeProperty, colour);
    }

    private static T Stroked<T>(T shape) where T : Shape
    {
        shape.StrokeThickness = 1;
        return shape.Themed(Shape.StrokeProperty, Frame);
    }

    private static SolidColorBrush Brush(string colour) => new(Color.Parse(colour));
}