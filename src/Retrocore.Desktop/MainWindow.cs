// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using Avalonia;
using Avalonia.Controls;
using Avalonia.Controls.Primitives;
using Avalonia.Input;
using Avalonia.Interactivity;
using Avalonia.Layout;
using Avalonia.Media;
using Avalonia.Threading;
using Avalonia.VisualTree;
using Retrocore.Debug;
using Retrocore.Machines.Devices;

namespace Retrocore.Desktop;

/// <summary>
///  The window: an activity bar on the left, a side pane that collapses, the machine's screen, and a status bar
///  across the bottom, laid out as VS Code lays out its own, in its light or dark colours, and zoomed as it zooms.
/// </summary>
internal sealed class MainWindow : Window
{
    // The small computer the extension's activity bar shows.
    private const string MachineIcon = "M2,4 H22 V16 H2 Z M4,6 V14 H20 V6 Z M9,19 H15 V21 H9 Z M11,16 H13 V19 H11 Z";

    // The chrome's size at 100%: the activity bar with its border, and the status bar with its border. The pane
    // opens over the screen, so it takes none of the picture's space.
    private const double ActivityWidth = 49;
    private const double StatusHeight = 25;

    private readonly MachineHost _host;
    private readonly DesktopSettings _settings;
    private readonly ScreenView _screen;
    private readonly Grid _body = new();
    private readonly Border _pane = new()
    {
        BorderThickness = new Thickness(0, 0, 1, 0),
        BoxShadow = BoxShadows.Parse("4 0 12 0 #40000000")
    };
    // The pane's background, under its contents, so its opacity leaves the text and controls solid.
    private readonly Border _paneBackdrop = new();
    private readonly LayoutTransformControl _paneZoom = new();
    private readonly LayoutTransformControl _activityZoom = new();
    private readonly LayoutTransformControl _statusZoom = new();
    private readonly ScrollViewer _machineView;
    private readonly ScrollViewer _settingsView;
    private readonly ActivityButton _machineButton;
    private readonly ActivityButton _settingsButton;
    private readonly GridSplitter _splitter = new()
    {
        Background = Brushes.Transparent,
        ResizeDirection = GridResizeDirection.Columns
    };
    private readonly StackPanel _hardware = new();
    private readonly StackPanel _drives = new();
    private readonly TextBlock _machineState = new TextBlock
    {
        Margin = new Thickness(6, 0, 0, 0)
    }.Themed(TextBlock.ForegroundProperty, Palette.Dim);
    private readonly TextBlock _status = new TextBlock
    {
        VerticalAlignment = VerticalAlignment.Center,
        Margin = new Thickness(8, 0)
    }.Themed(TextBlock.ForegroundProperty, Palette.StatusText);
    private readonly Button _zoomStatus;
    private readonly TextBlock _zoomSetting = new TextBlock
    {
        VerticalAlignment = VerticalAlignment.Center,
        MinWidth = 48,
        TextAlignment = TextAlignment.Center
    }

        .Themed(TextBlock.ForegroundProperty, Palette.Text);
    private readonly DispatcherTimer _refresh = new() { Interval = TimeSpan.FromMilliseconds(250) };
    // Auto, to fit the pane's contents, until the splitter is dragged; a double-click on it fits them again.
    private GridLength _paneWidth = GridLength.Auto;

    private string? _drivesShown;
    private bool _settingsShown;

