// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Machines.Atari;

/// <summary>
///  An Atari 400 or 800.
/// </summary>
public enum AtariModel
{
    /// <summary>
    ///  The Atari 800: two cartridge slots, three memory module slots (48 KB by default) and a full-stroke keyboard.
    /// </summary>
    Atari800,

    /// <summary>
    ///  The Atari 400: one cartridge slot, 16 KB on its fixed board (48 KB with an upgrade) and a membrane keyboard.
    /// </summary>
    Atari400
}
