// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Machines.Atari;

/// <summary>
///  The console keys, as <c>CONSOL</c>'s bits.
/// </summary>
[Flags]
public enum AtariConsoleKeys : byte
{
    /// <summary>
    ///  None held.
    /// </summary>
    None = 0,

    /// <summary>
    ///  START.
    /// </summary>
    Start = 1,

    /// <summary>
    ///  SELECT.
    /// </summary>
    Select = 2,

    /// <summary>
    ///  OPTION.
    /// </summary>
    Option = 4
}
