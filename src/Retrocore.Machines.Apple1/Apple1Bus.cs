// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using Retrocore.Cpu;

namespace Retrocore.Machines.Apple1;

/// <summary>
///  The Apple-1's memory map.
/// </summary>
/// <remarks>
///  <para>
///   RAM fills <c>$0000</c> up (4 or 8K), and an optional 4K bank sits at <c>$E000</c>. The cassette interface
///   answers at <c>$C000</c>-<c>$C1FF</c>. The PIA answers in <c>$D000</c>-<c>$DFFF</c> wherever address bit 4 is
///   set, its registers chosen by bits 0 and 1: <c>$D010</c> KBD, <c>$D011</c> KBDCR, <c>$D012</c> DSP and
///   <c>$D013</c> DSPCR. The Monitor's PROMs see only the low byte of the address, so they fill
///   <c>$F000</c>-<c>$FFFF</c>. Everything else reads the high byte of the address.
///  </para>
/// </remarks>
public sealed class Apple1Bus : IProcessorBus
{
    private const ushort CassetteStart = 0xC000;
    private const ushort CassetteEnd = 0xC200;
    private const ushort HighRamStart = 0xE000;
    private const int HighRamSize = 0x1000;

    private readonly byte[] _ram;
    private readonly byte[] _highRam;
    private readonly byte[] _monitor;

    /// <summary>
    ///  Creates the bus.
    /// </summary>
    /// <param name="configuration">The machine's options.</param>
    /// <param name="roms">The Monitor, the character generator and the cassette interface's PROM.</param>
    internal Apple1Bus(Apple1Configuration configuration, Apple1Roms roms)
    {
        _ram = new byte[configuration.RamKilobytes * 1024];
        _highRam = configuration.HighRam ? new byte[HighRamSize] : [];
        _monitor = roms.Monitor.ToArray();
        Terminal = new(roms.CharacterGenerator, Pia);
        Keyboard = new(Pia);
        Cassette = configuration.CassetteInterface ? new(roms.Cassette) : null;
    }

    /// <summary>
    ///  Gets the PIA that connects the keyboard and the terminal.
    /// </summary>
    public Pia6821 Pia { get; } = new();

    /// <summary>
    ///  Gets the video terminal.
    /// </summary>
    public Apple1Terminal Terminal { get; }

    /// <summary>
    ///  Gets the keyboard.
    /// </summary>
    public Apple1Keyboard Keyboard { get; }

    /// <summary>
    ///  Gets the cassette interface, or null when the slot is empty.
    /// </summary>
    public Apple1Cassette? Cassette { get; }

    /// <inheritdoc/>
    public byte Read(ushort address)
    {
        if (address < _ram.Length) { return _ram[address]; }
        return Area(address) switch
        {
            Apple1MemoryArea.Ram => _highRam[address - HighRamStart],
            Apple1MemoryArea.Monitor => _monitor[address & 0xFF],
            Apple1MemoryArea.Pia => ReadPia(address),
            Apple1MemoryArea.CassetteInterface or Apple1MemoryArea.CassetteRom => Cassette?.Read(address - CassetteStart) ?? (byte)(address >> 8),
            _ => (byte)(address >> 8)
        };
    }

    /// <inheritdoc/>
    public void Write(ushort address, byte value)
    {
        if (address < _ram.Length)
        {
            _ram[address] = value;
            return;
        }

        switch (Area(address))
        {
            case Apple1MemoryArea.Ram:
                _highRam[address - HighRamStart] = value;
                break;
            case Apple1MemoryArea.Pia:
                Pia.Write(address, value);
                break;
            case Apple1MemoryArea.CassetteInterface:
            case Apple1MemoryArea.CassetteRom:
                Cassette?.Write(address - CassetteStart);
                break;
        }
    }

    /// <summary>
    ///  Reads without side effects, for the debugger.
    /// </summary>
    /// <param name="address">The address.</param>
    /// <returns>The byte a read would return.</returns>
    public byte Peek(ushort address) => Area(address) switch
    {
        Apple1MemoryArea.Pia => PeekPia(address),
        Apple1MemoryArea.CassetteInterface or Apple1MemoryArea.CassetteRom => Cassette?.Peek(address - CassetteStart) ?? (byte)(address >> 8),
        _ => Read(address)
    };

    /// <summary>
    ///  Gets the region an address is in.
    /// </summary>
    /// <param name="address">The address.</param>
    /// <returns>The region.</returns>
    public Apple1MemoryArea Area(ushort address) => address switch
    {
        _ when address < _ram.Length => Apple1MemoryArea.Ram,
        >= 0xF000 => Apple1MemoryArea.Monitor,
        >= HighRamStart and < HighRamStart + HighRamSize when _highRam.Length != 0 => Apple1MemoryArea.Ram,
        >= 0xD000 and < 0xE000 when (address & 0x10) != 0 => Apple1MemoryArea.Pia,
        >= CassetteStart and < CassetteStart + 0x100 when Cassette is not null => Apple1MemoryArea.CassetteInterface,
        >= CassetteStart + 0x100 and < CassetteEnd when Cassette is not null => Apple1MemoryArea.CassetteRom,
        _ => Apple1MemoryArea.Unmapped
    };

    /// <summary>
    ///  Copies bytes into RAM, for loading a program.
    /// </summary>
    /// <param name="address">The first address.</param>
    /// <param name="bytes">The bytes.</param>
    /// <exception cref="ArgumentException">An address the bytes would fill is not RAM.</exception>
    public void Load(ushort address, ReadOnlySpan<byte> bytes)
    {
        for (int index = 0; index < bytes.Length; index++)
        {
            int target = address + index;
            if (target > ushort.MaxValue || Area((ushort)target) != Apple1MemoryArea.Ram)
            {
                throw new ArgumentException($"${target:X4} is not RAM.", nameof(bytes));
            }
        }

        for (int index = 0; index < bytes.Length; index++) { Write((ushort)(address + index), bytes[index]); }
    }

    /// <summary>
    ///  Advances the devices one cycle.
    /// </summary>
    internal void Tick()
    {
        Terminal.Tick();
        Keyboard.Tick();
        Pia.Tick();
        Cassette?.Tick();
    }

    private byte ReadPia(ushort address)
    {
        UpdateDisplayReady();
        return Pia.Read(address);
    }

    private byte PeekPia(ushort address)
    {
        UpdateDisplayReady();
        return Pia.Peek(address);
    }

    // PB7 reads the terminal's busy line; the other port B lines are pulled up.
    private void UpdateDisplayReady() => Pia.InputB = Terminal.Busy ? (byte)0xFF : (byte)0x7F;
}
