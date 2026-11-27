// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using Avalonia;
using Avalonia.Automation;
using Avalonia.Controls;
using Avalonia.Controls.Primitives;
using Avalonia.Input;
using Avalonia.Interactivity;
using Avalonia.Layout;
using Avalonia.Media;
using Avalonia.Threading;
using Avalonia.VisualTree;
using Retrocore.Machines.Devices;

namespace Retrocore.Desktop;

/// <summary>
///  The window: an activity bar on the left, a side pane that collapses, the machine's screen, and a status bar
///  across the bottom, laid out as VS Code lays out its own, in its light or dark colours, and zoomed as it zooms.
/// </summary>
internal sealed class MainWindow : Window
{
    // The chrome's size at 100%: the activity bar with its border, and the status bar with its border. The pane
    // opens over the screen, so it takes none of the picture's space.
    private const double ActivityWidth = 49;
    private const double StatusHeight = 23;

    private readonly MachineSession _session;
    private readonly DesktopSettings _settings;
    private readonly ScreenView _screen;
    private readonly MachinePane _machinePane;

    // Whether the window may close: set once its changed disks are saved or let go.
    private bool _mayClose;

    // Whether a close is asking about changed disks, so another close request waits on it rather than asking again.
    private bool _closing;
    private readonly Grid _body = new();
    private readonly Border _pane = new()
    {
        BorderThickness = new Thickness(0, 0, 1, 0),
        BoxShadow = BoxShadows.Parse("4 0 12 0 #40000000"),
    };

    // The pane's background, under its contents, so its opacity leaves the text and controls solid.
    private readonly Border _paneBackdrop = new();
    private readonly LayoutTransformControl _paneZoom = new();
    private readonly LayoutTransformControl _activityZoom = new();
    private readonly LayoutTransformControl _statusZoom = new();
    private readonly LayoutTransformControl _overlayZoom = new();

    // The quick pick and dialogs go over everything; notifications stack at the bottom right.
    private readonly Panel _overlay = new();
    private readonly StackPanel _notifications = new()
    {
        HorizontalAlignment = HorizontalAlignment.Right,
        VerticalAlignment = VerticalAlignment.Bottom,
        Margin = new Thickness(0, 0, 12, 12),
    };

    private readonly Control _machineView;
    private readonly Control _settingsView;
    private readonly ActivityButton _machineButton;
    private readonly ActivityButton _settingsButton;
    private readonly GridSplitter _splitter = new()
    {
        Background = Brushes.Transparent,
        ResizeDirection = GridResizeDirection.Columns,
    };

    private readonly StackPanel _off = new()
    {
        HorizontalAlignment = HorizontalAlignment.Center,
        VerticalAlignment = VerticalAlignment.Center,
        Spacing = 12,
    };

    private readonly TextBlock _offText = new TextBlock
    {
        FontSize = 13,
        HorizontalAlignment = HorizontalAlignment.Center,
        TextAlignment = TextAlignment.Center,
    }.Themed(TextBlock.ForegroundProperty, Palette.Text);

    private readonly TextBlock _status = new TextBlock
    {
        VerticalAlignment = VerticalAlignment.Center,
        FontSize = 12,
    }.Themed(TextBlock.ForegroundProperty, Palette.StatusText);

    private readonly StackPanel _keys = new() { Orientation = Orientation.Horizontal };
    private readonly FlatButton _zoomStatus;
    private readonly TextBlock _zoomStatusText = new();
    private readonly FlatButton _keyboardStatus;
    private readonly TextBlock _zoomSetting = new TextBlock
    {
        VerticalAlignment = VerticalAlignment.Center,
        MinWidth = 48,
        FontSize = 13,
        TextAlignment = TextAlignment.Center,
    }.Themed(TextBlock.ForegroundProperty, Palette.Text);

    private readonly DispatcherTimer _refresh = new() { Interval = TimeSpan.FromMilliseconds(250) };

    // Auto, to fit the pane's contents, until the splitter is dragged; a double-click on it fits them again.
    private GridLength _paneWidth = GridLength.Auto;
    private bool _settingsShown;
    private string? _keysFor;
    private FlatButton? _ctrlKey;
    private readonly FlatButton?[] _appleKeys = new FlatButton?[2];

