// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using Retrocore.Documentation;

namespace Retrocore.Debug.Language;

/// <summary>
///  Finds the bibliographies that a source's <c>Also:</c> entries may cite.
/// </summary>
internal static class SourceBibliography
{
    private static readonly Lazy<string?> s_sdkBibliography = new(() =>
    {
        string path = Path.Join(SdkModules.SdkDirectory, "Bibliography.md");
        return File.Exists(path) ? File.ReadAllText(path) : null;
    });

    /// <summary>
    ///  Gets the documents a source's <c>Also:</c> entries may cite: the SDK's bibliography, then each
    ///  <c>Bibliography.md</c> from the root down to the source's folder, nearer ones replacing a key.
    /// </summary>
    /// <param name="path">The source.</param>
    /// <returns>The documents.</returns>
    internal static DocumentationBibliography For(string path) => For(path, []);

    /// <summary>
    ///  Gets the documents an assembly's <c>Also:</c> entries may cite: the SDK's bibliography, then the root
    ///  file's folders from the top down, then those of each file it includes that the root's do not cover, so a
    ///  library's own <c>Bibliography.md</c> serves the library's entries.
    /// </summary>
    /// <param name="root">The root source.</param>
    /// <param name="members">The root and the files it includes.</param>
    /// <returns>The documents.</returns>
    internal static DocumentationBibliography For(string root, IEnumerable<string> members)
    {
        List<string> texts = [];
        if (s_sdkBibliography.Value is { } sdk) { texts.Add(sdk); }
        HashSet<string> read = [with(StringComparer.OrdinalIgnoreCase)];
        foreach (string path in members.Where(member => !string.Equals(member, root, StringComparison.OrdinalIgnoreCase)).Prepend(root))
        {
            List<string> files = [];
            for (string? directory = Path.GetDirectoryName(Path.GetFullPath(path));
                directory is not null;
                directory = Path.GetDirectoryName(directory))
            {
                string file = Path.Join(directory, "Bibliography.md");
                if (File.Exists(file)) { files.Add(file); }
            }

            files.Reverse();
            foreach (string file in files.Where(read.Add)) { texts.Add(File.ReadAllText(file)); }
        }

        return DocumentationBibliography.Parse(texts);
    }
}
