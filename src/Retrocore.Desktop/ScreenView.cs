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

    // The mouse card's mouse: whether its button is down, and whether the pointer is hidden over the picture while
    // the program has the mouse on and draws its own.
    private bool _mouseDown;
    private bool _pointerHidden;
    private static readonly Cursor s_hidden = new(StandardCursorType.None);

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
            _mouseDown = false;
            HidePointer(hide: false);
            KeysChanged?.Invoke(this, EventArgs.Empty);
            InvalidateVisual();
        };
    }

    /// <summary>
    ///  Raised when a latched key changes: Ctrl after the letter it applied to, or an Apple key.
    /// </summary>
    internal event EventHandler? KeysChanged;

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
    ///  Gets or sets the space the sharp picture is sized for, which the window sets from its own size so the picture
    ///  changes with the window and not with the chrome's zoom; null to size it for the control.
    /// </summary>
    /// <remarks>
    ///  <para>
    ///   A sharp picture is centred in the control, and clipped if zoomed chrome leaves less room.
    ///   Fit mode uses the control's actual bounds so that the complete picture remains visible.
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
        Rect destination = PictureBounds;
        if (!_host.Running) { context.FillRectangle(Brushes.Black, destination); }
        using (context.PushOpacity(_host.Running ? 1 : 0.35))
        {
            context.DrawImage(bitmap, new Rect(0, 0, bitmap.PixelSize.Width, bitmap.PixelSize.Height), destination);
        }

    }

    /// <summary>
    ///  Gets the picture's rectangle in control coordinates, preserving the machine's monitor aspect ratio.
    /// </summary>
    internal Rect PictureBounds => _bitmap is { } bitmap ? PictureRect(bitmap) : default;

    // The Apple II's 560 by 192 dots fill a 280 by 192 shape, and the TRS-80's fill 4 by 3.
    private Rect PictureRect(WriteableBitmap bitmap)
    {
        double width = bitmap.PixelSize.Width;
        double aspect = Aspect(_host.KeyMapName);
        double height = width / aspect;
        Size area = Sharp ? SizingArea ?? Bounds.Size : Bounds.Size;
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
        "bbc" => (704, 576),
        _ => (560, 384),
    };

    // The width to height of each machine's picture, as the display panel's aspect map has them.
    private static double Aspect(string machine) => machine switch
    {
        "trs80-model1" or "trs80-model3" or "trs80-model2" or "coco" or "altair" => 4.0 / 3.0,
        "bbc" => 704.0 / 576.0,
        _ => 280.0 / 192.0,
    };

    /// <inheritdoc/>
    protected override void OnPointerPressed(PointerPressedEventArgs e)
    {
        base.OnPointerPressed(e);
        Focus();
        if (!e.GetCurrentPoint(this).Properties.IsLeftButtonPressed || !OverPicture(e)) { return; }

        // The left button over the picture is the card's. Avalonia captures the pointer while it is down, so its
        // release comes here wherever the pointer is.
        if (PlaceMouse(e, pressed: true))
        {
            _mouseDown = true;
            e.Handled = true;
        }
    }

    /// <inheritdoc/>
    protected override void OnPointerReleased(PointerReleasedEventArgs e)
    {
        base.OnPointerReleased(e);
        if (!_mouseDown || e.InitialPressMouseButton != MouseButton.Left) { return; }
        _mouseDown = false;
        PlaceMouse(e, pressed: false);
    }

    /// <inheritdoc/>
    protected override void OnPointerMoved(PointerEventArgs e)
    {
        base.OnPointerMoved(e);
        PlaceMouse(e);
    }

    /// <inheritdoc/>
    protected override void OnPointerExited(PointerEventArgs e)
    {
        base.OnPointerExited(e);
        HidePointer(hide: false);
    }

    // The mouse card: the pointer stands for the card's mouse, its place in the picture the mouse's place within the
    // bounds the program set, so the mouse is wherever the pointer is and never drifts from it. Off the picture, as
    // over the space around it or in a drag that leaves the window, the mouse stays at the picture's nearest edge.
    private bool PlaceMouse(PointerEventArgs e, bool? pressed = null)
    {
        if (_host.MouseSlot == 0 || !_host.Running || _bitmap is null)
        {
            HidePointer(hide: false);
            return false;
        }

        Rect picture = PictureBounds;
        Point at = e.GetPosition(this);
        bool on = _host.PlaceMouse(
            (at.X - picture.X) / Math.Max(1, picture.Width),
            (at.Y - picture.Y) / Math.Max(1, picture.Height),
            pressed);

        // The program draws its own pointer once it turns the mouse on, so the window's is hidden over the picture.
        HidePointer(on && picture.Contains(at));
        return true;
    }

    private bool OverPicture(PointerEventArgs e) => _bitmap is not null && PictureBounds.Contains(e.GetPosition(this));

    private void HidePointer(bool hide)
    {
        if (hide == _pointerHidden) { return; }
        _pointerHidden = hide;
        Cursor = hide ? s_hidden : Cursor.Default;
    }

    /// <inheritdoc/>
    protected override void OnLostFocus(FocusChangedEventArgs e)
    {
        base.OnLostFocus(e);

        // A button let go while another window has the pointer never says so, so the card's button lets go here.
        if (_mouseDown)
        {
            _mouseDown = false;
            _host.PlaceMouse(across: null, down: null, pressed: false);
        }

        // A key let go while the screen lacks the keyboard never says so, so a held Apple key lets go here.
        for (int button = 0; button < 2; button++)
        {
            if (!_held[button]) { continue; }
            _held[button] = false;
            SendButton(button);
        }
    }

    private void SendButton(int button)
    {
        _host.Button(button, IsDown(button));
        KeysChanged?.Invoke(this, EventArgs.Empty);
    }

    /// <inheritdoc/>
    protected override void OnKeyDown(KeyEventArgs e)
    {
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