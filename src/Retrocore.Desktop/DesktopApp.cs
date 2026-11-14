// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using Avalonia;
using Avalonia.Controls.ApplicationLifetimes;
using Avalonia.Styling;
using Avalonia.Themes.Fluent;

namespace Retrocore.Desktop;

/// <summary>
///  The application: Avalonia's Fluent theme in the light or dark variant the settings ask for, and one window for
///  the machine.
/// </summary>
/// <param name="host">The machine.</param>
/// <param name="settings">The theme and zoom.</param>
/// <param name="smokeSeconds">
///  For a smoke run, how long to run before reporting and closing; null to run until closed.
/// </param>
internal sealed class DesktopApp(MachineHost host, DesktopSettings settings, double? smokeSeconds) : Application
{
    /// <inheritdoc/>
    public override void Initialize()
    {
        Styles.Add(new FluentTheme());
        Palette.Install(this);

        // Follow System is the default variant, which follows the system's light or dark mode as it changes.
        RequestedThemeVariant = Palette.Variant(settings.ThemeName);
    }

    /// <inheritdoc/>
    public override void OnFrameworkInitializationCompleted()
    {
        if (ApplicationLifetime is IClassicDesktopStyleApplicationLifetime desktop)
        {
            MainWindow window = new(host, settings);
            desktop.MainWindow = window;
            host.Start();
            if (smokeSeconds is { } seconds) { SmokeRun.Start(window, host, seconds, desktop); }
        }

        base.OnFrameworkInitializationCompleted();
    }
}