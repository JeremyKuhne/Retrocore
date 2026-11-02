// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using Retrocore.Media;
using System.Security.Cryptography;
using Touki;

namespace AppleSharp;

/// <summary>
///  App-owned native floppy media. Dirty WOZ data is explicitly persisted on motor-off/eject/exit.
///  Raw .dsk/.do/.po floppy conversion is read-only; slot-seven .po writes remain supported separately.
/// </summary>
internal sealed class FloppyMount : DisposableBase
{
    private byte[] _savedHash;

    /// <summary>
    ///  Loads a WOZ image or encodes raw sectors without requiring a graphics or debugger dependency.
    /// </summary>
    /// <param name="path">The user-selected media.</param>
    /// <param name="writable">Whether WOZ writes are explicitly enabled.</param>
    internal FloppyMount(string path, bool writable)
    {
        Path = System.IO.Path.GetFullPath(path);
        byte[] data = File.ReadAllBytes(Path);
        _savedHash = SHA256.HashData(data);
        string extension = System.IO.Path.GetExtension(Path).ToLowerInvariant();
        Disk = extension switch
        {
            ".woz" => WozDisk.Load(data, writable),
            ".dsk" or ".do" or ".po" when !writable => SectorDiskConverter.Convert(data, extension == ".po"),
            ".d13" when !writable => SectorDiskConverter.ConvertThirteenSector(data),
            ".dsk" or ".do" or ".po" or ".d13" => throw new NotSupportedException(
                "Writable raw floppy conversion is not supported. Export to .woz first, or use the slot-seven .po block device."),
            _ => throw new InvalidDataException("Disk II mounts .woz, .dsk, .do, .po or .d13 floppy images.")
        };
    }

    /// <summary>
    ///  Gets the source filename.
    /// </summary>
    internal string Path { get; }

    /// <summary>
    ///  Gets caller-owned bitstream media.
    /// </summary>
    internal WozDisk Disk { get; }

    /// <summary>
    ///  Persists changed WOZ media atomically and refuses to overwrite externally changed input.
    /// </summary>
    internal void Save()
    {
        if (!Disk.IsDirty) { return; }
        if (Disk.IsReadOnly) { throw new InvalidOperationException("Read-only media unexpectedly became dirty."); }
        if (!MemoryExtensions.SequenceEqual(SHA256.HashData(File.ReadAllBytes(Path)), _savedHash))
        {
            throw new IOException("The floppy image changed outside AppleSharp; refusing to overwrite it.");
        }

        byte[] data = Disk.Export();
        string temporary = Path + "." + Guid.NewGuid().ToString("N") + ".tmp";
        try
        {
            using (FileStream output = new(temporary, FileMode.CreateNew, FileAccess.Write, FileShare.None))
            {
                output.Write(data);
                output.Flush(flushToDisk: true);
            }

            File.Move(temporary, Path, overwrite: true);
            _savedHash = SHA256.HashData(data);
            Disk.MarkSaved();
        }
        finally
        {
            if (File.Exists(temporary)) { File.Delete(temporary); }
        }
    }

    /// <inheritdoc/>
    protected override void Dispose(bool disposing)
    {
        if (disposing) { Save(); }
    }
}
