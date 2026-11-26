// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using Retrocore.Cpu;
using Retrocore.Cpu.I8080;
using Retrocore.Cpu.M6502;
using Retrocore.Cpu.M6809;
using Retrocore.Cpu.Z80;
using Retrocore.Isa;

namespace Retrocore.Assembler;

/// <summary>
///  Runs one instruction on the CPU's own core, from given register, flag and memory values, to learn the values it
///  leaves: the flags of <c>LDA #0</c>, the sum of <c>ADC #1</c> with a known carry.
/// </summary>
/// <remarks>
///  <para>
///   The core is the one the emulator runs, so the analysis needs no rules of its own for how each instruction
///   computes its flags. The instruction's own bytes and the code after them come from the image; its other reads
///   get the values the caller gives, in order, and a read past them, or any port, ends the run without a result.
///  </para>
/// </remarks>
internal sealed class AnalysisEvaluator
{
    private readonly ICpuDebugView _view;
    private readonly Func<ProcessorExecutionResult> _step;
    private readonly AnalysisEvaluationBus _bus;
    private readonly string?[] _names;
    private readonly (string Name, int High, int Low)[] _pairs;
    private readonly string _flagsRegister;
    private readonly string _programCounter;

    private AnalysisEvaluator(ICpuDebugView view, Func<ProcessorExecutionResult> step, AnalysisEvaluationBus bus, IsaDescription description)
    {
        _view = view;
        _step = step;
        _bus = bus;
        _flagsRegister = description.Flags.Count == 0 ? "" : description.Flags[0].Register;
        _programCounter = "PC";
        IReadOnlyList<string> registers = description.EffectRegisters;
        _names = new string?[registers.Count];
        List<(string Name, int High, int Low)> pairs = [];
        for (int bit = 0; bit < registers.Count; bit++)
        {
            // Only a register without parts is set by name; a pair, as AF, would overwrite its parts.
            bool single = description.RegisterMask(registers[bit]) == 1u << bit;
            if (single && view.TryGetRegister(registers[bit], out _)) { _names[bit] = registers[bit]; }
        }

        // A part the core does not name, as the Z80's IXH, is set through its pair, the first part high.
        foreach (IsaRegister register in description.Registers)
        {
            uint mask = description.RegisterMask(register.Name);
            if (System.Numerics.BitOperations.PopCount(mask) != 2 || !view.TryGetRegister(register.Name, out _))
            {
                continue;
            }

            int high = System.Numerics.BitOperations.TrailingZeroCount(mask);
            int low = 31 - System.Numerics.BitOperations.LeadingZeroCount(mask);
            if (_names[high] is null || _names[low] is null) { pairs.Add((register.Name, high, low)); }
        }

        _pairs = [.. pairs];
    }

    /// <summary>
    ///  Creates an evaluator for an instruction set, or null when no core runs it.
    /// </summary>
    /// <param name="set">The instruction set.</param>
    /// <returns>The evaluator, or null.</returns>
    internal static AnalysisEvaluator? For(InstructionSet set)
    {
        AnalysisEvaluationBus bus = new();
        switch (set.Name.ToUpperInvariant())
        {
            case "MOS6502":
                return M6502(bus, ProcessorVariant.Mos6502, set);
            case "WDC65C02" or "65SC02":
                return M6502(bus, ProcessorVariant.Wdc65C02, set);
            case "ROCKWELL65C02":
                return M6502(bus, ProcessorVariant.Rockwell65C02, set);
            case "Z80":
                Z80Processor<AnalysisEvaluationBus> z80 = new(bus);
                return new(z80, () => z80.StepInstruction(), bus, set.Description);
            case "M6809":
                M6809Processor<AnalysisEvaluationBus> m6809 = new(bus);
                return new(m6809, () => m6809.StepInstruction(), bus, set.Description);
            case "I8080" or "I8085":
                I8080Processor<AnalysisEvaluationBus> i8080 = new(bus, set.Name.EndsWith('5') ? I8080Variant.I8085 : I8080Variant.I8080);
                return new(i8080, () => i8080.StepInstruction(), bus, set.Description);
            default:
                return null;
        }
    }

