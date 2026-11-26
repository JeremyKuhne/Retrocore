// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using Retrocore.Cpu.M6809;
using Retrocore.Isa;
using Observed = (uint Registers, byte Flags, uint ReadRegisters, byte ReadFlags);
using Outcome = (
    Retrocore.Cpu.M6809.M6809Registers Registers,
    System.Collections.Generic.List<(ushort Address, byte Value, Retrocore.Cpu.BusOperation Operation)> Accesses,
    Retrocore.Cpu.ProcessorExecutionStatus Status);

namespace Retrocore.Tests;

/// <summary>
///  The MC6809 description's <c>effects</c> lines, with the registers its postbytes name, checked against
///  execution, as <see cref="InstructionEffectsTests"/> checks the 6502 family's.
/// </summary>
[TestClass]
public class M6809EffectsTests
{
    // More cases than the 6502's and the Z80's: a 16-bit compare's low byte matters about once in 128, and a
    // postbyte's registers vary from case to case.
    private const int CasesPerEncoding = 1024;

    // The registers a test can set and read one at a time: those without parts, but CC, whose bits are the flags,
    // and PC, which the flow lines describe.
    private static readonly (string Name, uint Mask, int Bits)[] s_leaves = Leaves();

    /// <summary>
    ///  Every MC6809 encoding has effects; those with a register list, pair or indexed postbyte depend on it, and
    ///  the codec fills them in.
    /// </summary>
    [TestMethod]
    public void EveryM6809EncodingHasEffects()
    {
        InstructionSet set = M6809Isa.InstructionSet;
        IsaDescription description = set.Description;
        set.HasEffects.Should().BeTrue();
        for (int encoding = 0; encoding < set.Encodings.Count; encoding++)
        {
            set.Effects(encoding).IsKnown.Should().BeTrue(set.MnemonicName(set.GetEncoding(encoding).Mnemonic));
        }

        uint a = description.RegisterMask("A"), b = description.RegisterMask("B"), x = description.RegisterMask("X");
        uint s = description.RegisterMask("S"), u = description.RegisterMask("U"), pc = description.RegisterMask("PC");
        description.RegisterMask("D").Should().Be(a | b);

        // PULS A,X,PC: pulls five bytes into A, X and PC through S.
        InstructionEffects puls = Effects(set, [0x35, 0x92]);
        puls.DependsOnPostbyte.Should().BeTrue();
        puls.RegistersWritten.Should().Be(a | x | pc | s);
        puls.Pulled.Should().Be(5);
        Effects(set, [0x35]).Pulled.Should().Be(0, "without the postbyte the list is unknown");

        // PSHU CC,S: reads every flag and S, through U.
        InstructionEffects pshu = Effects(set, [0x36, 0x41]);
        pshu.FlagsRead.Should().Be(0xFF);
        pshu.RegistersRead.Should().Be(description.RegisterMask("CC") | s | u);
        (1u << pshu.StackRegister).Should().Be(u);
        pshu.Pushed.Should().Be(3);

        // TFR A,CC writes every flag; EXG D,X reads and writes both.
        Effects(set, [0x1F, 0x8A]).FlagsWritten.Should().Be(0xFF);
        Effects(set, [0x1E, 0x01]).RegistersWritten.Should().Be(a | b | x);

        // LDA ,X+ reads and writes X; LDA B,Y reads B and Y; LDA [$1234] reads no register.
        InstructionEffects postIncrement = Effects(set, [0xA6, 0x80]);
        postIncrement.RegistersRead.Should().Be(x);
        postIncrement.RegistersWritten.Should().Be(a | x);
        Effects(set, [0xA6, 0xA5]).RegistersRead.Should().Be(b | description.RegisterMask("Y"));
        Effects(set, [0xA6, 0x9F, 0x12, 0x34]).RegistersRead.Should().Be(0);

        // LDA <$12 reads DP.
        Effects(set, [0x96, 0x12]).RegistersRead.Should().Be(description.RegisterMask("DP"));
    }

