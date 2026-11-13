// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using Retrocore.Media;

namespace Retrocore.Debug;

/// <summary>
///  The volume an Apple Pascal disk holds: an Apple II Pascal volume or an Apple III SOS volume, seen the same way.
/// </summary>
internal sealed class PascalDisk
{
    private readonly PascalVolume? _pascal;
    private readonly SosVolume? _sos;

    /// <summary>
    ///  Constructs one over an Apple II Pascal volume.
    /// </summary>
    /// <param name="volume">The volume.</param>
    internal PascalDisk(PascalVolume volume)
    {
        _pascal = volume;
        Name = $"{volume.Name}:";
        Files = [.. volume.Files.Select(file => new PascalDiskFile(file.Name, file.Kind.ToString(), file.Length, file.Modified))];
    }

    /// <summary>
    ///  Constructs one over an Apple III SOS volume.
    /// </summary>
    /// <param name="volume">The volume.</param>
    internal PascalDisk(SosVolume volume)
    {
        _sos = volume;
        Name = $"/{volume.Name}";
        Files = [.. volume.Files.Select(file => new PascalDiskFile(file.Name, SosKind(file.FileType), file.EndOfFile, Modified: null))];
    }

    /// <summary>
    ///  Gets the volume's name as Pascal writes it: <c>APPLE1:</c> or <c>/PASCAL1</c>.
    /// </summary>
    internal string Name { get; }

    /// <summary>
    ///  Gets the files.
    /// </summary>
    internal IReadOnlyList<PascalDiskFile> Files { get; }

    /// <summary>
    ///  Finds a file by name, in any case.
    /// </summary>
    /// <param name="name">The name.</param>
    /// <returns>The file.</returns>
    /// <exception cref="InvalidDataException">The volume has no such file.</exception>
    internal PascalDiskFile Find(string name) =>
        Files.FirstOrDefault(file => string.Equals(file.Name, name, StringComparison.OrdinalIgnoreCase))
            ?? throw new InvalidDataException($"No file named {name} on {Name}; it has {string.Join(", ", Files.Select(file => file.Name))}.");

    /// <summary>
    ///  Reads a file.
    /// </summary>
    /// <param name="name">Its name, in any case.</param>
    /// <returns>Its contents.</returns>
    internal byte[] Read(string name)
    {
        PascalDiskFile file = Find(name);
        return _pascal?.ReadFile(file.Name) ?? _sos?.ReadFile(file.Name) ?? [];
    }

    // SOS's file types as Apple III Pascal's Filer names them.
    private static string SosKind(int type) => type switch
    {
        0x02 => "Code",
        0x03 => "Text",
        0x05 => "Data",
        0x0C => "Sos",
        0x0F => "Directory",
        _ => $"${type:X2}"
    };
}