    /// <summary>
    ///  Creates the window for a running machine.
    /// </summary>
    /// <param name="host">The machine.</param>
    /// <param name="settings">The theme and zoom.</param>
    internal MainWindow(MachineHost host, DesktopSettings settings)
    {
        _host = host;
        _settings = settings;
        _screen = new ScreenView(host);
        Title = $"Retrocore Desktop · {host.Name}";
        Width = 1280;
        Height = 800;
        this.Themed(BackgroundProperty, Palette.Editor);

        _machineView = MachineView();
        _settingsView = SettingsView();
        _paneZoom.Child = _machineView;
        _paneBackdrop.Opacity = settings.PaneOpacity / 100.0;
        _paneBackdrop.Themed(Border.BackgroundProperty, Palette.SideBar);
        _pane.Child = new Panel { Children = { _paneBackdrop, _paneZoom } };
        _pane.Themed(Border.BorderBrushProperty, Palette.Border);

        _body.ColumnDefinitions =
        [
            new ColumnDefinition(_paneWidth) { MinWidth = 160 },
            new ColumnDefinition(GridLength.Auto),
            new ColumnDefinition(GridLength.Star)
        ];

        _splitter.DoubleTapped += (_, _) => FitPane();
        _splitter.Width = 4;
        // The screen fills the body, and the pane and its splitter open over it, so opening, closing or resizing the
        // pane never moves or resizes the picture.
        Grid.SetColumnSpan(_screen, 3);
        Grid.SetColumn(_pane, 0);
        Grid.SetColumn(_splitter, 1);
        _body.Children.AddRange([_screen, _pane, _splitter]);

        _machineButton = new ActivityButton(new PathIcon
        {
            Data = StreamGeometry.Parse(MachineIcon),
            Width = 24,
            Height = 24
        }, "Machine");

        _settingsButton = new ActivityButton(new TextBlock { Text = "⚙", FontSize = 22 }, "Settings");
        _machineButton.Click += (_, _) => ShowView(settings: false);
        _settingsButton.Click += (_, _) => ShowView(settings: true);
        _zoomStatus = StatusButton("", () => ZoomTo(0), "Reset Zoom (Ctrl+0)");

        DockPanel root = new();
        Border status = StatusBar();
        Border activity = ActivityBar();
        DockPanel.SetDock(status, Dock.Bottom);
        DockPanel.SetDock(activity, Dock.Left);
        root.Children.AddRange([status, activity, _body]);
        Content = root;

        // Zoom keys go first to the window, so no control takes them, unless the screen has the keyboard and they
        // are the machine's. Ctrl with the wheel always zooms: no machine takes the wheel.
        AddHandler(KeyDownEvent, OnZoomKey, RoutingStrategies.Tunnel);
        AddHandler(PointerWheelChangedEvent, OnZoomWheel, RoutingStrategies.Tunnel);

        ApplyZoom();
        UpdateActivity();

        // The picture's size follows the window, never the pane or the zoom.
        SizeChanged += (_, _) => UpdateScreenArea();
        _body.SizeChanged += (_, _) => _pane.MaxWidth = Math.Max(160, _body.Bounds.Width - 48);
        _refresh.Tick += (_, _) => Refresh();
        _refresh.Start();
        Opened += (_, _) => _screen.Focus();
    }

    /// <summary>
    ///  Gets the machine's screen.
    /// </summary>
    internal ScreenView Screen => _screen;

    /// <summary>
    ///  Shows a view in the side pane, or collapses the pane when that view is already shown, as clicking an activity
    ///  bar icon in VS Code does.
    /// </summary>
    /// <param name="settings">True for the settings, false for the machine.</param>
    internal void ShowView(bool settings)
    {
        if (_pane.IsVisible && _settingsShown == settings)
        {
            SetPaneOpen(open: false);
        }
        else
        {
            _settingsShown = settings;
            _paneZoom.Child = settings ? _settingsView : _machineView;
            SetPaneOpen(open: true);
        }

        UpdateActivity();
    }

    /// <summary>
    ///  Zooms the window's chrome by steps of 20%.
    /// </summary>
    /// <param name="steps">The steps, in or out.</param>
    internal void ZoomBy(int steps) => ZoomTo(_settings.Zoom + steps);