    /// <summary>
    ///  Creates the window for a machine.
    /// </summary>
    /// <param name="session">The machine.</param>
    /// <param name="settings">The theme and zoom.</param>
    internal MainWindow(MachineSession session, DesktopSettings settings)
    {
        _session = session;
        _settings = settings;
        _screen = new ScreenView(session);
        Width = 1280;
        Height = 800;
        this.Themed(BackgroundProperty, Palette.Editor);

        _machinePane = new MachinePane(this, session, settings);
        _machineView = SideView("Retrocore", _machinePane);
        _settingsView = SideView("Settings", SettingsView());
        _paneZoom.Child = _machineView;
        _paneBackdrop.Opacity = settings.PaneOpacity / 100.0;
        _paneBackdrop.Themed(Border.BackgroundProperty, Palette.SideBar);
        _pane.Child = new Panel { Children = { _paneBackdrop, _paneZoom } };
        _pane.Themed(Border.BorderBrushProperty, Palette.Border);

        _body.ColumnDefinitions =
        [
            new ColumnDefinition(_paneWidth) { MinWidth = 160 },
            new ColumnDefinition(GridLength.Auto),
            new ColumnDefinition(GridLength.Star),
        ];

        _splitter.DoubleTapped += (_, _) => FitPane();
        _splitter.Width = 4;

        // The screen fills the body, and the pane and its splitter open over it, so opening, closing or resizing the
        // pane never moves or resizes the picture. An off machine shows how to start it, over its dimmed picture.
        Grid.SetColumnSpan(_screen, 3);
        Grid.SetColumnSpan(_off, 3);
        Grid.SetColumn(_pane, 0);
        Grid.SetColumn(_splitter, 1);
        _body.Children.AddRange([_screen, _off, _pane, _splitter]);
        BuildOff();

        _machineButton = new ActivityButton(MachineIcon.Activity(Palette.ActivityInactive), "Retrocore");
        _settingsButton = new ActivityButton(Codicon.Create("settings-gear", Palette.ActivityInactive, 24), "Settings");
        _machineButton.Click += (_, _) => ShowView(settings: false);
        _settingsButton.Click += (_, _) => ShowView(settings: true);
        _zoomStatus = StatusItem(_zoomStatusText, "Reset Zoom (Ctrl+0)", () => ZoomTo(0));
        _keyboardStatus = StatusItem(Codicon.Create("keyboard", Palette.StatusText, 14), "Keyboard", () => _screen.Focus());

        DockPanel root = new();
        Border status = StatusBar();
        Border activity = ActivityBar();
        DockPanel.SetDock(status, Dock.Bottom);
        DockPanel.SetDock(activity, Dock.Left);
        root.Children.AddRange([status, activity, _body]);
        _overlayZoom.Child = new Panel { Children = { _overlay, _notifications } };
        Content = new Panel { Children = { root, _overlayZoom } };

        // Zoom keys go first to the window, so no control takes them, unless the screen has the keyboard and they
        // are the machine's. Ctrl with the wheel always zooms: no machine takes the wheel.
        AddHandler(KeyDownEvent, OnZoomKey, RoutingStrategies.Tunnel);
        AddHandler(PointerWheelChangedEvent, OnZoomWheel, RoutingStrategies.Tunnel);

        // The screen's context menu pastes, as the panel's does.
        _screen.ContextMenu = ViewTree.Menu([[new TreeAction(Icon: null, "Paste", () => _ = _screen.PasteAsync())]]);
        _screen.PasteRequested += (_, _) => _ = _screen.PasteAsync();
        _screen.KeysChanged += (_, _) => PaintKeys();

        // A click in the screen collapses the side pane, so the whole picture is the machine's.
        _screen.AddHandler(
            PointerPressedEvent,
            (_, e) =>
            {
                if (!_pane.IsVisible || !e.GetCurrentPoint(_screen).Properties.IsLeftButtonPressed) { return; }
                SetPaneOpen(open: false);
                UpdateActivity();
            },
            RoutingStrategies.Tunnel,
            handledEventsToo: true);

        session.Changed += (_, _) =>
        {
            UpdateTitle();
            Refresh();
        };

        ApplyZoom();
        UpdateActivity();
        UpdateTitle();

        // Sharp sizing follows the window, never the pane or the zoom; Fit uses the screen's actual bounds.
        SizeChanged += (_, _) => UpdateScreenArea();
        _body.SizeChanged += (_, _) => _pane.MaxWidth = Math.Max(160, _body.Bounds.Width - 48);
        _refresh.Tick += (_, _) => Refresh();
        _refresh.Start();
        Opened += (_, _) =>
        {
            Refresh();
            _screen.Focus();
        };
    }

