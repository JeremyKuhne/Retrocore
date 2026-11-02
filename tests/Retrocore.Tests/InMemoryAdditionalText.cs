// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using Microsoft.CodeAnalysis;
using Microsoft.CodeAnalysis.Text;

namespace Retrocore.Tests;

/// <summary>
///  Supplies generator inputs without reading or modifying workspace files.
/// </summary>
internal sealed class InMemoryAdditionalText : AdditionalText
{
    private readonly SourceText? _text;

    /// <summary>
    ///  Creates an additional text input, optionally simulating an unreadable file.
    /// </summary>
    /// <param name="text">The file contents, or null to simulate a read failure.</param>
    /// <param name="path">The additional file path.</param>
    internal InMemoryAdditionalText(string? text, string path = "OpcodeTables.txt")
    {
        _text = text is null ? null : SourceText.From(text);
        Path = path;
    }

    /// <summary>
    ///  Gets the input's file path.
    /// </summary>
    public override string Path { get; }

    /// <summary>
    ///  Gets the simulated file contents.
    /// </summary>
    /// <param name="cancellationToken">The cancellation token.</param>
    /// <returns>The source text, or null for an unreadable file.</returns>
    public override SourceText? GetText(CancellationToken cancellationToken = default) => _text;
}