    /// <summary>
    ///  Zooms the window's chrome to a level.
    /// </summary>
    /// <param name="level">The level, 0 for 100%.</param>
    internal void ZoomTo(int level)
    {
        level = Math.Clamp(level, DesktopSettings.MinimumZoom, DesktopSettings.MaximumZoom);
        if (level == _settings.Zoom) { return; }
        _settings.Zoom = level;
        ApplyZoom();
        _settings.Save();
    }

    private void SetPaneOpen(bool open)
    {
        if (!open) { _paneWidth = _body.ColumnDefinitions[0].Width; }
        _pane.IsVisible = open;
        _splitter.IsVisible = open;
        _body.ColumnDefinitions[0].Width = open ? _paneWidth : new GridLength(0);
        if (!open) { _screen.Focus(); }
    }

    // Back to as wide as the pane's contents need, within the window.
    private void FitPane()
    {
        _paneWidth = GridLength.Auto;
        if (_pane.IsVisible) { _body.ColumnDefinitions[0].Width = _paneWidth; }
    }

    private void UpdateActivity()
    {
        _machineButton.Active = _pane.IsVisible && !_settingsShown;
        _settingsButton.Active = _pane.IsVisible && _settingsShown;
    }

    // The space the picture is sized for: the window less the chrome at 100%, so that zooming the chrome, which takes
    // a little more or less of the window, leaves the picture as it was.
    private void UpdateScreenArea()
    {
        _screen.SizingArea = new Size(
            Math.Max(0, ClientSize.Width - ActivityWidth),
            Math.Max(0, ClientSize.Height - StatusHeight));

        _screen.InvalidateVisual();
    }

    private void ApplyZoom()
    {
        double scale = _settings.Scale;
        ScaleTransform transform = new(scale, scale);


        _paneZoom.LayoutTransform = transform;
        _activityZoom.LayoutTransform = transform;
        _statusZoom.LayoutTransform = transform;
        string percent = $"{scale * 100:0}%";
        _zoomSetting.Text = percent;
        _zoomStatus.Content = "Zoom " + percent;
        _zoomStatus.IsVisible = _settings.Zoom != 0;
    }

    private void OnZoomKey(object? sender, KeyEventArgs e)
    {
        // Ctrl+Shift+E moves the keyboard from the screen to the pane and back, as it does between VS Code's editor
        // and its side bar, so the keyboard alone can reach the pane while the machine has it.
        if (e.Key == Key.E && e.KeyModifiers == (KeyModifiers.Control | KeyModifiers.Shift))
        {
            if (FocusManager?.GetFocusedElement() == _screen)
            {
                FocusPane();
            }
            else
            {
                _screen.Focus();
            }

            e.Handled = true;
            return;
        }

        if ((e.KeyModifiers & KeyModifiers.Control) == 0 || FocusManager?.GetFocusedElement() == _screen) { return; }
        switch (e.Key)
        {
            case Key.OemPlus or Key.Add:
                ZoomBy(1);
                break;
            case Key.OemMinus or Key.Subtract:
                ZoomBy(-1);
                break;
            case Key.D0 or Key.NumPad0:
                ZoomTo(0);
                break;
            default:
                return;
        }

        e.Handled = true;
    }

    // Opens the pane if it is closed and gives the keyboard to its first control, or to the view's icon when it has
    // none.
    private void FocusPane()
    {
        if (!_pane.IsVisible) { ShowView(_settingsShown); }
        InputElement? first = _paneZoom.GetVisualDescendants()
            .OfType<InputElement>()
            .FirstOrDefault(element => element.Focusable && element.IsEffectivelyVisible && element.IsEffectivelyEnabled);

        (first ?? (_settingsShown ? _settingsButton : _machineButton)).Focus(NavigationMethod.Tab);
    }

    private void OnZoomWheel(object? sender, PointerWheelEventArgs e)
    {
        if ((e.KeyModifiers & KeyModifiers.Control) == 0 || e.Delta.Y == 0) { return; }
        ZoomBy(Math.Sign(e.Delta.Y));
        e.Handled = true;
    }

