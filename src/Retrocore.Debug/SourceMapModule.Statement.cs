// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Debug;

internal sealed partial class SourceMapModule
{
    /// <summary>
    ///  One emitted statement.
    /// </summary>
    /// <param name="Address">The CPU address of its first byte.</param>
    /// <param name="Bytes">The bytes it assembled to, which memory must hold for its source to apply.</param>
    /// <param name="Chain">Its source levels, innermost first.</param>
    /// <param name="EntryDepth">How many innermost levels' invocations begin with it.</param>
    private sealed record Statement(ushort Address, byte[] Bytes, SourceLine[] Chain, int EntryDepth);
}
