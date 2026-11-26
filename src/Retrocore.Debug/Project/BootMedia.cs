// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using System.Globalization;
using System.Security.Cryptography;
using System.Text.Json;
using System.Text.Json.Nodes;

namespace Retrocore.Debug.Project;

/// <summary>
///  The boot media and device dumps the SDK's environments use that are not SDK sources, as
///  <c>Sdk/1/boot-media.json</c> lists them, and where a launch finds them: by each file's hash, whatever its name.
/// </summary>
/// <remarks>
///  <para>
///   Each set is identified by the SHA-1 of each file, as its usual source publishes it (MAME's sets give SHA-1). The
///   files are looked for in a target's <c>bootImage</c> folder, the launch's ROM folder, the folder the set's
///   variable names (such as <c>RETROCORE_PET_ROMS</c>), and <c>RETROCORE_CACHE</c> (by default
///   <c>%USERPROFILE%\Retrocore</c>), each searched with its subfolders, a linked file read as its target is and a
///   linked folder left out, so no search loops. Only files of a set's sizes are read. A set is found when every
///   file is.
///  </para>
/// </remarks>
internal static class BootMedia
{
    /// <summary>
    ///  The catalog's file name, in the SDK's major version's folder.
    /// </summary>
    internal const string FileName = "boot-media.json";

    /// <summary>
    ///  Reads the catalog.
    /// </summary>
    /// <param name="sdk">The SDK's root.</param>
    /// <param name="version">The SDK's major version.</param>
    /// <returns>The sets.</returns>
    /// <exception cref="ProjectException">The catalog cannot be read, or is malformed.</exception>
    internal static IReadOnlyList<BootMediaSet> Catalog(string sdk, string version = "1")
    {
        string file = Path.Join(sdk, version, FileName);
        try
        {
            JsonNode root = JsonNode.Parse(File.ReadAllText(file)) ?? throw new JsonException("The catalog is empty.");
            List<BootMediaSet> sets = [];
            foreach (JsonNode? node in root["media"]?.AsArray() ?? [])
            {
                JsonObject set = node?.AsObject() ?? throw new JsonException("A set is null.");
                sets.Add(new(
                    Required(set, "id"),
                    Required(set, "title"),
                    Required(set, "for"),
                    Required(set, "source"),
                    set["variable"]?.GetValue<string>(),
                    Required(set, "folder"),
                    [.. (set["files"]?.AsArray() ?? []).Select(entry => new BootMediaFile(
                        Required(entry?.AsObject() ?? throw new JsonException("A file is null."), "name"),
                        entry["size"]?.GetValue<int>() ?? throw new JsonException("A file gives no size."),
                        Required(entry.AsObject(), "sha1").ToLowerInvariant()))]));
            }

            return sets;
        }
        catch (Exception exception) when (exception is IOException or UnauthorizedAccessException or JsonException or InvalidOperationException or FormatException)
        {
            throw new ProjectException($"{file}: the SDK's catalog of boot media cannot be read: {exception.Message}");
        }

        static string Required(JsonObject json, string field) =>
            json[field]?.GetValue<string>() ?? throw new JsonException($"A set or file gives no '{field}'.");
    }

    /// <summary>
    ///  Finds a set by its id.
    /// </summary>
    /// <param name="sdk">The SDK's root.</param>
    /// <param name="id">The set's id, such as <c>c4040</c>.</param>
    /// <returns>The set.</returns>
    /// <exception cref="ProjectException">The catalog cannot be read, or has no such set.</exception>
    internal static BootMediaSet Named(string sdk, string id) =>
        Catalog(sdk).FirstOrDefault(set => set.Id == id)
            ?? throw new ProjectException($"The SDK's catalog of boot media has no set '{id}'.");

    /// <summary>
    ///  Gets the folder <c>RETROCORE_CACHE</c> names, or its default, <c>%USERPROFILE%\Retrocore</c>.
    /// </summary>
    internal static string CacheDirectory =>
        Environment.GetEnvironmentVariable("RETROCORE_CACHE") is { Length: > 0 } cache
            ? cache
            : Path.Join(Environment.GetFolderPath(Environment.SpecialFolder.UserProfile), "Retrocore");

