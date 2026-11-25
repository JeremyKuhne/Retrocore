// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using Retrocore.Media.Atari;
using Retrocore.Media.Floppy;

namespace Retrocore.Machines.Atari;

/// <summary>
///  A disk image as an 810's FD1771 sees it: 40 tracks of 18 single-density sectors, in the order the 810's firmware
///  formats them, holding the inverted bytes its inverted data bus writes.
/// </summary>
/// <remarks>
///  <para>
///   Logical sector <c>n</c> (1-720) is sector <c>(n - 1) % 18 + 1</c> on track <c>(n - 1) / 18</c>. Each track is
///   in the order the firmware formats it, from the index: revision C writes sector 18, then the odd sectors, then
///   the even ones, so each sector follows the one before it 9 or 10 slots on, in turn (Altirra 10.9); revision B
///   writes 18, 7, 14, 3 and on, 13 apart (13:1). Each firmware's table of the order follows its reset code. Sectors
///   past 720, and disks with 256-byte sectors, aren't on the 810's tracks.
///  </para>
///  <para>
///   What the controller writes goes back to the image when its command ends (<see cref="Sync"/>), so the image is
///   what saves.
///  </para>
/// </remarks>
internal sealed class Atari810Disk
{
    /// <summary>
    ///  The tracks.
    /// </summary>
    public const int Tracks = 40;

    /// <summary>
    ///  The sectors on a track.
    /// </summary>
    public const int SectorsPerTrack = 18;

    private const int SectorSize = 128;

    private static readonly int[] s_orderC = [18, 1, 3, 5, 7, 9, 11, 13, 15, 17, 2, 4, 6, 8, 10, 12, 14, 16];
    private static readonly int[] s_orderB = [18, 7, 14, 3, 10, 17, 6, 13, 2, 9, 16, 5, 12, 1, 8, 15, 4, 11];

    private long _synced;

    /// <summary>
    ///  Lays out an image's sectors.
    /// </summary>
    /// <param name="image">The image.</param>
    /// <param name="revision">The firmware's revision, <c>'B'</c> or <c>'C'</c>, for the sector order.</param>
    public Atari810Disk(AtariDisk image, char revision)
    {
        Image = image;
        Floppy = new() { IsWriteProtected = image.IsWriteProtected };
        int[] order = revision == 'B' ? s_orderB : s_orderC;
        byte[] data = new byte[SectorSize];
        int sectors = image.SectorSize == SectorSize ? Math.Min(image.SectorCount, Tracks * SectorsPerTrack) : 0;
        for (int track = 0; track < Tracks; track++)
        {
            foreach (int sector in order)
            {
                int logical = (track * SectorsPerTrack) + sector;
                if (logical <= sectors)
                {
                    image.ReadSector(logical, data);
                }
                else
                {
                    data.AsSpan().Clear();
                }

                Invert(data);
                Floppy.Add(track, 0, new((byte)track, 0, (byte)sector, data, doubleDensity: false));
            }
        }

        _synced = Floppy.Version;
    }

    /// <summary>
    ///  Gets the image.
    /// </summary>
    public AtariDisk Image { get; }

    /// <summary>
    ///  Gets the tracks the controller reads.
    /// </summary>
    public FloppyDisk Floppy { get; }

    /// <summary>
    ///  Copies what the controller has written back to the image, a sector at a time where it differs, and follows the
    ///  image's write protection.
    /// </summary>
    public void Sync()
    {
        bool protect = Image.IsWriteProtected;
        if (Floppy.Version != _synced && Image.SectorSize == SectorSize)
        {
            try
            {
                CopyBack();
            }
            finally
            {
                Image.IsWriteProtected = protect;
            }
        }

        _synced = Floppy.Version;
        if (Floppy.IsWriteProtected != protect) { Floppy.IsWriteProtected = protect; }
    }

    private void CopyBack()
    {
        Span<byte> written = stackalloc byte[SectorSize];
        Span<byte> current = stackalloc byte[SectorSize];
        int sectors = Math.Min(Image.SectorCount, Tracks * SectorsPerTrack);
        foreach ((int cylinder, int _, IReadOnlyList<FloppySector> track) in Floppy.Tracks())
        {
            foreach (FloppySector sector in track)
            {
                int logical = (cylinder * SectorsPerTrack) + sector.Sector;
                bool ours = sector.Track == cylinder && sector.Sector is >= 1 and <= SectorsPerTrack;
                if (!ours || logical > sectors || sector.Data.Length != SectorSize) { continue; }

                sector.Data.CopyTo(written);
                Invert(written);
                Image.ReadSector(logical, current);
                if (written.SequenceEqual(current)) { continue; }

                // A write the controller took before the image was protected is on the disk: it still goes to the
                // image, past the protection Sync puts back.
                Image.IsWriteProtected = false;
                Image.WriteSector(logical, written);
            }
        }
    }

    private static void Invert(Span<byte> data)
    {
        for (int i = 0; i < data.Length; i++) { data[i] = (byte)~data[i]; }
    }
}
