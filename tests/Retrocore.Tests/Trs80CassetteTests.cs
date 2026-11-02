// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using Retrocore.Machines.Trs80;
using Retrocore.Media.Trs80;

namespace Retrocore.Tests;

/// <summary>
///  The cassette interface records the pulses a program writes as CAS bytes, and plays them back to the latch.
/// </summary>
[TestClass]
public class Trs80CassetteTests
{
    private const int PulseCycles = 220;

    /// <summary>
    ///  A 500 baud recording of leader, sync and data plays back bit for bit.
    /// </summary>
    [TestMethod]
    public void RecordsAndPlaysBack()
    {
        Trs80Bus bus = Trs80MachineTests.Create(new()).Bus;
        Trs80Cassette cassette = bus.Cassette;
        cassette.CellCycles.Should().Be(3548);
        byte[] payload = [0x55, 0x3C, 0x00, 0xFF, 0x12, 0x81];
        byte[] expected = [.. Enumerable.Repeat((byte)0, 16), 0xA5, .. payload];

        CassetteImage tape = new();
        cassette.Record(tape);
        bus.Out(0xFF, 0x04);
        foreach (byte value in expected)
        {
            for (int bit = 7; bit >= 0; bit--) { WriteCell(bus, cassette.CellCycles, ((value >> bit) & 1) != 0); }
        }

        bus.Out(0xFF, 0x00);
        tape.Bytes.Should().Equal(expected);

        cassette.Play(tape);
        bus.Out(0xFF, 0x04);
        List<long> pulses = [];
        for (long time = 0; !cassette.AtEnd && time < 10_000_000; time++)
        {
            bus.Tick();
            if ((bus.In(0xFF) & 0x80) == 0) { continue; }
            pulses.Add(time);
            bus.Out(0xFF, 0x04);
        }

        Decode(pulses, cassette.CellCycles).Should().Equal(expected);
    }

    /// <summary>
    ///  Level I tapes run at 250 baud.
    /// </summary>
    [TestMethod]
    public void LevelOneRunsAtHalfSpeed()
    {
        byte[] rom = new byte[0x1000];
        byte[] font = new byte[Trs80Roms.CharacterGeneratorSize];
        Trs80Configuration configuration = new()
        {
            Rom = Trs80Rom.Level1,
            RamKilobytes = 4,
            ExpansionInterface = false
        };

        Trs80Machine machine = new(configuration, new(rom, font));
        machine.Bus.Cassette.CellCycles.Should().Be(7096);
        machine.Bus.Area(0x1000).Should().Be(Trs80MemoryArea.Unmapped);
    }

    // A clock pulse, then for a 1 a data pulse half a cell later: output positive, then negative, then zero.
    private static void WriteCell(Trs80Bus bus, int cell, bool one)
    {
        Pulse(bus);
        Run(bus, (cell / 2) - (2 * PulseCycles));
        if (one) { Pulse(bus); }
        else { Run(bus, 2 * PulseCycles); }
        Run(bus, cell - (cell / 2) - (2 * PulseCycles));
    }

    private static void Pulse(Trs80Bus bus)
    {
        bus.Out(0xFF, 0x05);
        Run(bus, PulseCycles);
        bus.Out(0xFF, 0x06);
        Run(bus, PulseCycles);
        bus.Out(0xFF, 0x04);
    }

    private static void Run(Trs80Bus bus, int cycles)
    {
        for (int index = 0; index < cycles; index++) { bus.Tick(); }
    }

    // A pulse more than three quarters of a cell after the last clock pulse is the next clock pulse.
    private static List<byte> Decode(List<long> pulses, int cell)
    {
        List<bool> bits = [];
        long clock = pulses[0];
        bool data = false;
        foreach (long pulse in pulses.Skip(1))
        {
            if (pulse - clock < cell * 3 / 4)
            {
                data = true;
                continue;
            }

            bits.Add(data);
            clock = pulse;
            data = false;
        }

        bits.Add(data);
        List<byte> bytes = [];
        for (int index = 0; index + 8 <= bits.Count; index += 8)
        {
            bytes.Add((byte)bits.Skip(index).Take(8).Aggregate(0, (value, bit) => (value << 1) | (bit ? 1 : 0)));
        }

        return bytes;
    }
}