    /// <summary>
    ///  Runs every MC6809 encoding, with random valid postbytes, from random states on the core, which the
    ///  functional, cycle and interrupt programs and the undocumented-behaviour tests check, and checks the data
    ///  both ways, as the 6502 family's test does: what is not written keeps its value, constants take theirs,
    ///  the stack moves by what is pushed and pulled; a register or flag not read changes nothing else, on the bus
    ///  or in the result; and each one read or written makes a difference in some case.
    /// </summary>
    [TestMethod]
    public void M6809EffectsMatchExecution()
    {
        InstructionSet set = M6809Isa.InstructionSet;
        M6809RecordingBus bus = new();
        M6809Processor<M6809RecordingBus> cpu = new(bus);
        M6809Snapshot baseline = cpu.CaptureState();
        Random random = new(6809);
        byte[] template = new byte[0x10000];
        byte[] bytes = new byte[8];
        List<string> failures = [];
        for (int encoding = 0; encoding < set.Encodings.Count; encoding++)
        {
            IsaEncoding value = set.GetEncoding(encoding);
            OperandForm form = set.GetForm(value.Form);
            string label = $"{set.MnemonicName(value.Mnemonic)} {form.Name} ({Hex(value)})";
            random.NextBytes(template);
            template.CopyTo(bus.Memory, 0);
            Observed observed = default;
            InstructionEffects union = default;
            int before = failures.Count;
            for (int index = 0; index < CasesPerEncoding && failures.Count == before; index++)
            {
                int size = Encode(set, encoding, random, bytes);
                InstructionEffects effects = set.Effects(encoding, bytes[value.OpcodeLength]);
                union = Union(union, effects);
                M6809Registers start = RandomState(random);

                // Every eighth case, A is the immediate operand's high byte, where a 16-bit compare's low byte counts.
                if (index % 8 == 1 && size > value.OpcodeLength) { start.A = bytes[value.OpcodeLength]; }
                for (int offset = 0; offset < size; offset++)
                {
                    ushort address = (ushort)(start.PC + offset);
                    template[address] = bytes[offset];
                    bus.Memory[address] = bytes[offset];
                }

                Outcome outcome = Run(cpu, bus, baseline, template, start);
                string name = $"{label} {Convert.ToHexString(bytes, 0, size)} case {index}";
                byte postbyte = bytes[value.OpcodeLength];
                bool indexed = form.HasPostbyte && form.Field(0) == OperandFieldKind.IndexedPostbyte;
                bool autoStack = indexed && (postbyte & 0xE0) == 0xE0 && (postbyte & 0x0F) <= 3;
                CheckOutcome(effects, start, outcome, autoStack, name, failures, ref observed);
                Perturb(cpu, bus, baseline, template, effects, start, outcome, random, name, failures, ref observed);
            }

            CheckObserved(union, observed, label, failures);
        }

        string.Join(Environment.NewLine, failures).Should().BeEmpty();
    }

    // What the data says, checked against one execution from a start state.
    private static void CheckOutcome(
        InstructionEffects effects,
        M6809Registers start,
        Outcome outcome,
        bool autoStack,
        string label,
        List<string> failures,
        ref Observed observed)
    {
        M6809Registers end = outcome.Registers;
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

        byte changed = (byte)(start.CC ^ end.CC);
        observed.Flags |= changed;
        byte unwritten = (byte)~(effects.FlagsWritten | effects.FlagsMayWrite);
        if ((changed & unwritten) != 0)
        {
            failures.Add($"{label}: CC changed from ${start.CC:X2} to ${end.CC:X2}, outside the written ${effects.FlagsWritten:X2}.");
        }

        if ((end.CC & effects.FlagsSet) != effects.FlagsSet || (end.CC & effects.FlagsCleared) != 0)
        {
            failures.Add($"{label}: CC ${end.CC:X2} misses the set ${effects.FlagsSet:X2} or cleared ${effects.FlagsCleared:X2}.");
        }

        // An indexed operand that auto-increments or auto-decrements the stack pointer, as JSR [,S++], moves it too.
        bool moves = (effects.Pushed | effects.Pulled | effects.MayPush | effects.MayPull) != 0;
        if (moves && outcome.Status == ProcessorExecutionStatus.InstructionComplete && !autoStack)
        {
            string stack = M6809Isa.Description.EffectRegisters[effects.StackRegister];
            int from = Get(start, stack);
            int to = Get(end, stack);
            ushort always = (ushort)(from - effects.Pushed + effects.Pulled);
            ushort taken = (ushort)(always - effects.MayPush + effects.MayPull);
            if (to != always && to != taken)
            {
                failures.Add($"{label}: {stack} went from ${from:X4} to ${to:X4}; expected ${always:X4} or ${taken:X4}.");
            }
        }
    }

    // Changes each register and flag in turn: one not read must change nothing but itself.
    private static void Perturb(
        M6809Processor<M6809RecordingBus> cpu,
        M6809RecordingBus bus,
        M6809Snapshot baseline,
        byte[] template,
        InstructionEffects effects,
        M6809Registers start,
        Outcome outcome,
        Random random,
        string label,
        List<string> failures,
        ref Observed observed)
    {
        foreach ((string name, uint mask, int bits) in s_leaves)
        {
            int change = random.Next(1, 1 << bits);
            M6809Registers changed = Set(start, name, Get(start, name) ^ change);
            Outcome other = Run(cpu, bus, baseline, template, changed);
            M6809Registers expected = outcome.Registers;
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
            M6809Registers changed = start;
            changed.CC ^= flag;
            Outcome other = Run(cpu, bus, baseline, template, changed);
            M6809Registers expected = outcome.Registers;
            byte skip = (byte)(effects.FlagsMayWrite & flag);
            if (((effects.FlagsWritten | effects.FlagsMayWrite) & flag) == 0) { expected.CC ^= flag; }
            bool differs = !Same(expected, other.Registers, 0, skip, outcome, other);
            if (differs) { observed.ReadFlags |= flag; }
            if (differs && (effects.FlagsRead & flag) == 0)
            {
                failures.Add($"{label}: changing flag bit {bit}, which is not read, changed the result.");
            }
        }
    }

