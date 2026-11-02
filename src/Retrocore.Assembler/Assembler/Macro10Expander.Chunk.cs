// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Assembler;

internal sealed partial class Macro10Expander
{
    /// <summary>
    ///  Text to expand: a file, a conditional or repeat body, or a macro expansion.
    /// </summary>
    /// <param name="Text">The text.</param>
    /// <param name="Location">The source location of each of the text's lines, by line index.</param>
    private readonly record struct Chunk(string Text, Func<int, AssemblyLocation> Location);
}
