// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using Avalonia;
using Avalonia.Controls;
using Avalonia.Controls.Primitives;
using Avalonia.Layout;
using Avalonia.Media;

namespace Retrocore.Desktop;

/// <summary>
///  An icon in the activity bar: bright with a bar beside it while its view is shown, dimmed otherwise, as VS Code
///  draws its own.
/// </summary>
internal sealed class ActivityButton : Button
{
    private readonly Control _icon;
    private readonly Border _indicator = new() { Width = 2, HorizontalAlignment = HorizontalAlignment.Left };

    /// <summary>
    ///  Creates the icon.
    /// </summary>
    /// <param name="icon">
    ///  The icon: a <see cref="PathIcon"/> or a <see cref="TextBlock"/>, coloured from the theme.
    /// </param>
    /// <param name="name">The view's name, for the tooltip.</param>
    internal ActivityButton(Control icon, string name)
    {
        _icon = icon;
        _icon.HorizontalAlignment = HorizontalAlignment.Center;
        _icon.VerticalAlignment = VerticalAlignment.Center;
        _indicator.Themed(Border.BackgroundProperty, Palette.ActivityBorder);
        Content = new Grid { Width = 48, Height = 48, Children = { _indicator, _icon } };
        Width = 48;
        Height = 48;
        Padding = new Thickness(0);
        Background = Brushes.Transparent;
        BorderThickness = new Thickness(0);
        CornerRadius = new CornerRadius(0);
        Focusable = false;
        ToolTip.SetTip(this, name);
        Active = false;
    }

    /// <summary>
    ///  Gets or sets whether the icon's view is the one shown.
    /// </summary>
    internal bool Active
    {
        get => _indicator.IsVisible;
        set
        {
            _indicator.IsVisible = value;
            _icon.Themed(_icon is TextBlock ? TextBlock.ForegroundProperty : TemplatedControl.ForegroundProperty, value ? Palette.ActivityActive : Palette.ActivityInactive);
        }
    }
}