    // Each register and flag the data says, in some case, is read or written made a difference in some case.
    private static void CheckObserved(InstructionEffects effects, Observed observed, string label, List<string> failures)
    {
        foreach ((string name, uint mask, _) in s_leaves)
        {
            if (effects.ReadsAny(mask) && (observed.ReadRegisters & mask) == 0)
            {
                failures.Add($"{label}: {name} is read, but changing it never made a difference.");
            }

            if (effects.ChangesAny(mask) && (observed.Registers & mask) == 0)
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

    // What the cases of one encoding claimed between them, as their postbytes vary.
    private static InstructionEffects Union(InstructionEffects first, InstructionEffects second) => second with
    {
        RegistersRead = first.RegistersRead | second.RegistersRead,
        RegistersWritten = first.RegistersWritten | second.RegistersWritten,
        RegistersMayWrite = first.RegistersMayWrite | second.RegistersMayWrite,
        FlagsRead = (byte)(first.FlagsRead | second.FlagsRead),
        FlagsWritten = (byte)(first.FlagsWritten | second.FlagsWritten),
        FlagsMayWrite = (byte)(first.FlagsMayWrite | second.FlagsMayWrite)
    };

    private static bool Same(M6809Registers expected, M6809Registers actual, uint skipRegisters, byte skipFlags, Outcome first, Outcome second)
    {
        foreach ((string name, uint mask, _) in s_leaves)
        {
            if ((skipRegisters & mask) == 0 && Get(expected, name) != Get(actual, name)) { return false; }
        }

        if (((expected.CC ^ actual.CC) & ~skipFlags) != 0
            || expected.PC != actual.PC
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

    private static Outcome Run(
        M6809Processor<M6809RecordingBus> cpu,
        M6809RecordingBus bus,
        M6809Snapshot baseline,
        byte[] template,
        M6809Registers start)
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

    // The encoding's bytes with random operands, drawn again until a postbyte field is one the set decodes.
    private static int Encode(InstructionSet set, int encoding, Random random, byte[] bytes)
    {
        IsaEncoding value = set.GetEncoding(encoding);
        while (true)
        {
            random.NextBytes(bytes);
            for (int index = 0; index < value.OpcodeLength; index++)
            {
                bytes[index] = (byte)(value.Opcode >> (index * 8));
            }

            if (set.TryDecode(bytes, out int decoded, out int size) && decoded == encoding) { return size; }
        }
    }

    private static M6809Registers RandomState(Random random) => new()
    {
        A = (byte)random.Next(256),
        B = (byte)random.Next(256),
        X = (ushort)random.Next(0x10000),
        Y = (ushort)random.Next(0x10000),
        U = (ushort)random.Next(0x10000),
        S = (ushort)random.Next(0x10000),
        PC = (ushort)random.Next(0x10000),
        DP = (byte)random.Next(256),
        CC = (byte)random.Next(256)
    };

    private static int Get(M6809Registers registers, string name) => name switch
    {
        "A" => registers.A,
        "B" => registers.B,
        "X" => registers.X,
        "Y" => registers.Y,
        "U" => registers.U,
        "S" => registers.S,
        "DP" => registers.DP,
        _ => throw new ArgumentOutOfRangeException(nameof(name), name, "Not an MC6809 register the test sets.")
    };

    private static M6809Registers Set(M6809Registers registers, string name, int value)
    {
        switch (name)
        {
            case "A": registers.A = (byte)value; break;
            case "B": registers.B = (byte)value; break;
            case "X": registers.X = (ushort)value; break;
            case "Y": registers.Y = (ushort)value; break;
            case "U": registers.U = (ushort)value; break;
            case "S": registers.S = (ushort)value; break;
            case "DP": registers.DP = (byte)value; break;
            default: throw new ArgumentOutOfRangeException(nameof(name), name, "Not an MC6809 register the test sets.");
        }

        return registers;
    }

    private static (string Name, uint Mask, int Bits)[] Leaves()
    {
        IsaDescription description = M6809Isa.Description;
        List<(string, uint, int)> leaves = [];
        for (int bit = 0; bit < description.EffectRegisters.Count; bit++)
        {
            string name = description.EffectRegisters[bit];
            if (name is "CC" or "PC" || description.RegisterMask(name) != 1u << bit) { continue; }
            leaves.Add((name, 1u << bit, name is "X" or "Y" or "U" or "S" ? 16 : 8));
        }

        return [.. leaves];
    }

    private static InstructionEffects Effects(InstructionSet set, byte[] bytes)
    {
        set.TryDecode([bytes[0], 0, 0, 0], out int encoding).Should().BeTrue();
        return bytes.Length > 1 ? set.Effects(encoding, bytes[1]) : set.Effects(encoding);
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
