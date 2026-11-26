// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Pascal.Source;

/// <summary>
///  A WITH statement's body as the scan passes through it, whose bare names may be a record's fields.
/// </summary>
internal sealed class PascalWithBody
{
    /// <summary>
    ///  Creates a body.
    /// </summary>
    /// <param name="depth">The BEGIN and CASE depth it ends at.</param>
    /// <param name="block">Whether it is a BEGIN block, which ends at its END.</param>
    internal PascalWithBody(int depth, bool block)
    {
        Depth = depth;
        Block = block;
    }

    /// <summary>
    ///  Gets the BEGIN and CASE depth it ends at.
    /// </summary>
    public int Depth { get; }

    /// <summary>
    ///  Gets whether it is a BEGIN block, which ends at its END rather than at the end of a statement.
    /// </summary>
    public bool Block { get; }

    /// <summary>
    ///  Gets or sets the IFs in it still open to an ELSE, which then stays in the body.
    /// </summary>
    public int Ifs { get; set; }

    /// <summary>
    ///  Gets or sets whether the ELSE being read is one of its own IFs', so that it goes on.
    /// </summary>
    public bool Kept { get; set; }
}
