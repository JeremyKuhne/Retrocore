// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using System.Text.Json.Nodes;

namespace Retrocore.Debug.Language;

/// <summary>
///  A stretch of a document, from a start position up to an end.
/// </summary>
/// <param name="Start">Where it starts.</param>
/// <param name="End">Where it ends, just past its last character.</param>
internal sealed record LspRange(Position Start, Position End)
{
    /// <summary>
    ///  Makes a range from its lines and columns.
    /// </summary>
    /// <param name="startLine">The start's line.</param>
    /// <param name="startCharacter">The start's column.</param>
    /// <param name="endLine">The end's line.</param>
    /// <param name="endCharacter">The end's column.</param>
    public LspRange(int startLine, int startCharacter, int endLine, int endCharacter)
        : this(new Position(startLine, startCharacter), new Position(endLine, endCharacter))
    {
    }

    /// <summary>
    ///  Writes the range.
    /// </summary>
    /// <returns>Its JSON.</returns>
    public JsonObject ToJson() => new() { ["start"] = Start.ToJson(), ["end"] = End.ToJson() };
}
