// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Machines.Trs80Model100;

/// <summary>
///  What backs a Model 100 address.
/// </summary>
public enum Trs80Model100MemoryArea
{
    /// <summary>
    ///  Nothing: addresses below the RAM fitted, and the option ROM's socket when it is empty, read $FF.
    /// </summary>
    None,

    /// <summary>
    ///  The main ROM, at $0000-$7FFF.
    /// </summary>
    Rom,

    /// <summary>
    ///  The option ROM, at $0000-$7FFF while port $E0 bit 0 selects it.
    /// </summary>
    OptionRom,

    /// <summary>
    ///  RAM, from $FFFF down.
    /// </summary>
    Ram
}