    private Border ActivityBar()
    {
        DockPanel bar = new() { Width = 48 };
        DockPanel.SetDock(_machineButton, Dock.Top);
        DockPanel.SetDock(_settingsButton, Dock.Bottom);
        bar.Children.AddRange([_machineButton, _settingsButton, new Panel()]);
        _activityZoom.Child = bar;
        _activityZoom.VerticalAlignment = VerticalAlignment.Stretch;
        return new Border { Child = _activityZoom, BorderThickness = new Thickness(0, 0, 1, 0) }
            .Themed(Border.BackgroundProperty, Palette.ActivityBar)
            .Themed(Border.BorderBrushProperty, Palette.Border);
    }

    private ScrollViewer MachineView()
    {
        StackPanel sections = new();
        StackPanel machine = new();
        machine.Children.Add(new StackPanel
        {
            Orientation = Orientation.Horizontal,
            Margin = new Thickness(12, 4, 8, 4),
            Children =
            {
                new TextBlock
                {
                    Text = _host.Name, FontWeight = FontWeight.SemiBold
                }.Themed(TextBlock.ForegroundProperty, Palette.Text),
                _machineState
            },
        });

        machine.Children.Add(_hardware);
        foreach (HardwareRow row in _host.Hardware())
        {
            _hardware.Children.Add(Row(row.Name, row.Value, row.Value == "empty"));
        }

        sections.Children.Add(Section("Machine", machine));
        sections.Children.Add(Section("Drives", _drives));
        sections.Children.Add(Section("Display and Sound", DisplayAndSound()));
        return new ScrollViewer { Content = sections, HorizontalScrollBarVisibility = ScrollBarVisibility.Auto };
    }

    private ScrollViewer SettingsView()
    {
        StackPanel appearance = new() { Margin = new Thickness(0, 0, 0, 8) };

        string[] themes = ["system", "light", "dark"];
        ComboBox theme = Choice(["Follow System", "Light", "Dark"], Math.Max(0, Array.IndexOf(themes, _settings.ThemeName)));
        theme.SelectionChanged += (_, _) =>
        {
            _settings.ThemeName = themes[theme.SelectedIndex];
            if (Application.Current is { } application)
            {
                application.RequestedThemeVariant = Palette.Variant(_settings.ThemeName);
            }

            _settings.Save();
        };

        appearance.Children.Add(Option("Theme", theme));

        StackPanel zoom = new()
        {
            Orientation = Orientation.Horizontal,
            Spacing = 4,
            Children =
            {
                SmallButton("−", () => ZoomBy(-1), "Zoom Out (Ctrl+-)"),
                _zoomSetting,
                SmallButton("+", () => ZoomBy(1), "Zoom In (Ctrl+=)"),
                SmallButton("Reset", () => ZoomTo(0), "Reset Zoom (Ctrl+0)"),
            },
        };

        appearance.Children.Add(Option("Zoom", zoom));

        TextBlock opacityText = new TextBlock
        {
            Text = $"{_settings.PaneOpacity}%",
            VerticalAlignment = VerticalAlignment.Center,
            MinWidth = 40,
            Margin = new Thickness(6, 0, 0, 0)
        }.Themed(TextBlock.ForegroundProperty, Palette.Text);

        Slider opacity = new()
        {
            Minimum = DesktopSettings.MinimumPaneOpacity,
            Maximum = 100,
            Value = _settings.PaneOpacity,
            TickFrequency = 1,
            IsSnapToTickEnabled = true,
            Width = OptionWidth
        };

        ToolTip.SetTip(opacity, "How much of the machine shows through the pane");
        opacity.ValueChanged += (_, _) =>
        {
            int percent = (int)Math.Round(opacity.Value);
            if (percent == _settings.PaneOpacity) { return; }
            _settings.PaneOpacity = percent;
            _paneBackdrop.Opacity = percent / 100.0;
            opacityText.Text = $"{percent}%";
            _settings.Save();
        };

        appearance.Children.Add(Option(
            "Pane opacity",
            new StackPanel { Orientation = Orientation.Horizontal, Children = { opacity, opacityText } }));

        appearance.Children.Add(new TextBlock
        {
            Text = "Ctrl with the mouse wheel zooms too, anywhere in the window.",
            TextWrapping = TextWrapping.Wrap,
            FontSize = 12,
            Margin = new Thickness(20, 4, 8, 4),
        }.Themed(TextBlock.ForegroundProperty, Palette.Dim));

        return new ScrollViewer
        {
            Content = new StackPanel { Children = { Section("Appearance", appearance) } },
            HorizontalScrollBarVisibility = ScrollBarVisibility.Auto,
        };
    }

