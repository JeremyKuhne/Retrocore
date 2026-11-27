// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using Retrocore.Machines;
using Retrocore.Machines.Chips;
using Retrocore.Machines.Commodore.Vic20;

namespace Retrocore.Debug;

/// <summary>
///  The VIC-20's characters as the debugger draws and reads them.
/// </summary>
/// <remarks>
///  <para>
///   The dots come from wherever the VIC fetches them now, the character ROM or RAM, 8 or 16 lines tall. Text reads as
///   the character ROM's upper-case and graphics set or, with the VIC pointed at its lower-case half at <c>$8800</c>,
///   as that set. Codes from <c>$80</c> are the reversed copies of those below them.
///  </para>
/// </remarks>
/// <param name="machine">The machine.</param>
internal sealed class Vic20CharacterSet(Vic20Machine machine) : ICharacterSet
{
    /// <inheritdoc/>
    public int CharacterWidth => 8;

    /// <inheritdoc/>
    public int CharacterHeight => machine.Vic.TallCharacters ? 16 : 8;

    // The lower-case set and its reversed copy, $8800 and $8C00 to the processor.
    private bool Lowercase => machine.Vic.CharacterAddress is 0x0800 or 0x0C00;

    /// <inheritdoc/>
    public bool IsLit(byte code, int line, int pixel, bool flashed)
    {
        int height = CharacterHeight;
        int address = (machine.Vic.CharacterAddress + (code * height) + (line % height)) & 0x3FFF;
        byte dots = ((IVicMemory)machine.Bus).FetchVideo(address);
        return (dots & (0x80 >> pixel)) != 0;
    }

    /// <inheritdoc/>
    public char Character(byte code)
    {
        int value = code & 0x7F;
        if (Lowercase)
        {
            return value switch
            {
                0 => '@',
                >= 1 and <= 26 => (char)('a' + value - 1),
                >= 0x1B and < 0x20 => "[\\]^_"[value - 0x1B],
                < 0x40 => (char)value,
                >= 0x41 and <= 0x5A => (char)('A' + value - 0x41),
                _ => '\0'
            };
        }

        return value switch
        {
            < 0x20 => (char)(value + 0x40),
            < 0x40 => (char)value,
            _ => '\0'
        };
    }
}
