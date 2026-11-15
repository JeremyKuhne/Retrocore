// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using Avalonia;
using Avalonia.Controls;
using Avalonia.Input;
using Avalonia.Input.Platform;
using Avalonia.Media;
using Avalonia.Media.Imaging;
using Avalonia.Platform;
using Avalonia.Threading;
using System.Diagnostics;
using System.Runtime.Versioning;

namespace Retrocore.Desktop;

/// <summary>
///  The machine's screen: draws its latest frame on each of the display's frames, scaled sharp or to fit, and types
///  the keys pressed while it has the focus, with the display panel's special keys: Ctrl+F12 or Ctrl+Break for reset,
///  the Alt keys for the Apple keys, Shift+Insert to paste, and a click to give the mouse to a mouse card.
/// </summary>
/// <remarks>
///  <para>
///   The frame goes into a bitmap the control owns, which Avalonia's compositor draws with Skia on the GPU. Each
///   display frame asks for the next with <see cref="TopLevel.RequestAnimationFrame"/>, so drawing keeps to the
///   display's rate rather than a timer's. A machine switched for another keeps the last picture until the new one
///   draws, and an off machine's is dimmed, as the panel dims a session that ended.
///  </para>
/// </remarks>
internal sealed class ScreenView : Control
{
    private readonly MachineSession _session;
    private MachineHost _host;
    private WriteableBitmap? _bitmap;
    private long _frameSeen;
    private bool _animating;

    // The Apple keys or game-port buttons: held by an Alt key, or latched by the status bar's buttons.
    private readonly bool[] _held = new bool[2];
    private readonly bool[] _latched = new bool[2];

    // The mouse card's mouse, while it has the pointer: where the pointer is, the part of a dot not yet sent, and
    // the pointer itself, captured while a button is down.
    private Point? _mouseAt;
    private IPointer? _mousePointer;

    // On Windows, where the pointer last was in screen pixels, read from Windows rather than from the move events,
    // which can be older than the last time the pointer was put back.
    private int _cursorX;
    private int _cursorY;
    private bool _releasing;

    // When the mouse card took the pointer, for the note that says how to let it go.
    private long _capturedAt;
    private double _mouseX;
    private double _mouseY;

    /// <summary>
    ///  Creates the screen for a machine.
    /// </summary>
    /// <param name="session">The machine.</param>
    internal ScreenView(MachineSession session)
    {
        _session = session;
        _host = session.Host;
        Focusable = true;
        ClipToBounds = true;
        RenderOptions.SetBitmapInterpolationMode(this, BitmapInterpolationMode.None);
        ActualThemeVariantChanged += (_, _) => InvalidateVisual();
        session.Changed += (_, _) =>
        {
            if (_session.Host == _host) { return; }

            // Another machine, or the same one built again: the last picture stays until its first frame.
            _host = _session.Host;
            _frameSeen = 0;
            Array.Clear(_held);
            Array.Clear(_latched);
            ReleaseMouse();
            KeysChanged?.Invoke(this, EventArgs.Empty);
            InvalidateVisual();
        };
    }

    /// <summary>
    ///  Raised when a latched key changes: Ctrl after the letter it applied to, or an Apple key.
    /// </summary>
    internal event EventHandler? KeysChanged;

    /// <summary>
    ///  Raised when the mouse card takes the pointer or gives it back.
    /// </summary>
    internal event EventHandler? MouseChanged;

    /// <summary>
    ///  Raised when the screen asks for the clipboard's text to be typed, as Shift+Insert or Paste does.
    /// </summary>
    internal event EventHandler? PasteRequested;

    /// <summary>
    ///  Gets or sets whether each dot is drawn as a whole number of screen pixels (sharp) or the picture fills the
    ///  space (fit).
    /// </summary>
    internal bool Sharp { get; set; } = true;

    /// <summary>
    ///  Gets or sets the space the picture is sized for, which the window sets from its own size so the picture
    ///  changes with the window and not with the chrome's zoom; null to size it for the control.
    /// </summary>
    /// <remarks>
    ///  <para>
    ///   The picture is centred in the control, and clipped by it if the zoomed chrome leaves it a little less room.
    ///  </para>
    /// </remarks>
    internal Size? SizingArea { get; set; }

    /// <summary>
    ///  Gets the times between display frames, and the frames that drew a new picture.
    /// </summary>
    internal FrameStats Stats { get; } = new();

    /// <summary>
    ///  Gets whether there is a picture, as there is once a machine has drawn one.
    /// </summary>
    internal bool HasPicture => _bitmap is not null;

