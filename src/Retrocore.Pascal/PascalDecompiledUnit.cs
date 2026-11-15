// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Pascal;

/// <summary>
///  A unit of a decompiled program's own, which the Linker linked into it: its source, to compile on its own, as the
///  program's <c>USES (*$U NAME.CODE*) NAME</c> names it.
/// </summary>
/// <param name="Name">Its name, its segment's, up to eight letters.</param>
/// <param name="Segment">Its segment number, which the program's USES gives it.</param>
/// <param name="Source">Its source: <c>UNIT</c>, its interface and its implementation.</param>
public sealed record PascalDecompiledUnit(string Name, int Segment, string Source)
{
    /// <summary>
    ///  Gets whether it is an intrinsic unit no library at hand declares, declared from the program's calls: it is
    ///  compiled for its interface, which the program's USES reads, and is not linked, as the system has its code.
    /// </summary>
    public bool Intrinsic { get; init; }
}
