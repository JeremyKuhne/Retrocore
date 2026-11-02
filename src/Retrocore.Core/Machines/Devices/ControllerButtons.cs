// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Machines.Devices;

/// <summary>
///  The buttons of a modern controller, by position, so an Xbox and a PlayStation controller read alike.
/// </summary>
[Flags]
public enum ControllerButtons
{
    /// <summary>
    ///  No button.
    /// </summary>
    None = 0,

    /// <summary>
    ///  The bottom face button: A on an Xbox controller, Cross on a PlayStation controller.
    /// </summary>
    South = 1 << 0,

    /// <summary>
    ///  The right face button: B on an Xbox controller, Circle on a PlayStation controller.
    /// </summary>
    East = 1 << 1,

    /// <summary>
    ///  The left face button: X on an Xbox controller, Square on a PlayStation controller.
    /// </summary>
    West = 1 << 2,

    /// <summary>
    ///  The top face button: Y on an Xbox controller, Triangle on a PlayStation controller.
    /// </summary>
    North = 1 << 3,

    /// <summary>
    ///  The d-pad's up.
    /// </summary>
    Up = 1 << 4,

    /// <summary>
    ///  The d-pad's down.
    /// </summary>
    Down = 1 << 5,

    /// <summary>
    ///  The d-pad's left.
    /// </summary>
    Left = 1 << 6,

    /// <summary>
    ///  The d-pad's right.
    /// </summary>
    Right = 1 << 7
}