    /// <summary>
    ///  Gets the folders a set's files are looked for in, in order: a target's <c>bootImage</c>, the launch's ROM
    ///  folder, the folder the set's variable names, and the cache.
    /// </summary>
    /// <param name="set">The set.</param>
    /// <param name="bootImage">The target's <c>bootImage</c>, or null.</param>
    /// <param name="romDirectory">The launch's ROM folder, such as a PET's <c>romDirectory</c>, or null.</param>
    /// <returns>The folders, those that exist.</returns>
    internal static List<string> Roots(BootMediaSet set, string? bootImage, string? romDirectory = null)
    {
        List<string> roots = [];
        if (bootImage is not null) { roots.Add(bootImage); }
        if (!string.IsNullOrWhiteSpace(romDirectory)) { roots.Add(Path.GetFullPath(romDirectory)); }
        string? folder = set.Variable is { } variable ? Environment.GetEnvironmentVariable(variable) : null;
        if (!string.IsNullOrEmpty(folder)) { roots.Add(folder); }
        roots.Add(CacheDirectory);
        return [.. roots.Where(Directory.Exists).Distinct(StringComparer.OrdinalIgnoreCase)];
    }

    /// <summary>
    ///  Finds each of a set's files by its size and hash in folders and their subfolders.
    /// </summary>
    /// <param name="set">The set.</param>
    /// <param name="roots">The folders, searched in order.</param>
    /// <returns>Each file's path, by its catalog name, or null when one is not found.</returns>
    internal static Dictionary<string, string>? Find(BootMediaSet set, IEnumerable<string> roots)
    {
        HashSet<long> sizes = [.. set.Files.Select(file => (long)file.Size)];
        Dictionary<string, BootMediaFile> wanted = set.Files.ToDictionary(file => file.Sha1, StringComparer.Ordinal);
        Dictionary<string, string> found = [];
        foreach (string root in roots)
        {
            foreach (FileInfo file in Files(root))
            {
                if (!sizes.Contains(file.Length)) { continue; }
                string hash;
                try
                {
                    hash = Convert.ToHexStringLower(SHA1.HashData(File.ReadAllBytes(file.FullName)));
                }
                catch (Exception exception) when (exception is IOException or UnauthorizedAccessException)
                {
                    continue;
                }

                if (wanted.TryGetValue(hash, out BootMediaFile? match)) { found.TryAdd(match.Name, file.FullName); }
                if (found.Count == set.Files.Count) { return found; }
            }
        }

        return null;
    }

    // A folder's files and its subfolders', a linked file among them, but not a linked folder's, so no search loops.
    private static IEnumerable<FileInfo> Files(string root)
    {
        EnumerationOptions options = new() { IgnoreInaccessible = true, AttributesToSkip = 0 };
        Stack<DirectoryInfo> folders = new([new DirectoryInfo(root)]);
        while (folders.TryPop(out DirectoryInfo? folder))
        {
            foreach (FileInfo file in folder.EnumerateFiles("*", options)) { yield return file; }
            foreach (DirectoryInfo child in folder.EnumerateDirectories("*", options))
            {
                if (!child.Attributes.HasFlag(FileAttributes.ReparsePoint)) { folders.Push(child); }
            }
        }
    }

    /// <summary>
    ///  Copies a set's files, found by hash, to a folder under their catalog names, as a launch that loads them by name
    ///  takes them.
    /// </summary>
    /// <param name="set">The set.</param>
    /// <param name="found">Each file's path, by its catalog name.</param>
    /// <param name="destination">The folder to put the set's folder in.</param>
    /// <returns>The set's folder there.</returns>
    /// <exception cref="IOException">A file cannot be copied.</exception>
    /// <exception cref="UnauthorizedAccessException">A file cannot be copied.</exception>
    internal static string Gather(BootMediaSet set, IReadOnlyDictionary<string, string> found, string destination)
    {
        string folder = Path.Join(destination, set.Folder);
        Directory.CreateDirectory(folder);
        foreach ((string name, string path) in found)
        {
            File.Copy(path, Path.Join(folder, name), overwrite: true);
        }

        return folder;
    }

    /// <summary>
    ///  Says that a set was not found: what it is, its files, where they were looked for and where to put them.
    /// </summary>
    /// <param name="set">The set.</param>
    /// <param name="roots">The folders searched.</param>
    /// <returns>The text, which ends a sentence.</returns>
    internal static string Missing(BootMediaSet set, IReadOnlyList<string> roots)
    {
        string files = string.Join(", ", set.Files.Select(file => $"{file.Name} (SHA-1 {file.Sha1})"));
        string searched = roots.Count == 0 ? "no folder, as none of them exists" : string.Join(", ", roots);
        string variable = set.Variable is { } name ? $", or the folder {name} names" : "";
        return string.Create(
            CultureInfo.InvariantCulture,
            $"{set.Title}, for {set.For}, were not found by their hashes in {searched}. They are {set.Source}: {files}. Put them in {CacheDirectory}{variable}, or name their folder with the target's 'bootImage'");
    }
}