    /// <summary>
    ///  Gets or sets whether the next letter typed is a control character, as the panel's Ctrl button makes it.
    /// </summary>
    internal bool StickyControl
    {
        get;
        set
        {
            field = value;
            KeysChanged?.Invoke(this, EventArgs.Empty);
        }
    }

    /// <summary>
    ///  Gets whether the mouse card has the pointer.
    /// </summary>
    internal bool MouseCaptured => _mouseAt is not null;

    /// <summary>
    ///  Gets whether an Apple key or game-port button is down, held or latched.
    /// </summary>
    /// <param name="button">0 or 1.</param>
    /// <returns>True while it is down.</returns>
    internal bool IsDown(int button) => _held[button] || _latched[button];

    /// <summary>
    ///  Latches an Apple key or game-port button down, or lets it go, as the panel's buttons do.
    /// </summary>
    /// <param name="button">0 or 1.</param>
    internal void ToggleLatch(int button)
    {
        _latched[button] = !_latched[button];
        SendButton(button);
    }

    /// <summary>
    ///  Types a key, applying a latched Ctrl to a letter, as the panel's keys do.
    /// </summary>
    /// <param name="code">The ASCII code.</param>
    internal void Type(int code)
    {
        if (StickyControl)
        {
            if (code is >= 97 and <= 122) { code -= 32; }
            if (code is >= 64 and <= 95) { code &= 31; }
            StickyControl = false;
        }

        _host.Key(code);
    }

    /// <inheritdoc/>
    protected override void OnAttachedToVisualTree(VisualTreeAttachmentEventArgs e)
    {
        base.OnAttachedToVisualTree(e);
        _animating = true;
        TopLevel.GetTopLevel(this)?.RequestAnimationFrame(OnFrame);
    }

    /// <inheritdoc/>
    protected override void OnDetachedFromVisualTree(VisualTreeAttachmentEventArgs e)
    {
        _animating = false;
        base.OnDetachedFromVisualTree(e);
    }

    private void OnFrame(TimeSpan time)
    {
        if (!_animating) { return; }
        long seen = _frameSeen;
        _frameSeen = _host.TakeFrame(_frameSeen, Copy);
        Stats.Frame(time, drew: _frameSeen != seen);
        if (_frameSeen != seen) { InvalidateVisual(); }
        TopLevel.GetTopLevel(this)?.RequestAnimationFrame(OnFrame);
    }

    private void Copy(ReadOnlySpan<byte> pixels, int width, int height)
    {
        if (_bitmap is null || _bitmap.PixelSize.Width != width || _bitmap.PixelSize.Height != height)
        {
            _bitmap?.Dispose();
            _bitmap = new WriteableBitmap(new PixelSize(width, height), new Vector(96, 96), PixelFormat.Rgba8888, AlphaFormat.Opaque);
        }

        using ILockedFramebuffer buffer = _bitmap.Lock();
        int rowBytes = width * 4;
        for (int row = 0; row < height; row++)
        {
            Span<byte> target;
            unsafe { target = new Span<byte>((byte*)buffer.Address + (row * buffer.RowBytes), rowBytes); }
            pixels.Slice(row * rowBytes, rowBytes).CopyTo(target);
        }
    }

    /// <inheritdoc/>
    public override void Render(DrawingContext context)
    {
        // The space around the picture is the editor's background in the window's theme, as in VS Code's panel.
        IBrush surround = this.TryFindResource(Palette.Editor, ActualThemeVariant, out object? brush) && brush is IBrush themed
            ? themed
            : Brushes.Black;

        context.FillRectangle(surround, new Rect(Bounds.Size));
        if (_bitmap is not { } bitmap) { return; }

        // An off machine's last picture is dimmed over black, as a monitor's fading glass is, in either theme.
        Rect destination = PictureRect(bitmap);
        if (!_host.Running) { context.FillRectangle(Brushes.Black, destination); }
        using (context.PushOpacity(_host.Running ? 1 : 0.35))
        {
            context.DrawImage(bitmap, new Rect(0, 0, bitmap.PixelSize.Width, bitmap.PixelSize.Height), destination);
        }

        // While the mouse card has the pointer, the screen's border lights, as the panel's bezel does.
        if (MouseCaptured && this.TryFindResource(Palette.Focus, ActualThemeVariant, out object? focus) && focus is IBrush outline)
        {
            context.DrawRectangle(new Pen(outline, 2), destination.Inflate(1));
            if (Stopwatch.GetElapsedTime(_capturedAt) < s_noteTime) { DrawNote(context, destination); }
        }
    }

