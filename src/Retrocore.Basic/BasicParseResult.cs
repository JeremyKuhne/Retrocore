// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Basic;

/// <summary>
///  The program a BASIC text holds, and what is wrong with it.
/// </summary>
/// <param name="Program">The program; null when there are errors.</param>
/// <param name="Dialect">The dialect the text was read as; null when none was given or named.</param>
/// <param name="Diagnostics">The problems found, in text order.</param>
/// <param name="SourceLines">For each of the program's lines, the zero-based line of the text it came from.</param>
public sealed record BasicParseResult(
    BasicProgram? Program,
    BasicDialect? Dialect,
    IReadOnlyList<BasicDiagnostic> Diagnostics,
    IReadOnlyList<int> SourceLines)
{
    /// <summary>
    ///  Gets whether the text has no errors.
    /// </summary>
    public bool Success => Program is not null;

    /// <summary>
    ///  Gets every line of the text that holds statements, in text order, with its number, even when there are
    ///  errors.
    /// </summary>
    public IReadOnlyList<BasicTextLine> Lines { get; init; } = [];

    /// <summary>
    ///  Gets the labels, by their uppercase names.
    /// </summary>
    public IReadOnlyDictionary<string, BasicLabel> Labels { get; init; } = new Dictionary<string, BasicLabel>();
}
