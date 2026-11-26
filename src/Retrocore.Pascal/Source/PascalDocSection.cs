// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Pascal.Source;

/// <summary>
///  One section of a documentation comment: its name and its lines.
/// </summary>
/// <param name="Name">The section's name, as <see cref="PascalDocComment.Sections"/> lists it.</param>
/// <param name="Line">The line it starts on, from 0, in its file.</param>
/// <param name="Text">Its text, its lines joined by spaces.</param>
public sealed record PascalDocSection(string Name, int Line, string Text)
{
    /// <summary>
    ///  Gets its items: a list section's comma-separated items, or each <c>Name = meaning</c> of <c>Parameters:</c>.
    /// </summary>
    public IReadOnlyList<string> Items => Name switch
    {
        "Also" or "See" or "Uses" => [.. PascalDocComment.SplitItems(Text)],
        "Parameters" => [.. PascalDocComment.SplitEntries(Text)],
        _ => [Text]
    };
}
