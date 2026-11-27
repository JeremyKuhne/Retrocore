// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using Retrocore.Cpu.I8080;
using Retrocore.Isa;
using Observed = (uint Registers, byte Flags, uint ReadRegisters, byte ReadFlags);
using Outcome = (
    Retrocore.Cpu.I8080.I8080Registers Registers,
    System.Collections.Generic.List<(ushort Address, byte Value, Retrocore.Cpu.BusOperation Operation)> Accesses,
    Retrocore.Cpu.ProcessorExecutionStatus Status);

namespace Retrocore.Tests;

/// <summary>
///  The 8080 and 8085 description's <c>effects</c> lines checked against execution, as
///  <see cref="InstructionEffectsTests"/> checks the 6502 family's.
/// </summary>
[TestClass]
public class I8080EffectsTests
{
    private const int CasesPerEncoding = 64;

    // The registers a test can set and read one at a time: those without parts, but F, whose bits are the flags,
    // and PC, which the flow lines describe.
    private static readonly (string Name, uint Mask, int Bits)[] s_leaves = Leaves();

    // The flags both CPUs keep; the 8085 adds K and V, and the 8080's bit 1 always reads 1.
    private const byte Kept = I8080Flags.S | I8080Flags.Z | I8080Flags.AC | I8080Flags.P | I8080Flags.CY;

    /// <summary>
    ///  Every 8080 and 8085 encoding has effects; the 8085's arithmetic also writes K and V, and its INX K.
    /// </summary>
    [TestMethod]
    public void EveryI8080EncodingHasEffects()
    {
        IsaDescription description = I8080Isa.Description;
        foreach (I8080Variant variant in new[] { I8080Variant.I8080, I8080Variant.I8085 })
        {
            InstructionSet set = I8080Isa.Get(variant);
            set.HasEffects.Should().BeTrue();
            for (int encoding = 0; encoding < set.Encodings.Count; encoding++)
            {
                set.Effects(encoding).IsKnown.Should().BeTrue(set.MnemonicName(set.GetEncoding(encoding).Mnemonic));
            }
        }

        description.RegisterMask("PSW").Should().Be(description.RegisterMask("A") | description.RegisterMask("F"));
        byte kv = I8080Flags.K | I8080Flags.V;
        Effects(I8080Variant.I8080, 0x80).FlagsWritten.Should().Be(I8080Flags.S | I8080Flags.Z | I8080Flags.AC | I8080Flags.P | I8080Flags.CY);
        (Effects(I8080Variant.I8085, 0x80).FlagsWritten & kv).Should().Be(kv);
        Effects(I8080Variant.I8085, 0x03).FlagsWritten.Should().Be(I8080Flags.K, "the 8085's INX B writes K");
        Effects(I8080Variant.I8080, 0x03).RegistersWritten.Should().Be(description.RegisterMask("BC"));
        Effects(I8080Variant.I8080, 0x7E).RegistersRead.Should().Be(description.RegisterMask("HL"), "MOV A,M reads HL");
    }

    /// <summary>
    ///  Runs every 8080 and 8085 encoding from random states on the core and checks the data both ways, as the
    ///  6502 family's test does: what is not written keeps its value, constants take theirs, SP moves by what is
    ///  pushed and pulled; a register or flag not read changes nothing else, on the bus, the ports or in the
    ///  result; and each one read or written makes a difference in some case.
    /// </summary>
    /// <param name="variant">The CPU.</param>
    [TestMethod]
    [DataRow(I8080Variant.I8080)]
    [DataRow(I8080Variant.I8085)]
    public void I8080EffectsMatchExecution(I8080Variant variant)
    {
        InstructionSet set = I8080Isa.Get(variant);
        Z80RecordingBus bus = new();
        I8080Processor<Z80RecordingBus> cpu = new(bus, variant);
        I8080Snapshot baseline = cpu.CaptureState();
        Random random = new(8080 + (int)variant);
        byte flagBits = variant == I8080Variant.I8085 ? (byte)(Kept | I8080Flags.K | I8080Flags.V) : Kept;
        byte[] template = new byte[0x10000];
        byte[] bytes = new byte[8];
        List<string> failures = [];
        for (int encoding = 0; encoding < set.Encodings.Count; encoding++)
        {
            InstructionEffects effects = set.Effects(encoding);
            IsaEncoding value = set.GetEncoding(encoding);
            OperandForm form = set.GetForm(value.Form);
            string label = $"{set.MnemonicName(value.Mnemonic)} {form.Name} ({Hex(value)})";
            random.NextBytes(template);
            template.CopyTo(bus.Memory, 0);
            Observed observed = default;
            int before = failures.Count;
            for (int index = 0; index < CasesPerEncoding && failures.Count == before; index++)
            {
                int size = Encode(set, encoding, random, bytes);
                set.TryDecode(bytes.AsSpan(0, size), out int decoded).Should().BeTrue(label);
                decoded.Should().Be(encoding, label);
                I8080Registers start = Boundary(RandomState(random), index);
                start.F = (byte)((start.F & flagBits) | (variant == I8080Variant.I8080 ? I8080Flags.V : 0));
                for (int offset = 0; offset < size; offset++)
                {
                    ushort address = (ushort)(start.PC + offset);
                    template[address] = bytes[offset];
                    bus.Memory[address] = bytes[offset];
                }

                Outcome outcome = Run(cpu, bus, baseline, template, start);
                string name = $"{label} case {index}";
                CheckOutcome(effects, start, outcome.Registers, name, failures, ref observed);
                Perturb(cpu, bus, baseline, template, effects, start, outcome, random, flagBits, name, failures, ref observed);
            }

            CheckObserved(effects, form, set.MnemonicName(value.Mnemonic), observed, label, failures);
        }

        string.Join(Environment.NewLine, failures).Should().BeEmpty();
    }