    /// <summary>
    ///  Gets the machine's screen.
    /// </summary>
    internal ScreenView Screen => _screen;

    /// <summary>
    ///  Gets the machine's side pane.
    /// </summary>
    internal MachinePane Pane => _machinePane;

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
    ///  Shows a quick pick at the top of the window and waits for a choice.
    /// </summary>
    /// <typeparam name="T">What an item gives.</typeparam>
    /// <param name="items">The items.</param>
    /// <param name="title">The title.</param>
    /// <param name="placeholder">The filter's placeholder.</param>
    /// <returns>The item picked, or null.</returns>
    internal Task<QuickPickItem<T>?> Pick<T>(IReadOnlyList<QuickPickItem<T>> items, string title, string placeholder) =>
        QuickPick.Show(_overlay, items, title, placeholder);

    /// <summary>
    ///  Asks a question in a modal dialog.
    /// </summary>
    /// <param name="message">The question.</param>
    /// <param name="buttons">The answers; Cancel follows them.</param>
    /// <returns>The answer, or null for Cancel.</returns>
    internal Task<string?> Ask(string message, IReadOnlyList<string> buttons) => Dialog.Ask(_overlay, message, buttons);

    /// <summary>
    ///  Shows a notification at the bottom right, as VS Code's error, warning and information messages show.
    /// </summary>
    /// <param name="message">The message.</param>
    /// <param name="icon"><c>error</c>, <c>warning</c> or <c>info</c>.</param>
    internal void Notify(string message, string icon = "error") => Notification.Show(_notifications, message, icon);

    /// <summary>
    ///  Closes the quick pick and dialogs, for the tour.
    /// </summary>
    internal void CloseOverlays() => _overlay.Children.Clear();

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

    private void UpdateTitle() => Title = $"Retrocore Desktop · {_session.Host.Name}";

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

    // The space the sharp picture is sized for: the window less the chrome at 100%, so zooming the chrome leaves
    // its whole-pixel size unchanged. Fit mode instead uses the actual viewport after layout.
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
        _overlayZoom.LayoutTransform = transform;
        string percent = $"{scale * 100:0}%";
        _zoomSetting.Text = percent;
        _zoomStatusText.Text = "Zoom " + percent;
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

    // A view of the side pane: its title in capitals, 35 pixels tall as VS Code's side bar title is, over its sections.
    private static DockPanel SideView(string title, Control content)
    {
        TextBlock caption = new TextBlock
        {
            Text = title.ToUpperInvariant(),
            FontSize = 11,
            VerticalAlignment = VerticalAlignment.Center,
            Margin = new Thickness(20, 0, 8, 0),
        }.Themed(TextBlock.ForegroundProperty, Palette.Text);

        Border header = new() { Height = 35, Child = caption };
        DockPanel.SetDock(header, Dock.Top);
        return new DockPanel { Children = { header, content } };
    }

