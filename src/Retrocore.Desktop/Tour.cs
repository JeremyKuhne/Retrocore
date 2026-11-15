// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using Avalonia;
using Avalonia.Controls.ApplicationLifetimes;
using Avalonia.Media.Imaging;
using Avalonia.Styling;
using Avalonia.Threading;
using System.Text.Json.Nodes;

namespace Retrocore.Desktop;

/// <summary>
///  Walks the window through what the side pane does, a step a second, and saves a picture of the window at each:
///  running, a row selected, stopped and off with its settings, Switch Machine's quick pick, a card added with its
///  drives, a dialog, a notification, the light theme and the settings. A check of the look without a person at the
///  keyboard: <c>--tour folder</c>.
/// </summary>
internal static class Tour
{
    /// <summary>
    ///  Starts the tour.
    /// </summary>
    /// <param name="window">The window.</param>
    /// <param name="session">The machine.</param>
    /// <param name="folder">Where the pictures go.</param>
    /// <param name="disk">A disk image to insert and boot from, or null to leave the drives empty.</param>
    /// <param name="desktop">The application, to shut down at the end.</param>
    internal static void Start(MainWindow window, MachineSession session, string folder, string? disk, IClassicDesktopStyleApplicationLifetime desktop)
    {
        Directory.CreateDirectory(folder);
        string Drive() => session.Host.DeviceStates().FirstOrDefault()?.Id ?? "";
        List<(string Name, Action Act)> steps =
        [
            ("01-running", () => { }),
            ("02-selected", () => window.Pane.MachineTree.SelectRow("hardware/slot6")),
            ("03-off", session.Stop),
            ("04-switch", () => window.Pane.MachineTree.Click("switch")),
            ("05-setting", () =>
            {
                window.CloseOverlays();
                window.Pane.MachineTree.Click("setting/sound");
            }),
            ("06-card", () =>
            {
                window.CloseOverlays();
                session.Hardware("slot6", new JsonObject { ["action"] = "addDiskII", ["sectors"] = 16 });
                window.Pane.DriveTree.SelectRow(Drive());
            }),
            ("06e-setting", () =>
            {
                // A setting changed while off keeps the card added in slot 6, and the Mockingboard goes in slot 4.
                MachineChoice sound = session.CatalogMachine?.Choices.First(choice => choice.Option == "sound")
                    ?? throw new InvalidOperationException("The machine has no sound setting.");

                session.SetSetting(sound, "mockingboard");
            }),
            ("07-dialog", () => _ = window.Ask("Remove the Disk II controller from Slot 6? Its disks are ejected.", ["Remove Card"])),
            ("08-notification", () =>
            {
                window.CloseOverlays();
                window.Notify("Retrocore: There is no device 'drive9'.");
            }),
            ("09-light", () =>
            {
                if (Application.Current is { } application) { application.RequestedThemeVariant = ThemeVariant.Light; }
            }),
            ("10-settings", () => window.ShowView(settings: true)),
            ("11-trs80", () =>
            {
                window.ShowView(settings: false);
                if (Application.Current is { } application) { application.RequestedThemeVariant = ThemeVariant.Dark; }
                session.Switch(MachineCatalog.Configuration(MachineCatalog.Machines.First(machine => machine.Id == "trs80-model1-level2")), saved: null);
                session.Start();
            }),
        ];

        // With a disk, it goes in the first drive while off, and the machine boots from it.
        if (disk is not null)
        {
            steps.InsertRange(steps.FindIndex(entry => entry.Name == "06e-setting"),
            [
                ("06b-inserted", () => session.Device(Drive(), "insert", new JsonObject { ["path"] = disk })),
                ("06c-booting", () =>
                {
                    session.Start();
                    window.Pane.DriveTree.SelectRow(Drive());
                }),
                ("06d-stopped", session.Stop),
            ]);
        }

        int step = 0;
        DispatcherTimer timer = new() { Interval = TimeSpan.FromSeconds(1.5) };
        timer.Tick += (_, _) =>
        {
            if (step > 0) { Save(window, Path.Join(folder, steps[step - 1].Name + ".png")); }
            if (step == steps.Count)
            {
                timer.Stop();
                desktop.Shutdown();
                return;
            }

            steps[step].Act();
            step++;
        };

        timer.Start();
    }

    // The window as it draws itself now, at its own scale.
    private static void Save(MainWindow window, string path)
    {
        double scale = window.RenderScaling;
        PixelSize size = new((int)(window.ClientSize.Width * scale), (int)(window.ClientSize.Height * scale));
        using RenderTargetBitmap bitmap = new(size, new Vector(96 * scale, 96 * scale));
        bitmap.Render(window);
        bitmap.Save(path, PngBitmapEncoderOptions.Default);
        Console.Out.WriteLine(path);
    }
}