    // What the data says, checked against one execution from a start state.
    private static void CheckOutcome(
        InstructionEffects effects,
        I8080Registers start,
        I8080Registers end,
        string label,
        List<string> failures,
        ref Observed observed)
    {
        IsaDescription description = Description;
        for (int index = 0; index < effects.CopyCount; index++)
        {
            // A copy leaves its destination with the source's value from before the instruction.
            effects.GetCopy(index, out int destination, out int source);
            string to = description.EffectRegisters[destination];
            string from = description.EffectRegisters[source];
            if (to != "R" && from != "R" && Get(end, to) != Get(start, from))
            {
                failures.Add($"{label}: {to} is ${Get(end, to):X2}, not {from}'s ${Get(start, from):X2}.");
            }
        }

        foreach ((string name, uint mask, _) in s_leaves)
        {
            int before = Get(start, name);
            int after = Get(end, name);
            if (before == after) { continue; }
            observed.Registers |= mask;
            if (!effects.ChangesAny(mask))
            {
                failures.Add($"{label}: {name} changed from ${before:X2} to ${after:X2} but is not written.");
            }
        }

        byte changed = (byte)(start.F ^ end.F);
        observed.Flags |= changed;
        byte unwritten = (byte)~(effects.FlagsWritten | effects.FlagsMayWrite);
        if ((changed & unwritten) != 0)
        {
            failures.Add($"{label}: F changed from ${start.F:X2} to ${end.F:X2}, outside the written ${effects.FlagsWritten:X2}.");
        }

        if ((end.F & effects.FlagsSet) != effects.FlagsSet || (end.F & effects.FlagsCleared) != 0)
        {
            failures.Add($"{label}: F ${end.F:X2} misses the set ${effects.FlagsSet:X2} or cleared ${effects.FlagsCleared:X2}.");
        }

        ushort always = (ushort)(start.SP - effects.Pushed + effects.Pulled);
        ushort taken = (ushort)(always - effects.MayPush + effects.MayPull);
        bool moves = (effects.Pushed | effects.Pulled | effects.MayPush | effects.MayPull) != 0;
        if (moves && end.SP != always && end.SP != taken)
        {
            failures.Add($"{label}: SP went from ${start.SP:X4} to ${end.SP:X4}; expected ${always:X4} or ${taken:X4}.");
        }
    }

