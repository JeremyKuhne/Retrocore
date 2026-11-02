// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Debug.Language;

/// <summary>
///  Path rules shared with the assembler's file resolver.
/// </summary>
internal static class LanguagePaths
{
    /// <summary>
    ///  Resolves an include request relative to the including file, as the assembler does.
    /// </summary>
    /// <param name="fromPath">The including file, or empty.</param>
    /// <param name="request">The requested path.</param>
    /// <returns>The full path.</returns>
    internal static string Resolve(string fromPath, string request)
    {
        if (Path.IsPathFullyQualified(request)) { return Path.GetFullPath(request); }
        string directory = fromPath.Length == 0 ? "" : Path.GetDirectoryName(Path.GetFullPath(fromPath)) ?? "";
        return Path.GetFullPath(Path.Join(directory, request));
    }
}