    // How long the note shows after the mouse card takes the pointer.
    private static readonly TimeSpan s_noteTime = TimeSpan.FromSeconds(3);

    // A note at the top of the picture, as a game says it has the mouse: in VS Code's widget colours.
    private void DrawNote(DrawingContext context, Rect picture)
    {
        IBrush background = this.TryFindResource(Palette.Widget, ActualThemeVariant, out object? widget) && widget is IBrush fill ? fill : Brushes.Black;
        IBrush text = this.TryFindResource(Palette.Text, ActualThemeVariant, out object? foreground) && foreground is IBrush ink ? ink : Brushes.White;
        FormattedText note = new(
            $"The mouse card in slot {_host.MouseSlot} has the mouse · press Esc to let it go",
            System.Globalization.CultureInfo.CurrentCulture,
            FlowDirection.LeftToRight,
            Typeface.Default,
            13,
            text);

        Rect box = new(picture.X + ((picture.Width - note.Width) / 2) - 12, picture.Y + 12, note.Width + 24, note.Height + 12);
        context.DrawRectangle(background, pen: null, box, 4, 4);
        context.DrawText(note, new Point(box.X + 12, box.Y + 6));
    }

    // Where the picture goes: its monitor's shape, as the display panel gives it, the Apple II's 560 by 192 dots
    // filling a 280 by 192 shape, so each line is drawn twice, and the TRS-80's filling 4 by 3.
    private Rect PictureRect(WriteableBitmap bitmap)
    {
        double width = bitmap.PixelSize.Width;
        double aspect = Aspect(_host.KeyMapName);
        double height = width / aspect;
        Size area = SizingArea ?? Bounds.Size;
        Size size;
        double device = TopLevel.GetTopLevel(this)?.RenderScaling ?? 1;
        (double across, double down) = SharpBase(_host.KeyMapName, width);
        double times = Math.Floor(Math.Min(area.Width * device / across, area.Height * device / down));
        if (Sharp && times >= 1)
        {
            // Whole device pixels for every dot and every line: the machine's sharp size at 1x, times the largest whole
            // number that fits. Too small a window for even 1x fits the picture instead, as the display panel does.
            size = new(across * times / device, down * times / device);
        }
        else
        {
            double scale = Math.Min(area.Width / width, area.Height / height);
            size = new(width * scale, height * scale);
        }

        return new Rect(new Point((Bounds.Width - size.Width) / 2, (Bounds.Height - size.Height) / 2), size);
    }

    // Each machine's picture at 1x in Sharp, in device pixels, as the display panel's sharpBase has them: each dot a
    // whole number of pixels across and down in the screen's shape. The IIe's rows are twice as tall as its dots are
    // wide; the Model I's dots are 2 wide by 3 tall; the CoCo 3's 704 dots by 249 lines show each line twice.
    private static (double Across, double Down) SharpBase(string machine, double width) => machine switch
    {
        "trs80-model1" => (768, 576),
        "trs80-model3" or "altair" => (640, 480),
        "trs80-model2" => (640, 576),
        "coco" => width == 704 ? (704, 498) : (640, 480),
        _ => (560, 384),
    };

    // The width to height of each machine's picture, as the display panel's aspect map has them.
    private static double Aspect(string machine) => machine switch
    {
        "trs80-model1" or "trs80-model3" or "trs80-model2" or "coco" or "altair" => 4.0 / 3.0,
        _ => 280.0 / 192.0,
    };

    /// <inheritdoc/>
    protected override void OnPointerPressed(PointerPressedEventArgs e)
    {
        base.OnPointerPressed(e);
        Focus();
        PointerPointProperties point = e.GetCurrentPoint(this).Properties;
        if (!point.IsLeftButtonPressed || !_host.Running || _host.MouseSlot == 0) { return; }

        // The mouse card: a click gives it the pointer, which it keeps until Escape or the window loses the keyboard,
        // and then the left button is the card's. The pointer is hidden and held at the screen's centre, so it never
        // stops at the window's edge.
        if (!MouseCaptured)
        {
            _mouseX = _mouseY = 0;
            _capturedAt = Stopwatch.GetTimestamp();
            Cursor = new Cursor(StandardCursorType.None);
            Hold(e.Pointer);
            Recentre(e.GetPosition(this));
            MouseChanged?.Invoke(this, EventArgs.Empty);
            InvalidateVisual();
            DispatcherTimer.RunOnce(InvalidateVisual, s_noteTime);
        }
        else
        {
            Hold(e.Pointer);
            _host.Mouse(0, 0, pressed: true);
        }

        e.Handled = true;
    }