    private static Button SmallButton(string text, Action press, string tip)
    {
        Button button = new()
        {
            Content = text,
            Padding = new Thickness(8, 2),
            MinWidth = 28,
            HorizontalContentAlignment = HorizontalAlignment.Center
        };

        button.Click += (_, _) => press();
        ToolTip.SetTip(button, tip);
        return button;
    }

    // A section that collapses, as VS Code's views in a side bar do: a plain header with a chevron.
    private static StackPanel Section(string title, Control content)
    {
        string caption = title.ToUpperInvariant();
        Button header = new Button
        {
            Content = "▾  " + caption,
            FontSize = 11,
            FontWeight = FontWeight.Bold,
            Background = Brushes.Transparent,
            BorderThickness = new Thickness(0),
            CornerRadius = new CornerRadius(0),
            HorizontalAlignment = HorizontalAlignment.Stretch,
            HorizontalContentAlignment = HorizontalAlignment.Left,
            Padding = new Thickness(8, 6),
        }.Themed(ForegroundProperty, Palette.Text);

        header.Click += (_, _) =>
        {
            content.IsVisible = !content.IsVisible;
            header.Content = (content.IsVisible ? "▾  " : "▸  ") + caption;
        };

        return new StackPanel { Children = { header, content } };
    }

    private static Grid Row(string name, string value, bool dim = false) => new()
    {
        ColumnDefinitions = [new ColumnDefinition(new GridLength(110)), new ColumnDefinition(GridLength.Star)],
        Margin = new Thickness(20, 2, 8, 2),
        Children =
        {
            new TextBlock { Text = name }.Themed(TextBlock.ForegroundProperty, dim ? Palette.Dim : Palette.Text),
            Column(new TextBlock
            {
                Text = value, TextTrimming = TextTrimming.CharacterEllipsis
            }.Themed(TextBlock.ForegroundProperty, Palette.Dim), 1),
        },
    };

    private static Control Column(Control control, int column)
    {
        Grid.SetColumn(control, column);
        return control;
    }

