// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using System.Text.RegularExpressions;

namespace Retrocore.Debug.Language;

/// <summary>
///  Finds which assembly sources include which, from their text, so an included file is analyzed as part of
///  the source that includes it rather than alone.
/// </summary>
internal static partial class SourceIncludes
{
    // Folders that can't be listed, such as Windows' "Application Data" junctions, are skipped rather than failing the
    // search; hidden and system files are kept.
    private static readonly EnumerationOptions s_searchOne = new() { IgnoreInaccessible = true, AttributesToSkip = 0 };
    private static readonly EnumerationOptions s_searchAll = new()
    {
        IgnoreInaccessible = true,
        AttributesToSkip = 0,
        RecurseSubdirectories = true
    };

    /// <summary>
    ///  Gets whether a file is an assembly source the language features analyze.
    /// </summary>
    /// <param name="path">The file.</param>
    /// <returns>Whether its extension is an assembly source's.</returns>
    internal static bool IsAssemblySource(string path) =>
        Path.GetExtension(path).ToLowerInvariant() is ".asm" or ".s" or ".mac" or ".inc";

    /// <summary>
    ///  Gets the files a source includes with <c>.include</c>, or composes as a MACRO-10 overlay's base.
    /// </summary>
    /// <param name="path">The source's full path.</param>
    /// <returns>The full paths of the files it names.</returns>
    internal static IEnumerable<string> IncludesOf(string path)
    {
        string directory = Path.GetDirectoryName(path) ?? "";
        string text;
        try
        {
            text = File.ReadAllText(path);
        }
        catch (IOException)
        {
            yield break;
        }

        foreach (Match match in Include().Matches(text))
        {
            yield return Path.GetFullPath(Path.Join(directory, match.Groups["file"].Value));
        }

        // An overlay's first line names the base it edits.
        int end = text.IndexOf('\n', StringComparison.Ordinal);
        string first = end < 0 ? text : text[..end];
        Match overlay = Overlay().Match(first);
        if (overlay.Success && first.Contains("retrocore:", StringComparison.Ordinal))
        {
            yield return Path.GetFullPath(Path.Join(directory, overlay.Groups["file"].Value));
        }
    }

    /// <summary>
    ///  Gets the roots among a folder's sources: every assembly source that no other one includes.
    /// </summary>
    /// <param name="folder">The folder, searched with its subfolders.</param>
    /// <returns>The roots' full paths.</returns>
    internal static List<string> Roots(string folder)
    {
        List<string> files = [.. Directory.EnumerateFiles(folder, "*", s_searchAll)
            .Where(IsAssemblySource)
            .Select(Path.GetFullPath)];

        HashSet<string> included = new(StringComparer.OrdinalIgnoreCase);
        foreach (string file in files) { included.UnionWith(IncludesOf(file)); }
        return [.. files.Where(file => !included.Contains(file))];
    }

    /// <summary>
    ///  Gets the root to analyze a file through: the outermost source that includes it, found in its own folder
    ///  and the folders beside it, or the file itself when nothing includes it.
    /// </summary>
    /// <remarks>
    ///  <para>
    ///   When several sources include the file, the one whose name sorts last is used, so the later of two
    ///   versions (<c>Dos33.asm</c> over <c>Dos32.asm</c>, <c>Boot16.asm</c> over <c>Boot13.asm</c>) wins.
    ///  </para>
    /// </remarks>
    /// <param name="path">The file's full path.</param>
    /// <returns>The root's full path.</returns>
    internal static string RootOf(string path)
    {
        List<string> candidates = Neighbors(path);
        HashSet<string> seen = new(StringComparer.OrdinalIgnoreCase) { path };
        string current = path;
        while (candidates.FirstOrDefault(candidate =>
            !seen.Contains(candidate) && IncludesOf(candidate).Contains(current, StringComparer.OrdinalIgnoreCase)) is { } includer)
        {
            seen.Add(includer);
            current = includer;
        }

        return current;
    }

    // The sources in a file's folder and in the folders beside it, its own folder first, each by name descending.
    private static List<string> Neighbors(string path)
    {
        string? directory = Path.GetDirectoryName(path);
        if (directory is null || !Directory.Exists(directory)) { return []; }
        IEnumerable<string> folders = [directory];
        if (Path.GetDirectoryName(directory) is { } parent && Directory.Exists(parent))
        {
            folders = folders.Concat(Directory.EnumerateDirectories(parent, "*", s_searchOne)
                .Where(folder => !string.Equals(Path.GetFullPath(folder), Path.GetFullPath(directory), StringComparison.OrdinalIgnoreCase))
                .Order(StringComparer.OrdinalIgnoreCase));
        }

        return [.. folders.SelectMany(folder => Directory.EnumerateFiles(folder, "*", s_searchOne)
            .Where(IsAssemblySource)
            .Select(Path.GetFullPath)
            .OrderDescending(StringComparer.OrdinalIgnoreCase))];
    }

    [GeneratedRegex(@"^[ \t]*(?:[A-Za-z_@][\w@]*:?[ \t]+)?\.include[ \t]+""(?<file>[^""]+)""", RegexOptions.Multiline | RegexOptions.IgnoreCase)]
    private static partial Regex Include();

    [GeneratedRegex(@"\boverlay=(?<file>\S+)", RegexOptions.IgnoreCase)]
    private static partial Regex Overlay();
}
