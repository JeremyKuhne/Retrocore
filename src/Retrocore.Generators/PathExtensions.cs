// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace System.IO;

/// <summary>
///  Supplies the path APIs missing from the generator's .NET Standard reference surface, with the same results as
///  the .NET ones on the platform the generator runs on.
/// </summary>
internal static class PathExtensions
{
    extension(Path)
    {
        /// <summary>
        ///  Joins two paths with one separator, never letting a rooted second path replace the first.
        /// </summary>
        /// <param name="path1">The first path, which may be empty.</param>
        /// <param name="path2">The second path, which may be empty.</param>
        /// <returns>The joined path.</returns>
        internal static string Join(string? path1, string? path2) => Join(path1, path2, Windows);

        /// <summary>
        ///  Checks whether a path's location is fixed, independent of any current directory.
        /// </summary>
        /// <param name="path">The path.</param>
        /// <returns>Whether the path is fully qualified on the platform the generator runs on.</returns>
        internal static bool IsPathFullyQualified(string path) => IsPathFullyQualified(path, Windows);
    }

    private static bool Windows => Path.DirectorySeparatorChar == '\\';

    /// <summary>
    ///  Joins two paths with one separator under Windows or Unix rules, as .NET's <c>Path.Join</c> does on each.
    /// </summary>
    /// <param name="path1">The first path, which may be empty.</param>
    /// <param name="path2">The second path, which may be empty.</param>
    /// <param name="windows">Whether to apply Windows rules rather than Unix ones.</param>
    /// <returns>The joined path.</returns>
    internal static string Join(string? path1, string? path2, bool windows)
    {
        if (path1 is null or "") { return path2 ?? ""; }
        if (path2 is null or "") { return path1; }
        bool separated = IsSeparator(path1[^1], windows) || IsSeparator(path2[0], windows);
        return separated ? path1 + path2 : path1 + (windows ? '\\' : '/') + path2;
    }

    /// <summary>
    ///  Checks whether a path is fully qualified under Windows or Unix rules, as .NET's
    ///  <c>Path.IsPathFullyQualified</c> does on each.
    /// </summary>
    /// <param name="path">The path.</param>
    /// <param name="windows">Whether to apply Windows rules rather than Unix ones.</param>
    /// <returns>
    ///  Under Windows rules, whether it starts with a drive letter, colon and separator, or with two separators (a
    ///  UNC or device path) or a separator and <c>?</c>. Under Unix rules, whether it starts with <c>/</c>.
    /// </returns>
    internal static bool IsPathFullyQualified(string path, bool windows)
    {
        ArgumentNullException.ThrowIfNull(path);
        if (!windows) { return path.Length > 0 && path[0] == '/'; }
        if (path.Length < 2) { return false; }
        bool drive = path.Length > 2 && path[1] == ':' && IsSeparator(path[2], windows) && char.IsAsciiLetter(path[0]);
        return IsSeparator(path[0], windows) ? path[1] == '?' || IsSeparator(path[1], windows) : drive;
    }

    private static bool IsSeparator(char value, bool windows) => value == '/' || (windows && value == '\\');
}
