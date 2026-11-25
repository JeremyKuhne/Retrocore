// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using Retrocore.Media.Atari;

namespace Retrocore.Machines.Atari;

/// <summary>
///  Runs binary load files (<c>.xex</c>, <c>.com</c>, <c>.exe</c>) without DOS: a boot disk of our loader
///  (<c>Roms/ExecutableLoader.rom.asm</c>) and the file, which the OS boots from <c>D1:</c>.
/// </summary>
public static class AtariExecutable
{
    /// <summary>
    ///  Gets whether data looks like a binary load file: it starts with the <c>$FFFF</c> header.
    /// </summary>
    /// <param name="file">The file.</param>
    /// <returns>Whether it starts <c>$FF $FF</c>.</returns>
    public static bool IsExecutable(ReadOnlySpan<byte> file) => file.Length >= 6 && file[0] == 0xFF && file[1] == 0xFF;

    /// <summary>
    ///  Builds a single-density boot disk that loads and runs a binary load file: the loader in sectors 1-3, the file
    ///  from sector 4. The disk is write-protected.
    /// </summary>
    /// <param name="file">The binary load file.</param>
    /// <returns>The disk, at least 720 sectors.</returns>
    /// <exception cref="InvalidDataException">The file isn't a binary load file, or is too big.</exception>
    public static AtariDisk BootDisk(ReadOnlySpan<byte> file)
    {
        if (!IsExecutable(file)) { throw new InvalidDataException("A binary load file starts with $FF $FF."); }
        int sectors = 3 + ((file.Length + 127) / 128);
        if (sectors > 0xFFFF) { throw new InvalidDataException("The file is too big for a boot disk."); }

        byte[] loader = ExecutableLoader.Bytes.ToArray();
        int length = ExecutableLoader.Length - ExecutableLoader.Origin;
        loader[length] = (byte)file.Length;
        loader[length + 1] = (byte)(file.Length >> 8);
        loader[length + 2] = (byte)(file.Length >> 16);

        AtariDisk disk = AtariDisk.Create(Math.Max(720, sectors));
        for (int sector = 0; sector < 3; sector++)
        {
            disk.WriteSector(sector + 1, loader.AsSpan(sector * 128, 128));
        }

        byte[] buffer = new byte[128];
        for (int offset = 0, sector = 4; offset < file.Length; offset += 128, sector++)
        {
            Array.Clear(buffer);
            file[offset..Math.Min(file.Length, offset + 128)].CopyTo(buffer);
            disk.WriteSector(sector, buffer);
        }

        disk.MarkSaved();
        disk.IsWriteProtected = true;
        return disk;
    }
}
