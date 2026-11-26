// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Machines.Commodore;

/// <summary>
///  The switches of a Commodore (Atari-style) joystick, each closed while held, as the VIC-20 and the 64 read them.
/// </summary>
[Flags]
public enum CommodoreJoystick
{
    /// <summary>
    ///  Centred, with the button up.
    /// </summary>
    None = 0,

    /// <summary>
    ///  Up.
    /// </summary>
    Up = 1,

    /// <summary>
    ///  Down.
    /// </summary>
    Down = 2,

    /// <summary>
    ///  Left.
    /// </summary>
    Left = 4,

    /// <summary>
    ///  Right.
    /// </summary>
    Right = 8,

    /// <summary>
    ///  The fire button.
    /// </summary>
    Fire = 16
}