    private StackPanel DisplayAndSound()
    {
        StackPanel options = new() { Margin = new Thickness(0, 0, 0, 8) };

        ComboBox speed = Choice(["1×", "2×", "4×", "8×", "Max"], _host.Speed switch
        {
            2 => 1,
            4 => 2,
            8 => 3,
            0 => 4,
            _ => 0
        });

        speed.SelectionChanged += (_, _) => _host.Speed = speed.SelectedIndex switch
        {
            1 => 2,
            2 => 4,
            3 => 8,
            4 => 0,
            _ => 1
        };

        options.Children.Add(Option("Speed", speed));

        // As the display panel's Fast disk: a disk or tape loads as fast as the machine can run, whatever the speed.
        if (_host.FastDriveKind is { } kind)
        {
            _host.FastDrives = _settings.FastDrives;
            CheckBox fast = new() { IsChecked = _settings.FastDrives, MinWidth = 0 };

            ToolTip.SetTip(fast, kind == "disk"
                ? "Runs as fast as it can while a disk drive's motor turns, then back at the chosen speed"
                : "Runs as fast as it can while the tape plays, then back at the chosen speed");

            fast.IsCheckedChanged += (_, _) =>
            {
                _settings.FastDrives = fast.IsChecked == true;
                _host.FastDrives = _settings.FastDrives;
                _settings.Save();
            };

            options.Children.Add(Option(kind == "disk" ? "Fast disk" : "Fast tape", fast));
        }

        // The machine's own modes, starting from the one it launched with.
        IReadOnlyList<string> modes = _host.SoundModes;
        ComboBox sound = Choice(
            [.. modes.Select(mode => mode switch { "off" => "Off", "mockingboard" => "Mockingboard", _ => "Speaker" })],
            Math.Max(0, modes.ToList().IndexOf(_host.SoundMode)));

        sound.SelectionChanged += (_, _) => _host.SoundMode = modes[Math.Max(0, sound.SelectedIndex)];
        options.Children.Add(Option("Sound", sound));

        Slider volume = new()
        {
            Minimum = 0,
            Maximum = 100,
            Value = _host.Volume * 100,
            Width = OptionWidth
        };

        volume.ValueChanged += (_, _) => _host.Volume = (float)(volume.Value / 100);
        options.Children.Add(Option("Volume", volume));

        ComboBox scale = Choice(["Sharp", "Fit"], 0);
        scale.SelectionChanged += (_, _) =>
        {
            _screen.Sharp = scale.SelectedIndex == 0;
            _screen.InvalidateVisual();
        };

        options.Children.Add(Option("Scale", scale));

        IReadOnlyList<string> screens = _host.Screens;
        if (screens.Count > 1)
        {
            ComboBox screen = Choice([.. screens], Math.Max(0, screens.ToList().IndexOf(_host.Screen)));
            screen.SelectionChanged += (_, _) => _host.Screen = screens[screen.SelectedIndex];
            options.Children.Add(Option("Screen", screen));
        }

        return options;
    }

    private static ComboBox Choice(string[] items, int selected) => new()
    {
        ItemsSource = items,
        SelectedIndex = selected,
        Width = OptionWidth,
        FontSize = 12,
    };

    // Every option's control starts at the same edge and the drop-downs and sliders are the same width, so the
    // column lines up whatever each control is.
    private const double OptionWidth = 180;

    private static Grid Option(string name, Control control)
    {
        control.HorizontalAlignment = HorizontalAlignment.Left;
        control.VerticalAlignment = VerticalAlignment.Center;
        return OptionRow(name, control);
    }

    private static Grid OptionRow(string name, Control control) => new()
    {
        ColumnDefinitions = [new ColumnDefinition(new GridLength(90)), new ColumnDefinition(GridLength.Star)],
        Margin = new Thickness(20, 3, 8, 3),
        Children =
        {
            new TextBlock
            {
                Text = name, VerticalAlignment = VerticalAlignment.Center
            }.Themed(TextBlock.ForegroundProperty, Palette.Text),
            Column(control, 1),
        },
    };

    private Border StatusBar()
    {
        StackPanel right = new() { Orientation = Orientation.Horizontal };
        right.Children.Add(_zoomStatus);
        right.Children.Add(StatusButton("Ctrl-C", () => _host.Key(3), "CONTROL-C"));
        right.Children.Add(StatusButton("Esc", () => _host.Key(KeyMap.Code(_host.KeyMapName, Key.Escape, KeyModifiers.None) ?? 27), "ESC"));
        right.Children.Add(StatusButton("Reset", _host.Reset, "The machine's reset"));
        DockPanel.SetDock(right, Dock.Right);
        _statusZoom.Child = new DockPanel { Height = 24, Children = { right, _status } };
        return new Border { Child = _statusZoom, BorderThickness = new Thickness(0, 1, 0, 0) }
            .Themed(Border.BackgroundProperty, Palette.StatusBar)
            .Themed(Border.BorderBrushProperty, Palette.Border);
    }

