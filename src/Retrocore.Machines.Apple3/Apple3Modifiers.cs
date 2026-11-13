// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Machines.Apple3;

/// <summary>
///  The Apple III keyboard's modifier keys, which the firmware reads at <c>$C008</c>.
/// </summary>
[Flags]
public enum Apple3Modifiers
{
    /// <summary>
    ///  None held.
    /// </summary>
    None = 0,

    /// <summary>
    ///  Either SHIFT key.
    /// </summary>
    Shift = 1,

    /// <summary>
    ///  CONTROL.
    /// </summary>
    Control = 2,

    /// <summary>
    ///  ALPHA LOCK, down.
    /// </summary>
    AlphaLock = 4,

    /// <summary>
    ///  The Open Apple key.
    /// </summary>
    OpenApple = 8,

    /// <summary>
    ///  The Solid Apple key.
    /// </summary>
    SolidApple = 16
}
