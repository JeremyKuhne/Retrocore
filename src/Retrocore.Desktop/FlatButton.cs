// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using Avalonia;
using Avalonia.Automation;
using Avalonia.Automation.Peers;
using Avalonia.Controls;
using Avalonia.Input;
using Avalonia.Layout;
using Avalonia.Media;

namespace Retrocore.Desktop;

/// <summary>
///  A button drawn in VS Code's colours: a background of the theme's at rest and another under the pointer, and the
///  focus outline while it has the keyboard. Fluent's own button draws its hover in its own colours, which VS Code's
///  icon buttons, status bar items and dialog buttons do not have.
/// </summary>
internal sealed class FlatButton : Border
{
    private string? _rest;
    private string _hover;
    private bool _pressed;

    /// <summary>
    ///  Creates a button.
    /// </summary>
    /// <param name="content">What it shows.</param>
    /// <param name="name">Its name, for its tooltip and a screen reader.</param>
    /// <param name="rest">The theme colour of its background at rest, or null for none.</param>
    /// <param name="hover">The theme colour of its background under the pointer.</param>
    internal FlatButton(Control content, string name, string? rest, string hover)
    {
        _rest = rest;
        _hover = hover;
        Child = content;
        Focusable = true;
        Cursor = new Cursor(StandardCursorType.Arrow);
        BorderThickness = new Thickness(1);
        BorderBrush = Brushes.Transparent;
        AutomationProperties.SetName(this, name);
        ToolTip.SetTip(this, name);
        PointerEntered += (_, _) => Paint();
        PointerExited += (_, _) =>
        {
            _pressed = false;
            Paint();
        };

        GotFocus += (_, _) => Paint();
        LostFocus += (_, _) => Paint();
        Paint();
    }

    /// <summary>
    ///  Raised when the button is clicked or pressed from the keyboard.
    /// </summary>
    internal event EventHandler? Click;

    /// <summary>
    ///  Gets or sets whether it shows as down, as a latched key does.
    /// </summary>
    internal bool Down
    {
        get;
        set
        {
            field = value;
            Paint();
        }
    }

    /// <summary>
    ///  Gets or sets the colour shown while <see cref="Down"/>, or null to show its hover colour.
    /// </summary>
    internal string? DownColour { get; set; }

    /// <summary>
    ///  Makes a 22 pixel icon button, as a tree row's or a section's actions are.
    /// </summary>
    /// <param name="icon">The Codicon.</param>
    /// <param name="name">What it does.</param>
    /// <returns>The button.</returns>
    internal static FlatButton Icon(string icon, string name) => new(Codicon.Create(icon), name, rest: null, Palette.ToolbarHover)
    {
        Width = 22,
        Height = 22,
        Padding = new Thickness(2),
        CornerRadius = new CornerRadius(5),
        Focusable = false,
        VerticalAlignment = VerticalAlignment.Center,
    };

    /// <summary>
    ///  Makes a text button, as VS Code's dialogs and the display panel draw them: the primary in the accent colour,
    ///  the others secondary.
    /// </summary>
    /// <param name="text">The button's text.</param>
    /// <param name="primary">Whether it is the primary button.</param>
    /// <param name="name">Its tooltip, if not its text.</param>
    /// <returns>The button.</returns>
    internal static FlatButton Text(string text, bool primary, string? name = null)
    {
        TextBlock label = new TextBlock
        {
            Text = text,
            FontSize = 13,
            HorizontalAlignment = HorizontalAlignment.Center,
            VerticalAlignment = VerticalAlignment.Center,
        }.Themed(TextBlock.ForegroundProperty, primary ? Palette.ButtonText : Palette.SecondaryButtonText);

        FlatButton button = new(label, text, primary ? Palette.Button : Palette.SecondaryButton, primary ? Palette.ButtonHover : Palette.SecondaryButtonHover)
        {
            MinWidth = 70,
            Height = 26,
            Padding = new Thickness(12, 0),
            CornerRadius = new CornerRadius(2),
        };

        if (name is not null) { ToolTip.SetTip(button, name); }
        return button;
    }

    /// <summary>
    ///  Sets the colours.
    /// </summary>
    /// <param name="rest">At rest, or null for none.</param>
    /// <param name="hover">Under the pointer.</param>
    internal void SetColours(string? rest, string hover)
    {
        _rest = rest;
        _hover = hover;
        Paint();
    }

    /// <inheritdoc/>
    protected override void OnPointerPressed(PointerPressedEventArgs e)
    {
        base.OnPointerPressed(e);
        if (!e.GetCurrentPoint(this).Properties.IsLeftButtonPressed) { return; }
        _pressed = true;
        e.Handled = true;
    }

    /// <inheritdoc/>
    protected override void OnPointerReleased(PointerReleasedEventArgs e)
    {
        base.OnPointerReleased(e);
        if (!_pressed) { return; }
        _pressed = false;
        e.Handled = true;
        if (IsPointerOver) { Click?.Invoke(this, EventArgs.Empty); }
    }

    /// <inheritdoc/>
    protected override void OnKeyDown(KeyEventArgs e)
    {
        base.OnKeyDown(e);
        if (e.Key is Key.Enter or Key.Space && e.KeyModifiers == KeyModifiers.None)
        {
            e.Handled = true;
            Click?.Invoke(this, EventArgs.Empty);
        }
    }

    /// <inheritdoc/>
    protected override AutomationPeer OnCreateAutomationPeer() => new FlatButtonPeer(this);

    /// <summary>
    ///  Clicks the button, as a screen reader presses it.
    /// </summary>
    internal void Press() => Click?.Invoke(this, EventArgs.Empty);

    private void Paint()
    {
        string? background = Down ? DownColour ?? _hover : IsPointerOver ? _hover : _rest;
        if (background is null)
        {
            Background = Brushes.Transparent;
        }
        else
        {
            this.Themed(BackgroundProperty, background);
        }

        if (IsFocused && Focusable)
        {
            this.Themed(BorderBrushProperty, Palette.Focus);
        }
        else
        {
            BorderBrush = Brushes.Transparent;
        }
    }

}