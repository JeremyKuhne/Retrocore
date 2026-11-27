// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Assembler;

/// <summary>
///  What the routine analysis knows of a register, flag or byte of memory: where its value came from, and those of
///  its bits that are known, all of them for a constant.
/// </summary>
/// <param name="Origin">
///  Where the value came from: a slot's entry value, a change at an instruction, or an unknown value, as
///  <see cref="AnalysisRoutineEngine"/> encodes them.
/// </param>
/// <param name="Known">The bits whose values are known, within the slot's width.</param>
/// <param name="Bits">The values of the known bits; the others are 0.</param>
internal readonly record struct AnalysisValue(int Origin, int Known, int Bits)
{
    /// <summary>
    ///  Gets a value from an origin, with no bits known.
    /// </summary>
    /// <param name="origin">The origin.</param>
    /// <returns>The value.</returns>
    internal static AnalysisValue Of(int origin) => new(origin, 0, 0);

    /// <summary>
    ///  Gets whether every bit of a width is known.
    /// </summary>
    /// <param name="width">The slot's bits, as 0xFF for an 8-bit register or 1 for a flag.</param>
    /// <returns>Whether the value is a constant.</returns>
    internal bool IsConstant(int width) => (Known & width) == width;

    /// <summary>
    ///  Gets the value with no bits known, keeping where it came from.
    /// </summary>
    internal AnalysisValue WithoutBits => this with { Known = 0, Bits = 0 };

    /// <summary>
    ///  Gets the value with some bits known.
    /// </summary>
    /// <param name="known">The bits known.</param>
    /// <param name="bits">Their values.</param>
    /// <returns>The value.</returns>
    internal AnalysisValue WithBits(int known, int bits) => this with { Known = known, Bits = bits & known };

    /// <summary>
    ///  Joins two paths' values: a bit is known where both know it with the same value.
    /// </summary>
    /// <param name="other">The other path's value.</param>
    /// <param name="origin">The joined origin.</param>
    /// <returns>The joined value.</returns>
    internal AnalysisValue Join(AnalysisValue other, int origin)
    {
        int known = Known & other.Known & ~(Bits ^ other.Bits);
        return new(origin, known, Bits & known);
    }
}
