// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Isa;

/// <summary>
///  One instruction's, or form's, effects from an <c>effects</c> line, and whether an encoding took them.
/// </summary>
/// <param name="Effects">The effects.</param>
/// <param name="Line">The line that gave them.</param>
internal sealed record EffectsLine(InstructionEffects Effects, int Line)
{
    /// <summary>
    ///  Gets or sets whether some encoding of some set took these effects, so a line no encoding takes, such as
    ///  a misspelled instruction, can be reported.
    /// </summary>
    internal bool Used { get; set; }
}
