// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using System.Buffers.Binary;
using System.Security.Cryptography;
using Retrocore.Machines.Commodore;
using Retrocore.Media.Commodore;

namespace Retrocore.Debug;

/// <summary>
///  Completes the data transfer of a verified SDK PET project tape.
/// </summary>
internal sealed class PetTapeSkip
{
    /// <summary>
    ///  The SDK PET 4032 BASIC 4 LD100 tail jump to TRD.
    /// </summary>
    internal const ushort Boundary = 0xF3FE;
    private const ushort Continuation = 0xF418;
    private const ushort TapeReturn = 0xF92A;
    private const ushort EditorIrq = 0xE455;
    private const ushort ProgramStart = 0x0401;
    // The verified ROM stops two pulses into the 80 short pulses at either block's tail.
    private const int HeaderEnd = 35_299;
    private const int TailRemaining = 78;

    private readonly PetMachine _machine;
    private readonly CommodoreDatasette _deck;
    private readonly CommodoreTape _tape;
    private readonly int _mount;
    private readonly long _version;
    private readonly byte[] _payload;
    private readonly byte _checksum;

    private PetTapeSkip(PetMachine machine, CommodoreDatasette deck, CommodoreTape tape, ReadOnlySpan<byte> payload)
    {
        _machine = machine;
        _deck = deck;
        _tape = tape;
        _mount = deck.MountGeneration;
        _version = tape.Version;
        _payload = payload.ToArray();
        foreach (byte value in payload) { _checksum ^= value; }
        EarliestCycle = machine.Processor.CycleCount;
        for (int i = 0; i < HeaderEnd; i++) { EarliestCycle += (ulong)tape.Pulses[i]; }
    }

    /// <summary>
    ///  Gets the earliest cycle the deck could finish the header, even if its motor never stopped.
    /// </summary>
    internal ulong EarliestCycle { get; }

    /// <summary>
    ///  Verifies the ROMs and both copies of the mounted tape before boot runs it.
    /// </summary>
    /// <param name="target">The fresh project machine.</param>
    /// <param name="name">The tape's expected program name.</param>
    /// <param name="prg">The expected PRG, including its load address.</param>
    /// <returns>A prepared transfer if supported, otherwise null.</returns>
    internal static PetTapeSkip? Prepare(PetDebugTarget target, string name, byte[] prg)
    {
        PetMachine machine = target.Machine;
        CommodoreDatasette deck = target.BootDeck;
        if (machine.Model != PetModel.Pet4032
            || machine.Disks.Count != 0
            || machine.Bus.Cassette2.Tape is not null
            || deck.Tape is not { IsDirty: false } tape
            || prg.Length < 3
            || Word(prg, 0) != ProgramStart
            || ProgramStart + prg.Length - 2 > machine.Bus.Ram.Length
            || !RomMatches(machine.Bus, 0xB000, 0x3800, "F954EB647B6CE1DA88AD431C26F09D1360A71EA1E3E1776A4769EDD9580597C9")
            || !RomMatches(machine.Bus, 0xF000, 0x1000, "7CF8678B748BDA1FFEDEE69EA54888FEB3F5EC66DCA8143375CBDF8C3DE4D573")
            || !tape.Pulses.SequenceEqual(CommodoreTapeBuilder.FromPrg(name, prg).Pulses))
        {
            return null;
        }

        return new(machine, deck, tape, prg.AsSpan(2));
    }

    /// <summary>
    ///  Completes the transfer only at the verified CALL and device boundary.
    /// </summary>
    /// <returns>Whether the transfer ran.</returns>
    internal bool TryComplete()
    {
        PetBus bus = _machine.Bus;
        Processor<PetBus> cpu = _machine.Processor;
        if (!cpu.IsInstructionBoundary
            || bus.InterruptRequested
            || cpu.Signals != ProcessorSignals.None
            || !ReferenceEquals(_deck.Tape, _tape)
            || _deck.MountGeneration != _mount
            || _tape.Version != _version
            || _deck.Position != HeaderEnd
            || bus.Cassette2.Motor)
        {
            return false;
        }

        ProcessorRegisters registers = cpu.Registers;
        Span<byte> ram = bus.Ram;
        int end = ProgramStart + _payload.Length;
        if (registers.ProgramCounter != Boundary
            || registers.StackPointer > 0xFD
            || Word(ram, 0x101 + registers.StackPointer) != Continuation - 1
            || (registers.Status & (StatusRegister.IRQBDisable | StatusRegister.DecimalMode)) != 0
            || Word(ram, 0x90) != EditorIrq
            || ram[0x78] != 2
            || ram[0x96] != 0
            || ram[0x9B] != 0xFF
            || ram[0x9D] != 0
            || ram[0xD1] != 0
            || ram[0xD4] != 1
            || ram[0x27A] != 1
            || Word(ram, 0x27B) != ProgramStart
            || Word(ram, 0x27D) != end
            || Word(ram, 0xFB) != ProgramStart
            || Word(ram, 0xC7) != ProgramStart
            || Word(ram, 0xC9) != end
            || (bus.Pia1.ControlA & 1) != 0
            || (bus.Pia1.ControlB & 1) == 0
            || (bus.Via.Peek(14) & 0x7F) != 0
            || !_deck.TrySkipTo(_tape.Pulses.Count - TailRemaining))
        {
            return false;
        }

        _payload.CopyTo(ram[ProgramStart..]);
        BinaryPrimitives.WriteUInt16LittleEndian(ram[0xC7..], (ushort)end); // SAL after the final checksum scan
        ram[0xC3] = ram[0xDD] = ram[0xDF] = _checksum;
        registers.Accumulator = EditorIrq >> 8;
        registers.X = registers.Y = 0;
        registers.Status = (registers.Status & ~StatusRegister.Negative) | StatusRegister.Zero | StatusRegister.Carry;
        registers.ProgramCounter = TapeReturn;
        cpu.Registers = registers;
        return true;
    }

    private static ushort Word(ReadOnlySpan<byte> bytes, int start) => BinaryPrimitives.ReadUInt16LittleEndian(bytes[start..]);

    private static bool RomMatches(PetBus bus, int start, int count, string sha256)
    {
        byte[] bytes = new byte[count];
        for (int i = 0; i < count; i++) { bytes[i] = bus.Peek((ushort)(start + i)); }
        return Convert.ToHexString(SHA256.HashData(bytes)) == sha256;
    }
}