    // Changes each register and flag in turn: one not read must change nothing but itself.
    private static void Perturb(
        I8080Processor<Z80RecordingBus> cpu,
        Z80RecordingBus bus,
        I8080Snapshot baseline,
        byte[] template,
        InstructionEffects effects,
        I8080Registers start,
        Outcome outcome,
        Random random,
        byte flagBits,
        string label,
        List<string> failures,
        ref Observed observed)
    {
        foreach ((string name, uint mask, int bits) in s_leaves)
        {
            int change = random.Next(1, 1 << bits);
            I8080Registers changed = Set(start, name, Get(start, name) ^ change);
            Outcome other = Run(cpu, bus, baseline, template, changed);
            I8080Registers expected = outcome.Registers;
            uint skip = 0;
            if ((effects.RegistersMayWrite & mask) != 0) { skip |= mask; }
            else if ((effects.RegistersWritten & mask) == 0) { expected = Set(expected, name, Get(changed, name)); }
            bool differs = !Same(expected, other.Registers, skip, 0, outcome, other);
            if (differs) { observed.ReadRegisters |= mask; }
            if (differs && !effects.ReadsAny(mask))
            {
                failures.Add($"{label}: changing {name}, which is not read, changed the result.");
            }
        }

        for (int bit = 0; bit < 8; bit++)
        {
            byte flag = (byte)(1 << bit);
            if ((flagBits & flag) == 0) { continue; }
            I8080Registers changed = start;
            changed.F ^= flag;
            Outcome other = Run(cpu, bus, baseline, template, changed);
            I8080Registers expected = outcome.Registers;
            byte skip = (byte)(effects.FlagsMayWrite & flag);
            if (((effects.FlagsWritten | effects.FlagsMayWrite) & flag) == 0) { expected.F ^= flag; }
            bool differs = !Same(expected, other.Registers, 0, skip, outcome, other);
            if (differs) { observed.ReadFlags |= flag; }
            if (differs && (effects.FlagsRead & flag) == 0)
            {
                failures.Add($"{label}: changing flag bit {bit}, which is not read, changed the result.");
            }
        }
    }

    // Each register and flag the data says is read or written made a difference in some case. An instruction
    // can write a register with its own value, as MOV B,B and ANA A do; those are not expected to change it, but
    // ANA A's and ORA A's flags are.
    private static void CheckObserved(InstructionEffects effects, OperandForm form, string mnemonic, Observed observed, string label, List<string> failures)
    {
        string[] operands = form.Name.Split(',');
        bool idempotent = (mnemonic == "MOV" && operands.Length == 2 && operands[0] == operands[1])
            || (mnemonic is "ANA" or "ORA" && form.Name == "A");

        foreach ((string name, uint mask, _) in s_leaves)
        {
            if (effects.ReadsAny(mask) && (observed.ReadRegisters & mask) == 0)
            {
                failures.Add($"{label}: {name} is read, but changing it never made a difference.");
            }

            if (!idempotent && effects.ChangesAny(mask) && (observed.Registers & mask) == 0)
            {
                failures.Add($"{label}: {name} is written, but never changed.");
            }
        }

        byte flagsRead = (byte)(effects.FlagsRead & ~observed.ReadFlags);
        byte flagsWritten = (byte)((effects.FlagsWritten | effects.FlagsMayWrite) & ~observed.Flags);
        if (flagsRead != 0)
        {
            failures.Add($"{label}: flags ${flagsRead:X2} are read, but changing them never made a difference.");
        }

        if (flagsWritten != 0)
        {
            failures.Add($"{label}: flags ${flagsWritten:X2} are written, but never changed.");
        }
    }

    private static bool Same(I8080Registers expected, I8080Registers actual, uint skipRegisters, byte skipFlags, Outcome first, Outcome second)
    {
        foreach ((string name, uint mask, _) in s_leaves)
        {
            if ((skipRegisters & mask) == 0 && Get(expected, name) != Get(actual, name)) { return false; }
        }

        // The 8085's interrupt masks and serial output, which SIM sets, are compared as results too.
        if (((expected.F ^ actual.F) & ~skipFlags) != 0
            || expected.PC != actual.PC
            || expected.InterruptMask != actual.InterruptMask
            || expected.SerialOutput != actual.SerialOutput
            || first.Status != second.Status
            || first.Accesses.Count != second.Accesses.Count)
        {
            return false;
        }

        for (int index = 0; index < first.Accesses.Count; index++)
        {
            if (first.Accesses[index] != second.Accesses[index]) { return false; }
        }

        return true;
    }

    private static Outcome Run(I8080Processor<Z80RecordingBus> cpu, Z80RecordingBus bus, I8080Snapshot baseline, byte[] template, I8080Registers start)
    {
        cpu.RestoreState(baseline);
        bus.Accesses.Clear();
        cpu.Registers = start;
        ProcessorExecutionResult result = cpu.StepInstruction();
        List<(ushort Address, byte Value, BusOperation Operation)> accesses = [.. bus.Accesses];
        foreach ((ushort address, _, BusOperation operation) in accesses)
        {
            if (operation == BusOperation.Write) { bus.Memory[address] = template[address]; }
        }

        return (cpu.Registers, accesses, result.Status);
    }

