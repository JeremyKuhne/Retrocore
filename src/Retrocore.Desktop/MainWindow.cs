// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using Avalonia;
using Avalonia.Controls;
using Avalonia.Layout;
using Avalonia.Media;
using Avalonia.Threading;
using Retrocore.Debug;
using Retrocore.Machines.Devices;

namespace Retrocore.Desktop;

/// <summary>
///  The window: an activity bar on the left, a side pane that collapses, the machine's screen, and a status bar
///  across the bottom, laid out as VS Code lays out its own.
/// </summary>
internal sealed class MainWindow : Window
{
    // VS Code's dark theme, so the window reads as the extension's views do.
    private static readonly IBrush s_activityBar = new SolidColorBrush(Color.Parse("#333333"));
    private static readonly IBrush s_sideBar = new SolidColorBrush(Color.Parse("#252526"));
    private static readonly IBrush s_statusBar = new SolidColorBrush(Color.Parse("#007ACC"));
    private static readonly IBrush s_text = new SolidColorBrush(Color.Parse("#CCCCCC"));
    private static readonly IBrush s_dim = new SolidColorBrush(Color.Parse("#8B8B8B"));
    private static readonly IBrush s_reading = new SolidColorBrush(Color.Parse("#89D185"));
    private static readonly IBrush s_writing = new SolidColorBrush(Color.Parse("#F14C4C"));
    private static readonly IBrush s_seeking = new SolidColorBrush(Color.Parse("#CCA700"));

    // The small computer the extension's activity bar shows.
    private const string MachineIcon = "M2,4 H22 V16 H2 Z M4,6 V14 H20 V6 Z M9,19 H15 V21 H9 Z M11,16 H13 V19 H11 Z";

    private readonly MachineHost _host;
    private readonly ScreenView _screen;
    private readonly Grid _body = new();
    private readonly ScrollViewer _pane;
    private readonly GridSplitter _splitter = new()
    {
        Background = Brushes.Transparent,
        ResizeDirection = GridResizeDirection.Columns
    };
    private readonly StackPanel _hardware = new();
    private readonly StackPanel _drives = new();
    private readonly TextBlock _machineState = new() { Foreground = s_dim, Margin = new Thickness(6, 0, 0, 0) };
    private readonly TextBlock _status = new()
    {
        Foreground = Brushes.White,
        VerticalAlignment = VerticalAlignment.Center,
        Margin = new Thickness(8, 0)
    };
    private readonly DispatcherTimer _refresh = new() { Interval = TimeSpan.FromMilliseconds(250) };
    private GridLength _paneWidth = new(280);
    private string? _drivesShown;

    /// <summary>
    ///  Creates the window for a running machine.
    /// </summary>
    /// <param name="host">The machine.</param>
    internal MainWindow(MachineHost host)
    {
        _host = host;
        _screen = new ScreenView(host);
        Title = $"Retrocore Desktop · {host.Name}";
        Width = 1280;
        Height = 800;
        Background = Brushes.Black;

        _pane = Pane();
        _body.ColumnDefinitions = [new ColumnDefinition(_paneWidth), new ColumnDefinition(GridLength.Auto), new ColumnDefinition(GridLength.Star)];
        _splitter.Width = 4;
        Grid.SetColumn(_pane, 0);
        Grid.SetColumn(_splitter, 1);
        Grid.SetColumn(_screen, 2);
        _body.Children.AddRange([_pane, _splitter, _screen]);

        DockPanel root = new();
        DockPanel status = StatusBar();
        DockPanel activity = ActivityBar();
        DockPanel.SetDock(status, Dock.Bottom);
        DockPanel.SetDock(activity, Dock.Left);
        root.Children.AddRange([status, activity, _body]);
        Content = root;

        _refresh.Tick += (_, _) => Refresh();
        _refresh.Start();
        Opened += (_, _) => _screen.Focus();
    }

    /// <summary>
    ///  Gets the machine's screen.
    /// </summary>
    internal ScreenView Screen => _screen;

    /// <summary>
    ///  Opens or collapses the side pane, as clicking the active view's icon in VS Code does.
    /// </summary>
    internal void TogglePane()
    {
        bool open = _pane.IsVisible;
        if (open) { _paneWidth = _body.ColumnDefinitions[0].Width; }
        _pane.IsVisible = !open;
        _splitter.IsVisible = !open;
        _body.ColumnDefinitions[0].Width = open ? new GridLength(0) : _paneWidth;
        if (open) { _screen.Focus(); }
    }

    private DockPanel ActivityBar()
    {
        Button machine = IconButton(new PathIcon
        {
            Data = StreamGeometry.Parse(MachineIcon),
            Width = 24,
            Height = 24,
            Foreground = Brushes.White
        }, "Machine (opens and closes the side pane)");

        machine.Click += (_, _) => TogglePane();
        Button settings = IconButton(new TextBlock { Text = "⚙", FontSize = 20, Foreground = s_dim }, "Settings");
        DockPanel bar = new() { Width = 48, Background = s_activityBar };
        DockPanel.SetDock(machine, Dock.Top);
        DockPanel.SetDock(settings, Dock.Bottom);
        bar.Children.AddRange([machine, settings, new Panel()]);
        return bar;
    }

    private static Button IconButton(Control icon, string tip)
    {
        Button button = new()
        {
            Content = icon,
            Width = 48,
            Height = 48,
            Background = Brushes.Transparent,
            BorderThickness = new Thickness(0),
            HorizontalContentAlignment = HorizontalAlignment.Center,
            VerticalContentAlignment = VerticalAlignment.Center,
        };

        ToolTip.SetTip(button, tip);
        return button;
    }

