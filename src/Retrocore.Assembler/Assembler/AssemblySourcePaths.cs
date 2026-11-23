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
    ///  Resolves a requested path against the including document's folder.
    /// </summary>
    /// <param name="fromPath">The including document, or empty for a search-path candidate.</param>
    /// <param name="request">The include request.</param>
    /// <returns>The absolute source identity.</returns>
    /// <exception cref="ArgumentException">The request depends on current-directory state.</exception>
    internal static string Resolve(string fromPath, string request) =>
        Path.GetFullPath(Combine(fromPath.Length == 0 ? "" : Path.GetDirectoryName(Path.GetFullPath(fromPath)) ?? "", request));

    /// <summary>
    ///  Combines a directory and request: a fully qualified request is used as it is and a relative one is joined
    ///  to the directory.
    /// </summary>
    /// <remarks>
    ///  <para>
    ///   A Windows request rooted without being fully qualified, such as <c>\lib\X.asm</c> (the current drive's
    ///   root) or <c>C:X.asm</c> (drive C's own current directory), resolves against process-wide current-directory
    ///   state, so it is rejected rather than read from wherever that state points.
    ///  </para>
    /// </remarks>
    /// <param name="directory">The source or search directory.</param>
    /// <param name="request">The requested path.</param>
    /// <returns>The combined path.</returns>
    /// <exception cref="ArgumentException">The request depends on current-directory state.</exception>
    internal static string Combine(string directory, string request)
    {
        return DependsOnCurrentDirectory(request)
            ? throw new ArgumentException($"An include path must be relative or fully qualified, not '{request}'.")
            : Path.IsPathFullyQualified(request) ? request : Path.Join(directory, request);
    }

    /// <summary>
    ///  Checks whether a request is rooted without being fully qualified, so that it resolves against
    ///  current-directory state rather than the directory it would be joined to.
    /// </summary>
    /// <param name="request">The requested path.</param>
    /// <returns>
    ///  Whether, on Windows, it is not fully qualified and starts with a directory separator or with a drive letter
    ///  and colon. Always false elsewhere, where only a fully qualified path is rooted.
    /// </returns>
    internal static bool DependsOnCurrentDirectory(string request)
    {
        bool windows = Path.DirectorySeparatorChar == '\\';
        if (!windows || request.Length == 0 || Path.IsPathFullyQualified(request)) { return false; }
        bool separator = request[0] == Path.DirectorySeparatorChar || request[0] == Path.AltDirectorySeparatorChar;
        bool drive = request.Length > 1 && request[1] == Path.VolumeSeparatorChar && char.IsAsciiLetter(request[0]);
        return separator || drive;
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