    private ScrollViewer SettingsView()
    {
        StackPanel appearance = new() { Margin = new Thickness(0, 2, 0, 8) };

        string[] themes = ["system", "light", "dark"];
        ComboBox theme = Options.Choice(["Follow System", "Light", "Dark"], Math.Max(0, Array.IndexOf(themes, _settings.ThemeName)));
        theme.SelectionChanged += (_, _) =>
        {
            _settings.ThemeName = themes[theme.SelectedIndex];
            if (Application.Current is { } application)
            {
                application.RequestedThemeVariant = Palette.Variant(_settings.ThemeName);
            }

            _settings.Save();
        };

        appearance.Children.Add(Options.Row("Theme", theme, "Light Modern, Dark Modern, or as the system is"));

        FlatButton zoomOut = FlatButton.Icon("zoom-out", "Zoom Out (Ctrl+-)");
        FlatButton zoomIn = FlatButton.Icon("zoom-in", "Zoom In (Ctrl+=)");
        FlatButton reset = FlatButton.Text("Reset", primary: false, "Reset Zoom (Ctrl+0)");
        zoomOut.Focusable = zoomIn.Focusable = true;
        zoomOut.Click += (_, _) => ZoomBy(-1);
        zoomIn.Click += (_, _) => ZoomBy(1);
        reset.Click += (_, _) => ZoomTo(0);
        reset.MinWidth = 0;
        reset.Margin = new Thickness(6, 0, 0, 0);
        StackPanel zoom = new()
        {
            Orientation = Orientation.Horizontal,
            Spacing = 2,
            Children = { zoomOut, _zoomSetting, zoomIn, reset },
        };

        AutomationProperties.SetName(zoom, "Zoom");
        appearance.Children.Add(Options.Row("Zoom", zoom));

        TextBlock opacityText = new TextBlock
        {
            Text = $"{_settings.PaneOpacity}%",
            VerticalAlignment = VerticalAlignment.Center,
            FontSize = 13,
            MinWidth = 40,
            Margin = new Thickness(6, 0, 0, 0),
        }.Themed(TextBlock.ForegroundProperty, Palette.Text);

        Slider opacity = new()
        {
            Minimum = DesktopSettings.MinimumPaneOpacity,
            Maximum = 100,
            Value = _settings.PaneOpacity,
            TickFrequency = 1,
            IsSnapToTickEnabled = true,
            Width = Options.Width,
            MinHeight = 0,
        };

        AutomationProperties.SetName(opacity, "Pane opacity");
        opacity.ValueChanged += (_, _) =>
        {
            int percent = (int)Math.Round(opacity.Value);
            if (percent == _settings.PaneOpacity) { return; }
            _settings.PaneOpacity = percent;
            _paneBackdrop.Opacity = percent / 100.0;
            opacityText.Text = $"{percent}%";
            _settings.Save();
        };

        appearance.Children.Add(Options.Row(
            "Pane opacity",
            new StackPanel { Orientation = Orientation.Horizontal, Children = { opacity, opacityText } },
            "How much of the machine shows through the pane"));

        appearance.Children.Add(new TextBlock
        {
            Text = "Ctrl with the mouse wheel zooms too, anywhere in the window.",
            TextWrapping = TextWrapping.Wrap,
            FontSize = 12,
            Opacity = 0.7,
            Margin = new Thickness(20, 4, 12, 4),
        }.Themed(TextBlock.ForegroundProperty, Palette.Text));

        return new ScrollViewer
        {
            Content = new StackPanel { Children = { new ViewSection("Appearance", appearance, first: true) } },
            HorizontalScrollBarVisibility = ScrollBarVisibility.Auto,
        };
    }

    // An off machine's screen: what it is, and how to start it or set up another, as the panel shows a session that
    // ended with Restart and Start Machine.
    private void BuildOff()
    {
        FlatButton start = FlatButton.Text("Start This Machine", primary: true);
        FlatButton other = FlatButton.Text("Switch Machine…", primary: false);
        start.Focusable = other.Focusable = true;
        start.Click += (_, _) =>
        {
            _session.Start();
            _screen.Focus();
        };

        other.Click += (_, _) =>
        {
            if (!_pane.IsVisible || _settingsShown) { ShowView(settings: false); }
            _machinePane.MachineTree.Click("switch");
        };

        _off.Children.Add(_offText);
        _off.Children.Add(new StackPanel
        {
            Orientation = Orientation.Horizontal,
            HorizontalAlignment = HorizontalAlignment.Center,
            Spacing = 8,
            Children = { start, other },
        });
    }

    private Border StatusBar()
    {
        StackPanel right = new() { Orientation = Orientation.Horizontal };
        right.Children.Add(_zoomStatus);
        right.Children.Add(_keys);
        right.Children.Add(_keyboardStatus);
        DockPanel.SetDock(right, Dock.Right);
        Border left = new() { Padding = new Thickness(10, 0, 5, 0), Child = _status };
        _statusZoom.Child = new DockPanel { Height = 22, Children = { right, left } };
        return new Border { Child = _statusZoom, BorderThickness = new Thickness(0, 1, 0, 0) }
            .Themed(Border.BackgroundProperty, Palette.StatusBar)
            .Themed(Border.BorderBrushProperty, Palette.Border);
    }