    private Button StatusButton(string text, Action press, string tip)
    {
        Button button = new Button
        {
            Content = text,
            FontSize = 12,
            Background = Brushes.Transparent,
            BorderThickness = new Thickness(0),
            CornerRadius = new CornerRadius(0),
            Padding = new Thickness(8, 0),
            VerticalAlignment = VerticalAlignment.Stretch,
            VerticalContentAlignment = VerticalAlignment.Center,
        }.Themed(ForegroundProperty, Palette.StatusText);

        ToolTip.SetTip(button, tip);
        button.Click += (_, _) =>
        {
            press();
            _screen.Focus();
        };

        return button;
    }

    private void Refresh()
    {
        double megahertz = _host.MeasuredHertz / 1_000_000;
        List<DriveRow> drives = _host.Devices();
        DriveRow? busy = drives.FirstOrDefault(drive => drive.Activity != DeviceActivity.Idle);
        string state = _host.Stopped is null ? "running" : "stopped: press Reset";
        _machineState.Text = state;
        string fast = _host.Accelerated ? (_host.FastDriveKind == "tape" ? " · fast tape" : " · fast disk") : "";
        _status.Text = $"● {_host.Name} · {state} · {megahertz:0.00} MHz{fast} · {_screen.Stats.FramesPerSecond} fps"
            + (busy is null ? "" : $" · {busy.Name}: {busy.Activity.ToString().ToLowerInvariant()}");

        string shown = string.Join('|', drives.Select(drive => $"{drive.Name}{drive.Media}{drive.Locked}{drive.Activity}"));
        if (shown == _drivesShown) { return; }
        _drivesShown = shown;
        _drives.Children.Clear();
        if (drives.Count == 0)
        {
            _drives.Children.Add(new TextBlock
            {
                Text = "No drives",
                Margin = new Thickness(20, 2)
            }.Themed(TextBlock.ForegroundProperty, Palette.Dim));

            return;
        }

        foreach (DriveRow drive in drives) { _drives.Children.Add(Drive(drive)); }
    }

    // A drive's row: its own icon with a padlock badge, coloured by what it is doing, as the media plan draws it.
    private static Grid Drive(DriveRow drive)
    {
        string glyph = drive.Kind switch { DeviceKind.TapeDrive => "▭", DeviceKind.BlockStorage => "⛁", _ => "▣" };
        string badge = drive.Media is null || drive.Kind == DeviceKind.TapeDrive ? "" : drive.Locked ? "🔒" : "🔓";
        string colour = drive.Media is null ? Palette.Dim : drive.Activity switch
        {
            DeviceActivity.Reading => Palette.Reading,
            DeviceActivity.Writing => Palette.Writing,
            DeviceActivity.Seeking => Palette.Seeking,
            _ => Palette.Text,
        };

        return new Grid
        {
            ColumnDefinitions = [new ColumnDefinition(new GridLength(34)), new ColumnDefinition(new GridLength(90)), new ColumnDefinition(GridLength.Star)],
            Margin = new Thickness(20, 2, 8, 2),
            Children =
            {
                new TextBlock { Text = glyph + badge }.Themed(TextBlock.ForegroundProperty, colour),
                Column(new TextBlock
                {
                    Text = drive.Name
                }.Themed(TextBlock.ForegroundProperty, drive.Media is null ? Palette.Dim : Palette.Text), 1),
                Column(new TextBlock
                {
                    Text = drive.Media ?? "empty", TextTrimming = TextTrimming.CharacterEllipsis
                }.Themed(TextBlock.ForegroundProperty, Palette.Dim), 2),
            },
        };
    }

    /// <inheritdoc/>
    protected override void OnClosed(EventArgs e)
    {
        _refresh.Stop();
        base.OnClosed(e);
    }
}