    // The encoding's bytes, with random operands, a displacement before the last opcode byte where it goes there,
    // and a random bit or restart in bits 3-5 where the form holds one in the opcode.
    private static int Encode(InstructionSet set, int encoding, Random random, byte[] bytes)
    {
        IsaEncoding value = set.GetEncoding(encoding);
        int size = set.Size(encoding);
        int length = value.OpcodeLength;
        int operands = size - length;
        int split = value.SplitAt == 0 ? length : value.SplitAt;
        random.NextBytes(bytes);
        for (int index = 0; index < length; index++)
        {
            int at = index < split ? index : index + operands;
            bytes[at] = (byte)(value.Opcode >> (index * 8));
        }

        if (set.GetForm(value.Form).OpcodeField >= 0)
        {
            int last = split == length ? length - 1 : length - 1 + operands;
            bytes[last] = (byte)((bytes[last] & ~0x38) | (random.Next(8) << 3));
        }

        return size;
    }

    // Some cases sit where a rare change happens: low halves at $FF and 0, where a pair's increment or decrement
    // carries into its high half, and HL and DE at their ends for the 8085's K and DSUB.
    private static I8080Registers Boundary(I8080Registers registers, int index)
    {
        switch (index % 8)
        {
            case 1 or 2:
                byte low = index % 8 == 1 ? (byte)0xFF : (byte)0;
                registers.C = registers.E = registers.L = low;
                registers.SP = (ushort)((registers.SP & 0xFF00) | low);
                break;
            case 3 or 4:
                ushort end = index % 8 == 3 ? (ushort)0xFFFF : (ushort)0;
                registers.BC = registers.DE = registers.HL = end;
                registers.SP = end;
                break;
        }

        return registers;
    }

    private static I8080Registers RandomState(Random random) => new()
    {
        A = (byte)random.Next(256),
        F = (byte)random.Next(256),
        B = (byte)random.Next(256),
        C = (byte)random.Next(256),
        D = (byte)random.Next(256),
        E = (byte)random.Next(256),
        H = (byte)random.Next(256),
        L = (byte)random.Next(256),
        SP = (ushort)random.Next(0x10000),
        PC = (ushort)random.Next(0x10000)
    };

    private static int Get(I8080Registers registers, string name) => name switch
    {
        "A" => registers.A,
        "B" => registers.B,
        "C" => registers.C,
        "D" => registers.D,
        "E" => registers.E,
        "H" => registers.H,
        "L" => registers.L,
        "SP" => registers.SP,
        _ => throw new ArgumentOutOfRangeException(nameof(name), name, "Not an 8080 register the test sets.")
    };

    private static I8080Registers Set(I8080Registers registers, string name, int value)
    {
        switch (name)
        {
            case "A": registers.A = (byte)value; break;
            case "B": registers.B = (byte)value; break;
            case "C": registers.C = (byte)value; break;
            case "D": registers.D = (byte)value; break;
            case "E": registers.E = (byte)value; break;
            case "H": registers.H = (byte)value; break;
            case "L": registers.L = (byte)value; break;
            case "SP": registers.SP = (ushort)value; break;
            default: throw new ArgumentOutOfRangeException(nameof(name), name, "Not an 8080 register the test sets.");
        }

        return registers;
    }

    private static InstructionEffects Effects(I8080Variant variant, byte opcode)
    {
        InstructionSet set = I8080Isa.Get(variant);
        set.TryDecode([opcode, 0, 0], out int encoding).Should().BeTrue();
        return set.Effects(encoding);
    }

    private static IsaDescription Description => I8080Isa.Description;

    private static (string Name, uint Mask, int Bits)[] Leaves()
    {
        IsaDescription description = I8080Isa.Description;
        List<(string, uint, int)> leaves = [];
        for (int bit = 0; bit < description.EffectRegisters.Count; bit++)
        {
            string name = description.EffectRegisters[bit];
            if (name is "F" or "PC" || description.RegisterMask(name) != 1u << bit) { continue; }
            leaves.Add((name, 1u << bit, name is "SP" ? 16 : 8));
        }

        return [.. leaves];
    }

    private static string Hex(IsaEncoding encoding)
    {
        string text = "";
        for (int index = 0; index < encoding.OpcodeLength; index++)
        {
            text += ((encoding.Opcode >> (index * 8)) & 0xFF).ToString("X2", System.Globalization.CultureInfo.InvariantCulture) + " ";
        }

        return text.TrimEnd();
    }
}