    // A status bar item: 22 pixels tall, its text 12 pixels, lit under the pointer, as VS Code's are.
    private FlatButton StatusItem(Control content, string tip, Action press)
    {
        if (content is TextBlock text)
        {
            text.FontSize = 12;
            text.VerticalAlignment = VerticalAlignment.Center;
            text.Themed(TextBlock.ForegroundProperty, Palette.StatusText);
        }

        FlatButton item = new(content, tip, rest: null, Palette.StatusHover)
        {
            Height = 22,
            Padding = new Thickness(5, 0),
        };

        item.Click += (_, _) =>
        {
            press();
            _screen.Focus();
        };

        return item;
    }

    private FlatButton KeyItem(string label, string tip, Action press) => StatusItem(new TextBlock
    {
        Text = label
    }, tip, press);

    // The machine's own keys, as the display panel's key bar has them for each machine.
    private void BuildKeys(MachineHost host)
    {
        _keys.Children.Clear();
        _ctrlKey = null;
        Array.Clear(_appleKeys);
        string machine = host.KeyMapName;
        bool board = machine == "apple2" && host.Model is { } model && !model.Contains("IIe", StringComparison.Ordinal);
        void Code(string label, int code, string tip) => _keys.Children.Add(KeyItem(label, tip, () => host.Key(code)));
        void Reset(string label, string tip) => _keys.Children.Add(KeyItem(label, tip, host.Reset));
        void Clear() => _keys.Children.Add(KeyItem("Clear Screen", machine == "apple1"
            ? "CLEAR SCREEN: blanks the screen and puts the cursor at the top left"
            : "The terminal's CLEAR: blanks the screen and homes the cursor, as ^Z does", host.ClearScreen));

        switch (machine)
        {
            case "apple2" or "apple3":
                bool three = machine == "apple3";
                _ctrlKey = KeyItem("Ctrl", "Makes the next letter a control character, as holding CONTROL does (or hold Ctrl)",
                    () => _screen.StickyControl = !_screen.StickyControl);

                _keys.Children.Add(_ctrlKey);
                Code("Ctrl-C", 3, "CONTROL-C: stops a BASIC program (or Ctrl+C)");
                Reset("Ctrl-Reset", three
                    ? "CONTROL-RESET (or Ctrl+F12 or Ctrl+Break)"
                    : "CONTROL-RESET (or Ctrl+F12 or Ctrl+Break); with Open Apple down it restarts the machine");

                Code("Esc", 27, "ESC (or Esc)");
                string[] names = board ? ["Button 0", "Button 1"] : three ? ["Open Apple", "Solid Apple"] : ["Open Apple", "Closed Apple"];
                for (int button = 0; button < 2; button++)
                {
                    int which = button;
                    FlatButton key = KeyItem(names[button],
                        $"{names[button]}: stays down until clicked again (or hold the {(button == 0 ? "left" : "right")} Alt key)",
                        () => _screen.ToggleLatch(which));

                    _appleKeys[button] = key;
                    _keys.Children.Add(key);
                }

                break;
            case "trs80-model1":
                Code("Break", 1, "BREAK (or Esc)");
                Code("Clear", 31, "CLEAR (or Home)");
                Reset("Reset", "The reset button (or Ctrl+F12 or Ctrl+Break): boots a disk, or restarts BASIC with the program kept");
                break;
            case "trs80-model3":
                Code("Break", 1, "BREAK (or Esc)");
                Code("Clear", 31, "CLEAR (or Home)");
                Reset("Reset", "The reset button (or Ctrl+F12 or Ctrl+Break): the ROM starts again");
                break;
            case "trs80-model2":
                Code("Break", 3, "BREAK (or Esc)");
                Code("Hold", 0, "HOLD");
                Code("F1", 1, "F1");
                Code("F2", 2, "F2");
                Reset("Reset", "The reset switch (or Ctrl+F12 or Ctrl+Break): the boot ROM starts again");
                break;
            case "trs80-model100":
                Code("Label", 136, "LABEL: shows the function keys' labels");
                Code("Print", 137, "PRINT: prints the screen");
                Code("Paste", 138, "PASTE: types the paste buffer");
                Code("Pause", 139, "PAUSE (or Pause): the PAUSE/BREAK key, which pauses a listing or program");
                Code("Break", 140, "BREAK: PAUSE/BREAK with SHIFT, which stops a BASIC program");
                Reset("Reset", "The RESET button (or Ctrl+F12 or Ctrl+Break): the 80C85 starts again, keeping RAM, and turns the machine on after POWER OFF");
                break;
            case "kaypro2":
                Code("Esc", 27, "ESC (or Esc)");
                Reset("Reset", "The reset button (or Ctrl+F12 or Ctrl+Break): the monitor ROM boots CP/M from drive A again");
                break;
            case "apple1":
                Code("Esc", 27, "ESC (or Esc): drops the line being typed");
                Reset("Reset", "RESET (or Ctrl+F12 or Ctrl+Break): restarts the Monitor, keeping memory and the screen");
                Clear();
                break;
            case "altair":
                Code("Esc", 27, "ESC (or Esc)");
                Reset("Reset", "The front panel's RESET (or Ctrl+F12 or Ctrl+Break): the 8080 starts again at $0000, keeping memory");
                Clear();
                break;
            case "pet":
                Code("Stop", 3, "STOP (or Esc)");
                Code("Clr", 147, "CLR, the shifted HOME: clears the screen");
                Reset("Reset", "A reset switch (or Ctrl+F12 or Ctrl+Break): the kernal starts again, keeping memory");
                break;
            case "atari800":
                Code("Start", 0xF0, "START (or F2)");
                Code("Select", 0xF1, "SELECT (or F3)");
                Code("Option", 0xF2, "OPTION (or F4)");
                Code("Break", 0xF3, "BREAK (or Pause)");
                Code("System Reset", 0xF4, "SYSTEM RESET: the OS starts warm, and BASIC keeps its program");
                Reset("Power", "Power off and on (or Ctrl+F12 or Ctrl+Break): the OS starts cold");
                break;
            case "coco":
                Code("Break", 1, "BREAK (or Esc)");
                Code("Clear", 31, "CLEAR (or Home)");
                Reset("Reset", "The RESET button (or Ctrl+F12 or Ctrl+Break): BASIC starts again with the program kept");
                break;
            case "bbc":
                Code("Escape", 27, "ESCAPE (or Esc)");
                Code("Copy", 0x87, "COPY (or End): copies the character under the copy cursor");
                Reset("Break", "BREAK (or Ctrl+F12 or Ctrl+Break): the MOS starts again, keeping the program; OLD brings it back");
                break;
        }

        // The keyboard's hint, as the panel writes it under the screen.
        string hint = board
            ? "Ctrl+letter: control character · Ctrl+F12: RESET · left/right Alt: game-port buttons 0 and 1 · letters arrive as capitals"
            : machine switch
            {
                "apple2" => "Ctrl+letter: control character · Ctrl+F12: CONTROL-RESET · left/right Alt: Open/Closed Apple",
                "trs80-model1" or "trs80-model3" or "coco" => "Esc: BREAK · Home: CLEAR · arrows: the arrow keys · Ctrl+F12: reset",
                "trs80-model2" => "Esc: BREAK · Ctrl+letter: control character · arrows: the arrow keys · Ctrl+F12: reset",
                "pet" => "Esc: STOP · Home: HOME · arrows: the cursor keys · Backspace: DEL · Insert: INST · Tab: TAB (business keyboard) · Ctrl+F12: reset",
                "kaypro2" => "Ctrl+letter: control character · Esc: ESC · arrows: the arrow keys · Ctrl+F12: reset",
                "trs80-model100" => "Ctrl+letter: CTRL (but Ctrl+H, I and M: DEL, TAB, ENTER) · Esc: ESC · arrows: the arrow keys · F1-F8: the function keys · Pause: PAUSE · Ctrl+F12: RESET",
                "apple3" => "Ctrl+letter: control character · arrows and Esc: the arrow and ESCAPE keys · Ctrl+F12: CONTROL-RESET · left/right Alt: Open/Solid Apple",
                "apple1" => "Backspace: the back arrow (_) · Esc: ESC · Ctrl+F12: RESET · letters arrive as capitals",
                "altair" => "Ctrl+letter: control character · arrows: ^H ^J ^K ^L, as the ADM-3A sends them · Ctrl+F12: RESET",
                "bbc" => "Esc: ESCAPE · End: COPY · arrows: the cursor keys · F1-F9 and F10: f1-f9 and f0 · Ctrl+F12: BREAK",
                "atari800" => "Backspace: BACK S · Home: CLEAR · arrows: the cursor keys · F2-F4: START, SELECT, OPTION · Pause: BREAK · Ctrl+F12: power",
                _ => "",
            };

        ToolTip.SetTip(_keyboardStatus, hint + " · right-click or Shift+Insert: paste · Ctrl+Shift+E: the pane");
        PaintKeys();
    }

