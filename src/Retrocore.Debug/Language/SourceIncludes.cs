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
        string text;
        try
        {
            text = File.ReadAllText(path);
        }
        catch (Exception exception) when (exception is IOException or UnauthorizedAccessException)
        {
            // Gone (FileNotFoundException), unreadable, or replaced by a folder after it was listed, which Linux
            // reports as an UnauthorizedAccessException: it includes nothing.
            yield break;
        }

        foreach (Match match in Include().Matches(text))
        {
            if (Resolve(path, match.Groups["file"].Value) is { } file) { yield return file; }
        }

        // An overlay's first line names the base it edits.
        int end = text.IndexOf('\n', StringComparison.Ordinal);
        string first = end < 0 ? text : text[..end];
        Match overlay = Overlay().Match(first);
        if (overlay.Success
            && first.Contains("retrocore:", StringComparison.Ordinal)
            && Resolve(path, overlay.Groups["file"].Value) is { } overlaid)
        {
            yield return overlaid;
        }
    }

    // The file a source names, or where the shared BASIC sources keep it when that is elsewhere: in the repository
    // they are in Retrocore.Basic, and in the SDK beside the machines' sources. Null for a name no path can hold.
    private static string? Resolve(string fromPath, string request)
    {
        if (Named(fromPath, request) is not { } direct) { return null; }
        if (File.Exists(direct)) { return direct; }
        foreach (string fallback in OverlayBaseResolver.Fallbacks(fromPath, request, OverlayBaseResolver.SdkFallback))
        {
            if (File.Exists(fallback)) { return fallback; }
        }

        return direct;
    }

    /// <summary>
    ///  Gets the lines of a source that include another file with <c>.include</c>, and the files they name.
    /// </summary>
    /// <param name="path">The source's full path, which a relative name is resolved against.</param>
    /// <param name="lines">The source's lines.</param>
    /// <returns>Each including line's zero-based index and the full path of the file it names.</returns>
    internal static IEnumerable<(int Line, string File)> IncludeLines(string path, IReadOnlyList<string> lines)
    {
        for (int line = 0; line < lines.Count; line++)
        {
            if (Include().Match(lines[line]) is not { Success: true } match) { continue; }
            if (Resolve(path, match.Groups["file"].Value) is { } file) { yield return (line, file); }
        }
    }

    // The full path of a file a source names, as the workspace's resolver finds it (LanguagePaths.Resolve): an
    // absolute name as it is, a relative one from the source's folder. Null for a name no path can hold.
    private static string? Named(string path, string name) =>
        name.AsSpan().IndexOfAny(Path.GetInvalidPathChars()) >= 0 ? null : LanguagePaths.Resolve(path, name);

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

        HashSet<string> included = [with(StringComparer.OrdinalIgnoreCase)];
        foreach (string file in files) { included.UnionWith(IncludesOf(file)); }
        return [.. files.Where(file => !included.Contains(file))];
    }

    /// <summary>
    ///  Gets the root to analyze a file through: the outermost source that includes it, found in its own folder
    ///  and the folders beside it, or the file itself when nothing includes it. The repository's shared BASIC
    ///  sources also search the other projects' ROM sources.
    /// </summary>
    /// <remarks>
    ///  <para>
    ///   The file's own folder is searched first, then neighboring folders; candidates within a folder are
    ///   searched by descending name, so the later of two versions (<c>Dos33.asm</c> over <c>Dos32.asm</c>,
    ///   <c>Boot16.asm</c> over <c>Boot13.asm</c>) wins. Shared BASIC also searches the other ROM projects.
    ///  </para>
    /// </remarks>
    /// <param name="path">The file's full path.</param>
    /// <returns>The root's full path.</returns>
    internal static string RootOf(string path) => RootOf(path, NeighborFolders(path));

    /// <summary>
    ///  Gets the root to analyze a file through, searching the given folders' sources.
    /// </summary>
    /// <param name="path">The file's full path.</param>
    /// <param name="folders">The folders to search, its own first; one that no longer exists is skipped.</param>
    /// <returns>The root's full path.</returns>
    internal static string RootOf(string path, IEnumerable<string> folders)
    {
        List<string> candidates = [.. folders.SelectMany(SourcesIn)];
        HashSet<string> seen = [with(StringComparer.OrdinalIgnoreCase), path];
        string current = path;
        while (candidates.FirstOrDefault(candidate =>
            !seen.Contains(candidate) && IncludesOf(candidate).Contains(current, StringComparer.OrdinalIgnoreCase)) is { } includer)
        {
            seen.Add(includer);
            current = includer;
        }

        return current;
    }

    // A file's folder, the folders beside it and the folder above, its own first, the others by name and the folder
    // above last. A module's parts may be in a folder of their own, included from the one above.
    private static List<string> NeighborFolders(string path)
    {
        string? directory = Path.GetDirectoryName(path);
        if (directory is null || !Directory.Exists(directory)) { return []; }
        List<string> folders = [directory];
        if (Path.GetDirectoryName(directory) is not { } parent) { return folders; }
        try
        {
            folders.AddRange(Directory.EnumerateDirectories(parent, "*", s_searchOne)
                .Where(folder => !string.Equals(Path.GetFullPath(folder), Path.GetFullPath(directory), StringComparison.OrdinalIgnoreCase))
                .Order(StringComparer.OrdinalIgnoreCase));
        }
        catch (Exception exception) when (exception is IOException or UnauthorizedAccessException)
        {
            // The parent went away, or became unreadable, while it was listed; the file's own folder is still searched.
        }

        // SourcesIn finds nothing in the folder above if it went away too.
        folders.Add(parent);
        folders.AddRange(OtherRomFolders(directory));
        return folders;
    }

    // The repository's shared BASIC, Retrocore.Basic/Roms/Microsoft6502Basic, is included by the other projects'
    // ROM sources (AppleSoft, PET BASIC): their Roms folders and every folder within them, project by project.
    private static List<string> OtherRomFolders(string directory)
    {
        string? roms = Path.GetDirectoryName(directory);
        string? project = roms is null ? null : Path.GetDirectoryName(roms);
        string? sources = project is null ? null : Path.GetDirectoryName(project);
        if (!Path.GetFileName(directory).Equals("Microsoft6502Basic", StringComparison.OrdinalIgnoreCase)
            || !string.Equals(Path.GetFileName(roms), "Roms", StringComparison.OrdinalIgnoreCase)
            || !string.Equals(Path.GetFileName(project), "Retrocore.Basic", StringComparison.OrdinalIgnoreCase)
            || sources is null)
        {
            return [];
        }

        List<string> folders = [];
        try
        {
            foreach (string other in Directory.EnumerateDirectories(sources, "Retrocore.*", s_searchOne)
                .Order(StringComparer.OrdinalIgnoreCase))
            {
                if (string.Equals(other, project, StringComparison.OrdinalIgnoreCase)) { continue; }
                string otherRoms = Path.Join(other, "Roms");
                if (!Directory.Exists(otherRoms)) { continue; }
                folders.Add(otherRoms);
                folders.AddRange(Directory.EnumerateDirectories(otherRoms, "*", s_searchAll)
                    .Order(StringComparer.OrdinalIgnoreCase));
            }
        }
        catch (Exception exception) when (exception is IOException or UnauthorizedAccessException)
        {
            // A project went away, or became unreadable, while it was listed; the folders found so far are searched.
        }

        return folders;
    }

    /// <summary>
    ///  Gets the assembly sources directly in a folder, by name descending.
    /// </summary>
    /// <remarks>
    ///  <para>
    ///   A folder can be deleted after it is listed and before it is read, by a build or a cleanup beside the
    ///   sources; it then has no sources, rather than failing the analysis of the file being edited.
    ///  </para>
    /// </remarks>
    /// <param name="folder">The folder.</param>
    /// <returns>The sources' full paths; none when the folder no longer exists or can't be read.</returns>
    internal static List<string> SourcesIn(string folder)
    {
        try
        {
            return [.. Directory.EnumerateFiles(folder, "*", s_searchOne)
                .Where(IsAssemblySource)
                .Select(Path.GetFullPath)
                .OrderDescending(StringComparer.OrdinalIgnoreCase)];
        }
        catch (Exception exception) when (exception is IOException or UnauthorizedAccessException)
        {
            // Deleted or replaced by a file, an IOException (on Linux, DirectoryNotFoundException for both), or made
            // unreadable.
            return [];
        }
    }

    [GeneratedRegex(@"^[ \t]*(?:[A-Za-z_@][\w@]*:?[ \t]+)?\.include[ \t]+""(?<file>[^""]+)""", RegexOptions.Multiline | RegexOptions.IgnoreCase)]
    private static partial Regex Include();

    [GeneratedRegex(@"\boverlay=(?<file>\S+)", RegexOptions.IgnoreCase)]
    private static partial Regex Overlay();
}
