// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

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
    /// <returns>The parsed files.</returns>
    internal static IEnumerable<DocumentationFile> Parse(IEnumerable<string> paths)
    {
        foreach (string path in paths.Distinct(StringComparer.OrdinalIgnoreCase))
        {
            if (File.Exists(path)) { yield return DocumentationParser.Parse(File.ReadAllText(path), path); }
        }
    }
}