    // The latched keys show as down, in the accent colour, as the panel's pressed buttons do.
    private void PaintKeys()
    {
        void Paint(FlatButton? key, bool down)
        {
            if (key is null) { return; }
            key.DownColour = Palette.Button;
            key.Down = down;
            if (key.Child is TextBlock text)
            {
                text.Themed(TextBlock.ForegroundProperty, down ? Palette.ButtonText : Palette.StatusText);
            }
        }

        Paint(_ctrlKey, _screen.StickyControl);
        Paint(_appleKeys[0], _screen.IsDown(0));
        Paint(_appleKeys[1], _screen.IsDown(1));
    }

    private void Refresh()
    {
        MachineHost host = _session.Host;
        string keysFor = $"{host.KeyMapName}|{host.Model}|{host.GetHashCode()}";
        if (keysFor != _keysFor)
        {
            _keysFor = keysFor;
            BuildKeys(host);
        }

        _machinePane.Refresh();
        bool running = host.Running;
        _off.IsVisible = !running;
        _keys.IsVisible = running;
        _offText.Text = $"{host.Name} is off.\nCards and media changed now are there when it starts.";

        string state = !running ? "off" : host.Stopped is null ? "running" : "stopped: press Reset";
        List<string> parts = [host.Name, state];
        if (running)
        {
            parts.Add($"{host.MeasuredHertz / 1_000_000:0.00} MHz");
            if (host.Accelerated) { parts.Add(host.FastDriveKind == "tape" ? "fast tape" : "fast disk"); }
            parts.Add($"{_screen.Stats.FramesPerSecond} fps");
            if (host.DeviceStates().FirstOrDefault(drive => drive.Activity != DeviceActivity.Idle) is { } busy)
            {
                parts.Add($"{busy.Info.Name}: {busy.Activity.ToString().ToLowerInvariant()}");
            }

            if (host.MouseSlot is > 0 and var slot)
            {
                parts.Add($"mouse card in slot {slot} · the pointer over the screen is its mouse");
            }
        }

        _status.Text = string.Join(" · ", parts);
    }

    /// <inheritdoc/>
    /// <remarks>
    ///  <para>
    ///   The machine holds still first, so it cannot change a disk as the window closes. A disk with changes not
    ///   saved to its image then asks, as closing would lose them; the window closes once each is saved or let go.
    ///   One close asks at a time, and not while Stop, Restart or another change asks: a close request then waits on
    ///   its answer.
    ///  </para>
    /// </remarks>
    protected override void OnClosing(WindowClosingEventArgs e)
    {
        base.OnClosing(e);
        if (_mayClose) { return; }
        if (_closing || _machinePane.Busy)
        {
            e.Cancel = true;
            return;
        }

        _machinePane.Hold();
        if (!_machinePane.HasUnsaved) { return; }
        e.Cancel = true;
        _ = CloseAfterAsking();
    }

    private async Task CloseAfterAsking()
    {
        _closing = true;
        try
        {
            if (!await _machinePane.ReleaseMedia("closing")) { return; }
            _mayClose = true;
        }
        finally
        {
            _closing = false;
        }

        Close();
    }

    /// <inheritdoc/>
    protected override void OnClosed(EventArgs e)
    {
        _refresh.Stop();
        base.OnClosed(e);
    }
}