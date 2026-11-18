// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Machines.Commodore;

/// <summary>
///  What backs a CPU address on the PET.
/// </summary>
public enum PetMemoryArea
{
    /// <summary>
    ///  Nothing answers: past the RAM, the upper half of <c>$8000-$8FFF</c>, or an empty ROM socket.
    /// </summary>
    None,

    /// <summary>
    ///  RAM, from <c>$0000</c>.
    /// </summary>
    Ram,

    /// <summary>
    ///  The 1K of video RAM at <c>$8000-$83FF</c>, repeated to <c>$87FF</c>.
    /// </summary>
    VideoRam,

    /// <summary>
    ///  BASIC, <c>$C000-$DFFF</c> and its end in the editor's chip.
    /// </summary>
    Basic,

    /// <summary>
    ///  The screen editor, the rest of <c>$E000-$E7FF</c>.
    /// </summary>
    Editor,

    /// <summary>
    ///  The kernal, <c>$F000-$FFFF</c>.
    /// </summary>
    Kernal,

    /// <summary>
    ///  The PIAs and the VIA, <c>$E800-$EFFF</c>.
    /// </summary>
    Io,

    /// <summary>
    ///  An option ROM, <c>$9000-$BFFF</c>.
    /// </summary>
    OptionRom
}
