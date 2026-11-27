// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Pascal.Source;

/// <summary>
///  Where the SDK's Pascal sources find the files they include from other folders.
/// </summary>
public static class PascalIncludeFolders
{
    /// <summary>
    ///  Gets the folders a source includes from besides its own: for a Compiler's, in
    ///  <c>Compiler/&lt;machine&gt;-&lt;version&gt;</c>, the system's globals in <c>System/&lt;machine&gt;-&lt;version&gt;</c>.
    /// </summary>
    /// <param name="file">The source's path.</param>
    /// <returns>The folders that exist, in the order to look in them.</returns>
    public static IReadOnlyList<string> For(string file)
    {
        string? folder = Path.GetDirectoryName(Path.GetFullPath(file));
        string? parent = folder is null ? null : Path.GetDirectoryName(folder);
        if (folder is null || parent is null || !string.Equals(Path.GetFileName(parent), "Compiler", StringComparison.OrdinalIgnoreCase))
        {
            return [];
        }

        // The folders' names in any case, as a file system that minds case may have them.
        string? system = Child(Path.GetDirectoryName(parent), "System") is { } systems ? Child(systems, Path.GetFileName(folder)) : null;
        return system is null ? [] : [system];
    }

    // A folder's child folder of a name, whatever its case.
    private static string? Child(string? folder, string name)
    {
        if (folder is null || !Directory.Exists(folder)) { return null; }
        string exact = Path.Join(folder, name);
        return Directory.Exists(exact)
            ? exact
            : Directory.EnumerateDirectories(folder).FirstOrDefault(
                child => string.Equals(Path.GetFileName(child), name, StringComparison.OrdinalIgnoreCase));
    }
}