    /// <inheritdoc/>
    protected override void OnPointerReleased(PointerReleasedEventArgs e)
    {
        base.OnPointerReleased(e);
        if (!MouseCaptured) { return; }
        if (e.InitialPressMouseButton == MouseButton.Left) { _host.Mouse(0, 0, pressed: false); }

        // Avalonia ends a capture when the buttons come up; the card keeps the pointer until Escape.
        IPointer pointer = e.Pointer;
        Dispatcher.UIThread.Post(() =>
        {
            if (MouseCaptured) { Hold(pointer); }
        });
    }

    /// <inheritdoc/>
    protected override void OnPointerCaptureLost(PointerCaptureLostEventArgs e)
    {
        base.OnPointerCaptureLost(e);

        // Anything else that takes the capture while the card has the pointer gives it back to the card, unless the
        // card is letting go.
        if (!MouseCaptured || _releasing) { return; }
        IPointer pointer = e.Pointer;
        Dispatcher.UIThread.Post(() =>
        {
            if (MouseCaptured && pointer.Captured is null) { Hold(pointer); }
        });
    }

    // Captures the pointer, so every move comes here whatever is under it, the side pane among them.
    private void Hold(IPointer pointer)
    {
        _mousePointer = pointer;
        if (pointer.Captured != this) { pointer.Capture(this); }
    }

    /// <inheritdoc/>
    protected override void OnPointerMoved(PointerEventArgs e)
    {
        base.OnPointerMoved(e);
        if (_mouseAt is not { } last || _bitmap is not { } bitmap) { return; }

        // Movement in the picture's 280 by 192 dots, as the panel sends it. On Windows it is read from where Windows
        // has the pointer, since a move event can come from before the pointer was last put back, and the hidden
        // pointer goes back to the picture's centre as it nears an edge, so it never stops there.
        Rect picture = PictureRect(bitmap);
        double across;
        double down;
        if (OperatingSystem.IsWindows())
        {
            if (!ReadCursor(out int x, out int y) || (x == _cursorX && y == _cursorY)) { return; }
            double scale = TopLevel.GetTopLevel(this)?.RenderScaling ?? 1;
            across = (x - _cursorX) / scale;
            down = (y - _cursorY) / scale;
            _cursorX = x;
            _cursorY = y;

            // Put back at the centre only once it nears the picture's edge, so few moves are lost to the putting back.
            PixelPoint centre = this.PointToScreen(picture.Center);
            if (Math.Abs(x - centre.X) > picture.Width * scale / 4 || Math.Abs(y - centre.Y) > picture.Height * scale / 4)
            {
                Recentre(picture.Center);
            }
        }
        else
        {
            Point at = e.GetPosition(this);
            if (at == last) { return; }
            across = at.X - last.X;
            down = at.Y - last.Y;
            _mouseAt = at;
        }

        _mouseX += across * 280 / Math.Max(1, picture.Width);
        _mouseY += down * 192 / Math.Max(1, picture.Height);
        int dx = (int)Math.Truncate(_mouseX);
        int dy = (int)Math.Truncate(_mouseY);
        _mouseX -= dx;
        _mouseY -= dy;
        if (dx != 0 || dy != 0) { _host.Mouse(dx, dy); }
    }

    /// <inheritdoc/>
    protected override void OnLostFocus(FocusChangedEventArgs e)
    {
        base.OnLostFocus(e);

        // Another window or control taking the keyboard takes the pointer back from the mouse card.
        ReleaseMouse();

        // A key let go while the screen lacks the keyboard never says so, so a held Apple key lets go here.
        for (int button = 0; button < 2; button++)
        {
            if (!_held[button]) { continue; }
            _held[button] = false;
            SendButton(button);
        }
    }

