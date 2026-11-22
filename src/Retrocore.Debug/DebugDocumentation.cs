// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using Retrocore.Assembler;
using Retrocore.Documentation;

namespace Retrocore.Debug;

/// <summary>
///  Reads the documentation comments of a debug module's sources.
/// </summary>
internal static class DebugDocumentation
{
    /// <summary>
    ///  Parses each existing source file once.
    /// </summary>
    /// <param name="paths">The source paths, possibly repeated.</param>
    /// <param name="result">The assembly the sources made, so links follow its <c>.using</c> lines, or null.</param>
    /// <returns>The parsed files.</returns>
    internal static IEnumerable<DocumentationFile> Parse(IEnumerable<string> paths, AssemblyResult? result = null)
    {
        foreach (string path in paths.Distinct(StringComparer.OrdinalIgnoreCase))
        {
            if (!File.Exists(path)) { continue; }
            DocumentationAssembled? assembled = result is null ? null : DocumentationAssembled.From(result, path);
            yield return DocumentationParser.Parse(File.ReadAllText(path), path, assembled);
        }
    }
}