    private static AnalysisEvaluator M6502(AnalysisEvaluationBus bus, ProcessorVariant variant, InstructionSet set)
    {
        Processor<AnalysisEvaluationBus> cpu = new(bus, variant);
        return new(cpu, () => cpu.StepInstruction(), bus, set.Description);
    }

    /// <summary>
    ///  Runs an instruction.
    /// </summary>
    /// <param name="pc">Where the instruction is.</param>
    /// <param name="bytes">Its bytes.</param>
    /// <param name="registers">
    ///  The registers' values by bit of <see cref="IsaDescription.EffectRegisters"/>, 0 for any the instruction does
    ///  not read; receives their values after it.
    /// </param>
    /// <param name="flags">The flags register's value; receives its value after.</param>
    /// <param name="reads">
    ///  The values the instruction's reads of memory get, other than its own bytes and the code after them, in the
    ///  order it reads.
    /// </param>
    /// <param name="readCount">Receives how many such reads it made.</param>
    /// <param name="next">Receives where execution goes next.</param>
    /// <param name="read">
    ///  The registers to set, by bit; the others keep what an earlier run left, which an instruction that does not
    ///  read them does not see.
    /// </param>
    /// <param name="written">The registers to receive the values of, by bit.</param>
    /// <param name="known">
    ///  The value of a byte of memory the caller knows, as a ROM's, or -1; reads of those do not take a value from
    ///  <paramref name="reads"/> and are not counted.
    /// </param>
    /// <returns>
    ///  Whether the instruction ran, with no more reads than <paramref name="reads"/> has and no port.
    /// </returns>
    internal bool TryRun(
        ushort pc,
        ReadOnlySpan<byte> bytes,
        Span<int> registers,
        ref int flags,
        ReadOnlySpan<byte> reads,
        out int readCount,
        out ushort next,
        uint read = uint.MaxValue,
        uint written = uint.MaxValue,
        Func<ushort, int>? known = null)
    {
        next = pc;
        readCount = 0;
        _bus.Start(pc, bytes, reads, known);
        try
        {
            for (int bit = 0; bit < _names.Length; bit++)
            {
                if ((read & (1u << bit)) != 0 && _names[bit] is { } name && name != _flagsRegister && name != _programCounter)
                {
                    _view.TrySetRegister(name, registers[bit]);
                }
            }

            foreach ((string name, int high, int low) in _pairs)
            {
                if ((read & ((1u << high) | (1u << low))) == 0) { continue; }
                _view.TrySetRegister(name, ((registers[high] & 0xFF) << 8) | (registers[low] & 0xFF));
            }

            if (_flagsRegister.Length != 0) { _view.TrySetRegister(_flagsRegister, flags); }
            _view.TrySetRegister(_programCounter, pc);
        }
        catch (Exception exception) when (exception is ArgumentOutOfRangeException or InvalidOperationException)
        {
            return false;
        }

        ProcessorExecutionResult result = _step();
        readCount = _bus.ReadCount;
        if (_bus.Failed || result.Status != ProcessorExecutionStatus.InstructionComplete) { return false; }

        for (int bit = 0; bit < _names.Length; bit++)
        {
            if ((written & (1u << bit)) != 0 && _names[bit] is { } name && _view.TryGetRegister(name, out int value))
            {
                registers[bit] = value;
            }
        }

        foreach ((string name, int high, int low) in _pairs)
        {
            if ((written & ((1u << high) | (1u << low))) == 0) { continue; }
            _view.TryGetRegister(name, out int value);
            registers[high] = value >> 8;
            registers[low] = value & 0xFF;
        }

        if (_flagsRegister.Length != 0 && _view.TryGetRegister(_flagsRegister, out int after)) { flags = after; }
        next = _view.ProgramCounter;
        return true;
    }

}