    // On Windows, keeps the hidden pointer inside the picture and puts it back at the picture's centre after each
    // move, so it never reaches an edge; elsewhere the capture alone keeps its moves coming here.
    private unsafe void Recentre(Point at)
    {
        _mouseAt = at;
        if (!OperatingSystem.IsWindows() || _bitmap is not { } bitmap) { return; }
        Rect picture = PictureRect(bitmap);
        PixelPoint topLeft = this.PointToScreen(picture.TopLeft);
        PixelPoint bottomRight = this.PointToScreen(picture.BottomRight);

        // Windows lets go of a clip when another window is activated, so it is set again with each move.
        int* clip = stackalloc int[] { topLeft.X, topLeft.Y, bottomRight.X, bottomRight.Y };
        NativeMethods.ClipCursor(clip);
        PixelPoint centre = this.PointToScreen(picture.Center);
        if (NativeMethods.SetCursorPos(centre.X, centre.Y)) { _mouseAt = picture.Center; }
        if (!ReadCursor(out _cursorX, out _cursorY))
        {
            _cursorX = centre.X;
            _cursorY = centre.Y;
        }
    }

    // Where the pointer is now, in screen pixels.
    [SupportedOSPlatform("windows")]
    private static unsafe bool ReadCursor(out int x, out int y)
    {
        int* point = stackalloc int[2];
        bool read = NativeMethods.GetCursorPos(point);
        x = point[0];
        y = point[1];
        return read;
    }

    // The mouse card gives the pointer back, its button up.
    private unsafe void ReleaseMouse()
    {
        if (!MouseCaptured) { return; }
        _mouseAt = null;
        IPointer? pointer = _mousePointer;
        _mousePointer = null;
        _releasing = true;
        if (pointer?.Captured == this) { pointer.Capture(control: null); }
        _releasing = false;
        if (OperatingSystem.IsWindows()) { NativeMethods.ClipCursor(rectangle: null); }
        Cursor = Cursor.Default;
        _host.Mouse(0, 0, pressed: false);
        MouseChanged?.Invoke(this, EventArgs.Empty);
        InvalidateVisual();
    }

    private void SendButton(int button)
    {
        _host.Button(button, IsDown(button));
        KeysChanged?.Invoke(this, EventArgs.Empty);
    }

    /// <inheritdoc/>
    protected override void OnKeyDown(KeyEventArgs e)
    {
        // Escape gives the pointer back from the mouse card, rather than going to the machine.
        if (e.Key == Key.Escape && MouseCaptured)
        {
            ReleaseMouse();
            e.Handled = true;
            return;
        }

        // The Alt keys hold the Apple keys, or the II's game-port buttons, while they are down.
        if (e.Key is Key.LeftAlt or Key.RightAlt && _host.HasButtons)
        {
            int button = e.Key == Key.LeftAlt ? 0 : 1;
            if (!_held[button])
            {
                _held[button] = true;
                SendButton(button);
            }

            e.Handled = true;
            return;
        }

        // Ctrl+F12 for keyboards without Break, which some laptops lack or hide behind Fn.
        if (e.Key == Key.Cancel || (e.KeyModifiers.HasFlag(KeyModifiers.Control) && e.Key is Key.Pause or Key.F12))
        {
            _host.Reset();
            e.Handled = true;
            return;
        }

        // Shift+Insert pastes, as the screen's Paste does. Ctrl+V is CONTROL-V, like any other Ctrl letter.
        if (e.Key == Key.Insert && e.KeyModifiers == KeyModifiers.Shift)
        {
            PasteRequested?.Invoke(this, EventArgs.Empty);
            e.Handled = true;
            return;
        }

        if (KeyMap.Code(_host.KeyMapName, e.Key, e.KeyModifiers) is { } code)
        {
            Type(code);
            e.Handled = true;
            return;
        }

        base.OnKeyDown(e);
    }

    /// <inheritdoc/>
    protected override void OnKeyUp(KeyEventArgs e)
    {
        if (e.Key is Key.LeftAlt or Key.RightAlt && _host.HasButtons)
        {
            int button = e.Key == Key.LeftAlt ? 0 : 1;
            _held[button] = false;
            SendButton(button);
            e.Handled = true;
            return;
        }

        base.OnKeyUp(e);
    }

    /// <inheritdoc/>
    protected override void OnTextInput(TextInputEventArgs e)
    {
        foreach (char character in e.Text ?? "")
        {
            if (character is > (char)0 and < (char)127 and not '\r' and not '\n' and not '\b' and not '\t')
            {
                Type(character);
            }
        }

        e.Handled = true;
    }

    /// <summary>
    ///  Types the clipboard's text, as the panel's Paste does.
    /// </summary>
    /// <returns>A task that completes once it is queued.</returns>
    internal async Task PasteAsync()
    {
        if (TopLevel.GetTopLevel(this)?.Clipboard is not { } clipboard) { return; }
        string? text = await clipboard.TryGetTextAsync();
        if (!string.IsNullOrEmpty(text)) { _host.Type(text); }
    }
}