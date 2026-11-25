// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Machines.Trs80;

/// <summary>
///  How <see cref="Trs80Keyboard.Type"/> presses a letter's key, as the ROM's keyboard driver reads shift with it.
/// </summary>
internal enum Trs80TypedLetters : byte
{
    /// <summary>
    ///  Level II on the Model I: an uppercase letter alone, a lowercase one with shift, and ` as shift and @.
    /// </summary>
    ShiftForLowercase,

    /// <summary>
    ///  Level II on the Model III, 4 and 4P, and their DOSes: an uppercase letter with shift, a lowercase one alone,
    ///  and ` as shift and @.
    /// </summary>
    ShiftForUppercase,

    /// <summary>
    ///  Level I, which reads shift and a letter as its control code: every letter alone, so it comes out in
    ///  uppercase; ` has no key.
    /// </summary>
    Unshifted
}
