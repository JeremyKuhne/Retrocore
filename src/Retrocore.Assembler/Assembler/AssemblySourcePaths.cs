// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Assembler;

/// <summary>
///  Host path operations shared by native resolvers and the netstandard generator.
/// </summary>
internal static class AssemblySourcePaths
{
    /// <summary>
    ///  Resolves a requested path while preserving explicit rooted-path semantics.
    /// </summary>
    /// <param name="fromPath">The including document, or empty for a search-path candidate.</param>
    /// <param name="request">The include request.</param>
    /// <returns>The absolute source identity.</returns>
    internal static string Resolve(string fromPath, string request) =>
        Path.GetFullPath(Combine(fromPath.Length == 0 ? "" : Path.GetDirectoryName(Path.GetFullPath(fromPath)) ?? "", request));

    /// <summary>
    ///  Combines a directory and request, including an explicit absolute override.
    /// </summary>
    /// <param name="directory">The source or search directory.</param>
    /// <param name="request">The requested path.</param>
    /// <returns>The combined path.</returns>
    internal static string Combine(string directory, string request)
    {
#pragma warning disable TOUKI0032 // Combine preserves rooted requests and is available on netstandard2.0.
        return Path.Combine(directory, request);
#pragma warning restore TOUKI0032
    }

    /// <summary>
    ///  Checks that a normalized SDK candidate stays within its configured search directory.
    /// </summary>
    /// <param name="directory">The SDK directory.</param>
    /// <param name="candidate">The source candidate.</param>
    /// <returns>Whether the candidate is contained by the SDK directory.</returns>
    internal static bool IsWithin(string directory, string candidate)
    {
        string prefix = Path.GetFullPath(directory).TrimEnd('\\', '/') + Path.DirectorySeparatorChar;
        StringComparison comparison = Path.DirectorySeparatorChar == '\\' ? StringComparison.OrdinalIgnoreCase : StringComparison.Ordinal;
        return Path.GetFullPath(candidate).StartsWith(prefix, comparison);
    }
}
