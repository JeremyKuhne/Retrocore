// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using Avalonia;
using Avalonia.Controls;
using Avalonia.Input;
using Avalonia.Media;
using Avalonia.Media.Imaging;
using Avalonia.Platform;

namespace Retrocore.Desktop;

/// <summary>
///  The machine's screen: draws its latest frame on each of the display's frames, scaled sharp or to fit, and types
///  the keys pressed while it has the focus.
/// </summary>
/// <remarks>
///  <para>
///   The frame goes into a bitmap the control owns, which Avalonia's compositor draws with Skia on the GPU. Each
///   display frame asks for the next with <see cref="TopLevel.RequestAnimationFrame"/>, so drawing keeps to the
///   display's rate rather than a timer's.
///  </para>
/// </remarks>
internal sealed class ScreenView : Control
{
    private readonly MachineHost _host;
    private WriteableBitmap? _bitmap;
    private long _frameSeen;
    private bool _animating;

    /// <summary>
    ///  Creates the screen for a machine.
    /// </summary>
    /// <param name="host">The running machine.</param>
    internal ScreenView(MachineHost host)
    {
        _host = host;
        Focusable = true;
        ClipToBounds = true;
        RenderOptions.SetBitmapInterpolationMode(this, BitmapInterpolationMode.None);
        ActualThemeVariantChanged += (_, _) => InvalidateVisual();
    }

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

        // The picture has its monitor's shape, as the display panel gives it: the Apple II's 560 by 192 dots fill a
        // 280 by 192 shape, so each line is drawn twice; the TRS-80's fill 4 by 3.
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

        Rect destination = new(new Point((Bounds.Width - size.Width) / 2, (Bounds.Height - size.Height) / 2), size);
        context.DrawImage(bitmap, new Rect(0, 0, bitmap.PixelSize.Width, bitmap.PixelSize.Height), destination);
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
    }

    /// <inheritdoc/>
    protected override void OnKeyDown(KeyEventArgs e)
    {
        if (KeyMap.Code(_host.KeyMapName, e.Key, e.KeyModifiers) is { } code)
        {
            _host.Key(code);
            e.Handled = true;
            return;
        }

        base.OnKeyDown(e);
    }

    /// <inheritdoc/>
    protected override void OnTextInput(TextInputEventArgs e)
    {
        foreach (char character in e.Text ?? "")
        {
            if (character is > (char)0 and < (char)127 and not '\r' and not '\n' and not '\b' and not '\t')
            {
                _host.Key(character);
            }
        }

        e.Handled = true;
    }
}