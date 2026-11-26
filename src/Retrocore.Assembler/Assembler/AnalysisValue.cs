// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Assembler;

/// <summary>
///  What the routine analysis knows of a register, flag or byte of memory: where its value came from, and the value
///  itself when it is a known constant.
/// </summary>
/// <param name="Origin">
///  Where the value came from: a slot's entry value, a change at an instruction, or an unknown value, as
///  <see cref="AnalysisRoutineEngine"/> encodes them.
/// </param>
/// <param name="Constant">The value, when it is known, or -1.</param>
internal readonly record struct AnalysisValue(int Origin, int Constant)
{
    /// <summary>
    ///  Gets a value from an origin, with no constant known.
    /// </summary>
    /// <param name="origin">The origin.</param>
    /// <returns>The value.</returns>
    internal static AnalysisValue Of(int origin) => new(origin, -1);

    /// <summary>
    ///  Gets whether the value is a known constant.
    /// </summary>
    internal bool IsConstant => Constant >= 0;
}
