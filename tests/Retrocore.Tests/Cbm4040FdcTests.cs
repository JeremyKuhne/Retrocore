// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using Retrocore.Machines.Commodore;
using Retrocore.Media.Commodore;

namespace Retrocore.Tests;

/// <summary>
///  The 4040's read/write logic on its own, with the GCR PROM from MAME's <c>c4040</c> set.
/// </summary>
[TestClass]
public class Cbm4040FdcTests
{
    private static byte[] Gcr()
    {
        string path = Path.Join(PetMachineTests.RomRoot, "c4040", "901467.uk6");
        if (!File.Exists(path)) { Assert.Inconclusive("Set RETROCORE_PET_ROMS to a folder with MAME's c4040 set."); }
        return File.ReadAllBytes(path);
    }

    /// <summary>
    ///  Reading a track at its zone's speed, each READY after sync gives the next byte of every sector.
    /// </summary>
    /// <param name="track">The track.</param>
    [TestMethod]
    [DataRow(1)]
    [DataRow(18)]
    [DataRow(25)]
    [DataRow(35)]
    public void ReadsEveryByte(int track)
    {
        byte[] image = new byte[D64Format.Size];
        Random random = new(track);
        random.NextBytes(image);
        CommodoreDisk disk = D64Format.Read(image);

        CommodoreFloppyDrive drive0 = new(8, drive: 0, "4040");
        CommodoreFloppyDrive drive1 = new(8, drive: 1, "4040");
        drive0.Insert(disk, "random", "D64");
        drive0.Motor = true;
        for (int step = 0; step < (track - 1) * 2; step++) { drive0.Step(step + 1); }
        drive0.Position.Should().Be((track - 1) * 2);

        Cbm4040Fdc fdc = new(Gcr(), drive0, drive1) { ReadSelect = true, Zone = GcrLayout.Zone(track) };

        // After each sync, the bytes up to the next.
        List<List<byte>> blocks = [];
        List<byte>? block = null;
        bool wasSync = false;
        for (int microsecond = 0; microsecond < 200_000 * 2; microsecond++)
        {
            fdc.Advance(ticks: 16);
            bool sync = !fdc.Sync;
            if (sync && !wasSync)
            {
                block = [];
                blocks.Add(block);
            }

            wasSync = sync;
            if (fdc.ReadyChanges >= 2) { block?.Add(fdc.ReadData); }
        }

        int sectors = GcrLayout.SectorsOn(track);
        int offset = GcrLayout.FirstSector(track) * 256;
        int good = 0;
        for (int index = 0; index + 1 < blocks.Count; index++)
        {
            List<byte> header = blocks[index];
            if (header.Count < 6 || header[0] != 0x08) { continue; }
            int sector = header[2];
            header[3].Should().Be((byte)track);
            List<byte> data = blocks[index + 1];
            data.Count.Should().BeGreaterThan(257, $"sector {sector}'s data block is read whole");
            data[0].Should().Be(0x07);
            data.Skip(1).Take(256).Should().Equal(image.AsSpan(offset + (sector * 256), 256).ToArray(), $"sector {sector}");
            good++;
        }

        good.Should().BeGreaterThanOrEqualTo(sectors);
    }

    /// <summary>
    ///  Bytes written at a zone's speed, a sync mark then GCR, read back as written.
    /// </summary>
    /// <param name="track">The track.</param>
    [TestMethod]
    [DataRow(1)]
    [DataRow(18)]
    [DataRow(25)]
    [DataRow(35)]
    public void WritesAndReadsBack(int track)
    {
        CommodoreDisk disk = CommodoreDisk.Blank();
        CommodoreFloppyDrive drive0 = new(8, drive: 0, "4040");
        CommodoreFloppyDrive drive1 = new(8, drive: 1, "4040");
        drive0.Insert(disk, "blank", "D64");
        drive0.Motor = true;
        for (int step = 0; step < (track - 1) * 2; step++) { drive0.Step(step + 1); }

        Cbm4040Fdc fdc = new(Gcr(), drive0, drive1) { Zone = GcrLayout.Zone(track) };
        Random random = new(track);
        byte[] payload = new byte[3000];
        random.NextBytes(payload);

        // As a data block does, start with a byte whose code starts with a 0, which ends the sync.
        payload[0] = 0x07;

        // Five sync bytes with MODE SEL high, then the payload encoded.
        fdc.ReadSelect = false;
        fdc.ModeSelect = true;
        fdc.WriteData = 0xFF;
        int sent = 0;
        while (sent < 5 + payload.Length + 2)
        {
            fdc.Advance(ticks: 16);
            if (fdc.ReadyChanges < 2) { continue; }
            sent++;
            if (sent >= 5)
            {
                fdc.ModeSelect = false;
                fdc.WriteData = payload[Math.Min(sent - 5, payload.Length - 1)];
            }
        }

        {
            int position = drive0.Position;
            int count = disk.BitCount(position);
            byte[] bits = disk.Track(position).ToArray();
            bool Bit(int p) => (bits[(p % count) >> 3] & (0x80 >> ((p % count) & 7))) != 0;
            int ones = 0;
            int at = 0;
            while (at < count * 2)
            {
                if (Bit(at)) { ones++; }
                else if (ones >= 10) { break; }
                else { ones = 0; }
                at++;
            }

            string got = "";
            string want = "";
            for (int n = 0; n < 8; n++)
            {
                int code = 0;
                for (int i = 0; i < 10; i++) { code = (code << 1) | (Bit(at++) ? 1 : 0); }
                got += $" {code:X3}";
                want += $" {GcrLayout.Encode(payload[n]):X3}";
            }

            got.Should().Be(want, $"sync of {ones} ends at {at - 80}, count {count}");
        }

        fdc.ReadSelect = true;
        List<byte>? read = null;
        bool wasSync = false;
        for (int microsecond = 0; microsecond < 400_000; microsecond++)
        {
            fdc.Advance(ticks: 16);
            bool sync = !fdc.Sync;
            if (sync && !wasSync && read is null) { read = []; }
            wasSync = sync;
            if (fdc.ReadyChanges >= 2 && read is not null && read.Count < payload.Length) { read.Add(fdc.ReadData); }
        }

        read.Should().NotBeNull();
        read.Should().Equal(payload);
    }
}
