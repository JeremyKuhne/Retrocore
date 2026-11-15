// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Debug;

/// <summary>
///  The source behind an address.
/// </summary>
/// <param name="Chain">
///  The source levels, innermost first: macro body lines, then the line that invoked the outermost macro. Code
///  outside any macro has one level.
/// </param>
/// <param name="EntryDepth">
///  How many innermost levels begin at this address: the invocations whose first statement this is. A debugger
///  arriving here shows <c>Chain[EntryDepth]</c>, the line making the call, and steps in level by level.
/// </param>
/// <param name="Start">
///  The first address of the statement the address is in, when the module knows its statements; null otherwise.
/// </param>
/// <param name="Size">The statement's size in bytes, or 0 when <paramref name="Start"/> is null.</param>
/// <param name="Data">Whether the statement is data, such as <c>.byte</c>, rather than an instruction.</param>
internal sealed record DebugPosition(
    IReadOnlyList<SourceLine> Chain,
    int EntryDepth,
    ushort? Start = null,
    int Size = 0,
    bool Data = false);
