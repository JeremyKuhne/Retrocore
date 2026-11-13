// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Pascal;

/// <summary>
///  A line of an Apple Pascal compiler listing.
/// </summary>
/// <param name="Line">Its source line's number, from 1.</param>
/// <param name="Segment">The segment number its code is in.</param>
/// <param name="Procedure">The procedure number its code is in.</param>
/// <param name="Depth">
///  How deeply its statement nests, from 0 for a block's <c>BEGIN</c>; null for a declaration.
/// </param>
/// <param name="Offset">
///  For a statement, where its code starts, in bytes from the procedure's entry; for a declaration, the word its
///  variables start at.
/// </param>
/// <param name="Text">The source line.</param>
public sealed record PascalListingLine(int Line, int Segment, int Procedure, int? Depth, int Offset, string Text)
{
    /// <summary>
    ///  Gets whether it declares rather than runs.
    /// </summary>
    public bool IsDeclaration => Depth is null;
}
