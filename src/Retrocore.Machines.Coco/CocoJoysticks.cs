// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Machines.Coco;

/// <summary>
///  The Color Computer's two joysticks, read through the DAC and a comparator: PIA 0's CA2 and CB2 pick an axis,
///  the program sets the DAC, and PIA 0's PA7 reads high while the axis is at or above it.
/// </summary>
/// <remarks>
///  <para>
///   Each axis runs 0 to 63, centered at 32. The right joystick's button pulls PA0 low and the left one's PA1; a
///   CoCo 3 joystick's second button pulls PA2 (right) or PA3 (left). The buttons share those lines with the
///   keyboard's rows.
///  </para>
/// </remarks>
public sealed class CocoJoysticks
{
    private readonly int[] _axes = [32, 32, 32, 32];
    private int _buttons;

    /// <summary>
    ///  Sets a joystick's position.
    /// </summary>
    /// <param name="left">Whether it is the left joystick rather than the right.</param>
    /// <param name="x">The horizontal position, 0 (left) to 63 (right).</param>
    /// <param name="y">The vertical position, 0 (up) to 63 (down).</param>
    public void Set(bool left, int x, int y)
    {
        int index = left ? 2 : 0;
        _axes[index] = Math.Clamp(x, 0, 63);
        _axes[index + 1] = Math.Clamp(y, 0, 63);
    }

    /// <summary>
    ///  Presses or releases a joystick's button.
    /// </summary>
    /// <param name="left">Whether it is the left joystick rather than the right.</param>
    /// <param name="second">Whether it is the CoCo 3 joystick's second button.</param>
    /// <param name="pressed">Whether it is down.</param>
    public void SetButton(bool left, bool second, bool pressed)
    {
        int bit = (left ? 2 : 1) << (second ? 2 : 0);
        _buttons = pressed ? _buttons | bit : _buttons & ~bit;
    }

    /// <summary>
    ///  Gets the PIA 0 port A lines the buttons pull low, as a mask.
    /// </summary>
    public byte Buttons => (byte)_buttons;

    /// <summary>
    ///  Gets an axis by the multiplexer's selection: 0 right X, 1 right Y, 2 left X, 3 left Y.
    /// </summary>
    /// <param name="selection">CA2 in bit 0 and CB2 in bit 1.</param>
    /// <returns>The axis, 0-63.</returns>
    public int Axis(int selection) => _axes[selection & 3];
}