    private ScrollViewer Pane()
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
                    Text = _host.Name, Foreground = s_text, FontWeight = FontWeight.SemiBold
                }, _machineState
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
        return new ScrollViewer { Content = sections, Background = s_sideBar };
    }

    // A section that collapses, as VS Code's views in a side bar do: a plain header with a chevron.
    private static StackPanel Section(string title, Control content)
    {
        string caption = title.ToUpperInvariant();
        Button header = new()
        {
            Content = "▾  " + caption,
            FontSize = 11,
            FontWeight = FontWeight.Bold,
            Foreground = s_text,
            Background = Brushes.Transparent,
            BorderThickness = new Thickness(0),
            CornerRadius = new CornerRadius(0),
            HorizontalAlignment = HorizontalAlignment.Stretch,
            HorizontalContentAlignment = HorizontalAlignment.Left,
            Padding = new Thickness(8, 6),
            Focusable = false,
        };

        header.Click += (_, _) =>
        {
            content.IsVisible = !content.IsVisible;
            header.Content = (content.IsVisible ? "▾  " : "▸  ") + caption;
        };

        return new StackPanel { Children = { header, content } };
    }

    private static Grid Row(string name, string value, bool dim = false) => new Grid
    {
        ColumnDefinitions = [new ColumnDefinition(new GridLength(110)), new ColumnDefinition(GridLength.Star)],
        Margin = new Thickness(20, 2, 8, 2),
        Children =
        {
            new TextBlock { Text = name, Foreground = dim ? s_dim : s_text },
            Column(new TextBlock
            {
                Text = value, Foreground = s_dim, TextTrimming = TextTrimming.CharacterEllipsis
            }, 1),
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

        ComboBox speed = Choice(["1×", "2×", "4×", "8×", "Max"], 0);
        speed.SelectionChanged += (_, _) => _host.Speed = speed.SelectedIndex switch
        {
            1 => 2,
            2 => 4,
            3 => 8,
            4 => 0,
            _ => 1
        };

        options.Children.Add(Option("Speed", speed));

        ComboBox sound = Choice(["Off", "Speaker"], 1);
        sound.SelectionChanged += (_, _) => _host.SoundOn = sound.SelectedIndex == 1;
        options.Children.Add(Option("Sound", sound));

        Slider volume = new() { Minimum = 0, Maximum = 100, Value = _host.Volume * 100, Width = 140 };
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
        Width = 140,
        FontSize = 12,
    };

    private static Grid Option(string name, Control control) => new Grid
    {
        ColumnDefinitions = [new ColumnDefinition(new GridLength(90)), new ColumnDefinition(GridLength.Star)],
        Margin = new Thickness(20, 3, 8, 3),
        Children =
        {
            new TextBlock { Text = name, Foreground = s_text, VerticalAlignment = VerticalAlignment.Center },
            Column(control, 1),
        },
    };

    private DockPanel StatusBar()
    {
        StackPanel keys = new() { Orientation = Orientation.Horizontal };
        keys.Children.Add(KeyButton("Ctrl-C", () => _host.Key(3)));
        keys.Children.Add(KeyButton("Esc", () => _host.Key(27)));
        keys.Children.Add(KeyButton("Reset", _host.Reset));
        DockPanel.SetDock(keys, Dock.Right);
        return new DockPanel { Height = 24, Background = s_statusBar, Children = { keys, _status } };
    }

    private Button KeyButton(string text, Action press)
    {
        Button button = new()
        {
            Content = text,
            FontSize = 12,
            Foreground = Brushes.White,
            Background = Brushes.Transparent,
            BorderThickness = new Thickness(0),
            Padding = new Thickness(8, 0),
            VerticalAlignment = VerticalAlignment.Stretch,
            VerticalContentAlignment = VerticalAlignment.Center,
            Focusable = false,
        };

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
        _machineState.Text = "running";
        _status.Text = $"● {_host.Name} · running · {megahertz:0.00} MHz · {_screen.Stats.FramesPerSecond} fps"
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
                Foreground = s_dim,
                Margin = new Thickness(20, 2)
            });

            return;
        }

        foreach (DriveRow drive in drives) { _drives.Children.Add(Drive(drive)); }
    }

    // A drive's row: its own icon with a padlock badge, coloured by what it is doing, as the media plan draws it.
    private static Grid Drive(DriveRow drive)
    {
        string glyph = drive.Kind switch { DeviceKind.TapeDrive => "▭", DeviceKind.BlockStorage => "⛁", _ => "▣" };
        string badge = drive.Media is null || drive.Kind == DeviceKind.TapeDrive ? "" : drive.Locked ? "🔒" : "🔓";
        IBrush colour = drive.Media is null ? s_dim : drive.Activity switch
        {
            DeviceActivity.Reading => s_reading,
            DeviceActivity.Writing => s_writing,
            DeviceActivity.Seeking => s_seeking,
            _ => s_text,
        };

        return new Grid
        {
            ColumnDefinitions = [new ColumnDefinition(new GridLength(34)), new ColumnDefinition(new GridLength(90)), new ColumnDefinition(GridLength.Star)],
            Margin = new Thickness(20, 2, 8, 2),
            Children =
            {
                new TextBlock { Text = glyph + badge, Foreground = colour },
                Column(new TextBlock { Text = drive.Name, Foreground = drive.Media is null ? s_dim : s_text }, 1),
                Column(new TextBlock
                {
                    Text = drive.Media ?? "empty", Foreground = s_dim, TextTrimming = TextTrimming.CharacterEllipsis
                }, 2),
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