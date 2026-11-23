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
    ///  Resolves a requested path: a fully qualified request as it is, a relative one against the including
    ///  document's folder.
    /// </summary>
    /// <param name="fromPath">The including document, or empty for a search-path candidate.</param>
    /// <param name="request">The include request.</param>
    /// <returns>The absolute source identity.</returns>
    /// <exception cref="ArgumentException">
    ///  The request depends on current-directory state, or holds a character no path can.
    /// </exception>
    /// <exception cref="IOException">The full path is too long.</exception>
    internal static string Resolve(string fromPath, string request) =>
        Path.GetFullPath(Combine(fromPath.Length == 0 ? "" : Path.GetDirectoryName(Path.GetFullPath(fromPath)) ?? "", request));

    /// <summary>
    ///  Combines a directory and request: a fully qualified request is used as it is and a relative one is joined
    ///  to the directory.
    /// </summary>
    /// <remarks>
    ///  <para>
    ///   A Windows path rooted without being fully qualified, such as <c>\lib\X.asm</c> (the current drive's root)
    ///   or <c>C:X.asm</c> (drive C's own current directory), resolves against process-wide current-directory
    ///   state, so such a request or search directory is rejected rather than read from wherever that state points.
    ///  </para>
    /// </remarks>
    /// <param name="directory">The source or search directory, or empty.</param>
    /// <param name="request">The requested path.</param>
    /// <returns>The combined path.</returns>
    /// <exception cref="ArgumentException">The directory or request depends on current-directory state.</exception>
    internal static string Combine(string directory, string request)
    {
        RejectCurrentDirectory(directory, "A search path");
        RejectCurrentDirectory(request, "An include path");
        return Path.IsPathFullyQualified(request) ? request : Path.Join(directory, request);
    }

    /// <summary>
    ///  Checks whether a path is rooted without being fully qualified on the platform the assembler runs on, so
    ///  that it resolves against current-directory state rather than a directory it would be joined to.
    /// </summary>
    /// <param name="path">The path.</param>
    /// <returns>Whether the path depends on current-directory state.</returns>
    internal static bool DependsOnCurrentDirectory(string path) =>
        DependsOnCurrentDirectory(path, windows: Path.DirectorySeparatorChar == '\\');

    /// <summary>
    ///  Checks whether a path is rooted without being fully qualified under Windows or Unix rules.
    /// </summary>
    /// <param name="path">The path.</param>
    /// <param name="windows">Whether to apply Windows rules rather than Unix ones.</param>
    /// <returns>
    ///  Under Windows rules, whether it is a lone separator, a separator followed by anything but a second
    ///  separator or <c>?</c> (a UNC or device path), or a drive letter and colon not followed by a separator.
    ///  Under Unix rules, always false: a path is rooted only when it starts with <c>/</c>, which is fully qualified.
    /// </returns>
    internal static bool DependsOnCurrentDirectory(string path, bool windows)
    {
        if (!windows || path.Length == 0) { return false; }
        bool second = path.Length > 1;
        if (IsWindowsSeparator(path[0])) { return !second || !(path[1] == '?' || IsWindowsSeparator(path[1])); }
        bool drive = second && path[1] == ':' && char.IsAsciiLetter(path[0]);
        return drive && (path.Length == 2 || !IsWindowsSeparator(path[2]));
    }

    private static bool IsWindowsSeparator(char value) => value is '\\' or '/';

    private static void RejectCurrentDirectory(string path, string what)
    {
        if (DependsOnCurrentDirectory(path))
        {
            throw new ArgumentException($"{what} must be relative or fully qualified, not '{path}'.");
        }
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
