// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Machines.Kaypro;

/// <summary>
///  What an address reaches on the Kaypro II.
/// </summary>
public enum KayproMemoryArea
{
    /// <summary>
    ///  The 2K monitor ROM at $0000, with $0800-$2FFF reading zero, while the system port's bit 7 is set.
    ///  Writes there are lost.
    /// </summary>
    Rom,

    /// <summary>
    ///  The 4K of video RAM at $3000, while the ROM is banked in.
    /// </summary>
    Video,

    /// <summary>
    ///  The 64K of RAM.
    /// </summary>
    Ram
}
