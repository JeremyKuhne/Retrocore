// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Debug.Project;

/// <summary>
///  Expands a project's file patterns: <c>*</c> and <c>?</c> within a folder or file name, and <c>**</c> for any
///  number of folders, with <c>/</c> or <c>\</c> between them.
/// </summary>
internal static class ProjectGlob
{
    /// <summary>
    ///  Gets how file names compare: ignoring case on Windows and macOS, whose file systems usually do, and exactly
    ///  elsewhere.
    /// </summary>
    internal static StringComparer FileNames { get; } =
        OperatingSystem.IsWindows() || OperatingSystem.IsMacOS() ? StringComparer.OrdinalIgnoreCase : StringComparer.Ordinal;

    /// <summary>
    ///  Tests whether a path is a pattern rather than a single file.
    /// </summary>
    /// <param name="path">The path.</param>
    /// <returns>Whether it has a wildcard.</returns>
    internal static bool IsPattern(string path) => path.AsSpan().IndexOfAny('*', '?') >= 0;

    /// <summary>
    ///  Gets the files a pattern matches, in ordinal order of their paths.
    /// </summary>
    /// <param name="directory">The folder a relative pattern starts in.</param>
    /// <param name="pattern">The pattern.</param>
    /// <returns>The full paths of the files it matches.</returns>
    internal static List<string> Expand(string directory, string pattern)
    {
        string full = Path.GetFullPath(pattern, directory);
        string volume = Path.GetPathRoot(full) ?? "";
        string[] parts = full[volume.Length..].Split(['/', '\\'], StringSplitOptions.RemoveEmptyEntries);

        // The folders before the first wildcard are fixed, after the root: a drive, a share or '/'.
        int fixedCount = 0;
        while (fixedCount < parts.Length && !IsPattern(parts[fixedCount])) { fixedCount++; }
        string root = Path.Join(volume, string.Join(Path.DirectorySeparatorChar, parts[..fixedCount]));

        List<string> files = [];
        if (Directory.Exists(root)) { Match(root, parts.AsSpan(fixedCount), files); }
        files.Sort(StringComparer.Ordinal);
        return [.. files.Distinct(FileNames)];
    }

    private static void Match(string folder, ReadOnlySpan<string> parts, List<string> files)
    {
        string part = parts[0];
        if (part == "**")
        {
            // Any number of folders, none included.
            if (parts.Length == 1)
            {
                files.AddRange(Directory.EnumerateFiles(folder, "*", SearchOption.AllDirectories));
                return;
            }

            Match(folder, parts[1..], files);
            foreach (string child in Directory.EnumerateDirectories(folder))
            {
                Match(child, parts, files);
            }

            return;
        }

        if (parts.Length == 1)
        {
            files.AddRange(Directory.EnumerateFiles(folder).Where(file => Matches(part, Path.GetFileName(file))));
            return;
        }

        foreach (string child in Directory.EnumerateDirectories(folder).Where(child => Matches(part, Path.GetFileName(child))))
        {
            Match(child, parts[1..], files);
        }
    }

    /// <summary>
    ///  Tests a name against one part of a pattern, comparing as <see cref="FileNames"/> does.
    /// </summary>
    /// <param name="pattern">The part, with <c>*</c> for any characters and <c>?</c> for one.</param>
    /// <param name="name">The folder or file name.</param>
    /// <returns>Whether it matches.</returns>
    internal static bool Matches(ReadOnlySpan<char> pattern, ReadOnlySpan<char> name)
    {
        if (pattern.IsEmpty) { return name.IsEmpty; }
        if (pattern[0] == '*')
        {
            for (int skip = 0; skip <= name.Length; skip++)
            {
                if (Matches(pattern[1..], name[skip..])) { return true; }
            }

            return false;
        }

        bool ignoreCase = ReferenceEquals(FileNames, StringComparer.OrdinalIgnoreCase);
        return !name.IsEmpty
            && (pattern[0] == '?'
                || pattern[0] == name[0]
                || (ignoreCase && char.ToUpperInvariant(pattern[0]) == char.ToUpperInvariant(name[0])))
            && Matches(pattern[1..], name[1..]);
    }
}