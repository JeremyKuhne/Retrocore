// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Pascal;

/// <summary>
///  An assembled procedure to write as Assembler source: its number, and how its host declares it.
/// </summary>
/// <param name="Number">Its procedure number in its segment.</param>
/// <param name="Name">
///  The name its host declares it EXTERNAL by, which the Linker matches in its first eight letters.
/// </param>
/// <param name="IsFunction">Whether it is a function, <c>.FUNC</c>, or a procedure, <c>.PROC</c>.</param>
/// <param name="ParameterWords">The words its parameters take, not counting a function's result.</param>
public sealed record PascalAssembledProcedure(string Name, int Number, bool IsFunction, int ParameterWords)
{
    /// <summary>
    ///  Gets a comment to write above it.
    /// </summary>
    public string? Comment { get; init; }

    /// <summary>
    ///  Gets the names to give places in it, by offset from its entry.
    /// </summary>
    public IReadOnlyDictionary<int, string> Names { get; init; } = new Dictionary<int, string>();

    /// <summary>
    ///  Gets comments to write above places in it, by offset from its entry.
    /// </summary>
    public IReadOnlyDictionary<int, string> Comments { get; init; } = new Dictionary<int, string>();
}
