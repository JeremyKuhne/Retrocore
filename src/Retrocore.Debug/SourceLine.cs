// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Debug;

/// <summary>
///  One level of the source behind an address: a physical line, or a macro body line with its invocation.
/// </summary>
/// <param name="Path">The full source path.</param>
/// <param name="Line">The one-based line.</param>
/// <param name="Name">For a macro body line, the invocation it expands, shown as its stack frame's name.</param>
internal readonly record struct SourceLine(string Path, int Line, string? Name = null)
{
    /// <summary>
    ///  Tests whether this is the given file and line.
    /// </summary>
    /// <param name="path">The full source path.</param>
    /// <param name="line">The one-based line.</param>
    /// <returns>Whether they match, comparing paths without case as Windows file names do.</returns>
    internal bool Is(string path, int line) => Line == line && string.Equals(Path, path, StringComparison.OrdinalIgnoreCase);
}
