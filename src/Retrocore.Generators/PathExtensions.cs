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
        internal static string Join(string? path1, string? path2)
        {
            if (path1 is null or "") { return path2 ?? ""; }
            if (path2 is null or "") { return path1; }
            bool separated = IsDirectorySeparator(path1[^1]) || IsDirectorySeparator(path2[0]);
            return separated ? path1 + path2 : path1 + Path.DirectorySeparatorChar + path2;
        }

        /// <summary>
        ///  Checks whether a path's location is fixed, independent of any current directory.
        /// </summary>
        /// <param name="path">The path.</param>
        /// <returns>
        ///  On Windows, whether it starts with a drive letter, colon and separator, or with two separators (a UNC or
        ///  device path) or a separator and <c>?</c>. Elsewhere, whether it starts with a separator.
        /// </returns>
        internal static bool IsPathFullyQualified(string path)
        {
            ArgumentNullException.ThrowIfNull(path);
            if (Path.DirectorySeparatorChar != '\\') { return path.Length > 0 && path[0] == '/'; }
            if (path.Length < 2) { return false; }
            bool drive = path.Length > 2 && path[1] == Path.VolumeSeparatorChar && IsDirectorySeparator(path[2]) && char.IsAsciiLetter(path[0]);
            return IsDirectorySeparator(path[0]) ? path[1] == '?' || IsDirectorySeparator(path[1]) : drive;
        }
    }

    private static bool IsDirectorySeparator(char value) =>
        value == Path.DirectorySeparatorChar || value == Path.AltDirectorySeparatorChar;
}
