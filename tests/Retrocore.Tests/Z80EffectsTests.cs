// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using System.Text.Json;
using Retrocore.Cpu.Z80;
using Retrocore.Isa;
using Observed = (uint Registers, byte Flags, uint ReadRegisters, byte ReadFlags);
using Outcome = (
    Retrocore.Cpu.Z80.Z80Registers Registers,
    System.Collections.Generic.List<(ushort Address, byte Value, Retrocore.Cpu.BusOperation Operation)> Accesses,
    Retrocore.Cpu.ProcessorExecutionStatus Status);

namespace Retrocore.Tests;

/// <summary>
///  The Z80 description's <c>effects</c> lines checked against execution, as
///  <see cref="InstructionEffectsTests"/> checks the 6502 family's.
/// </summary>
[TestClass]
public class Z80EffectsTests
{
    private const int CasesPerEncoding = 64;

    // The registers a test can set and read one at a time: those without parts, but F, whose bits are the flags,
    // and PC, which the flow lines describe.
    private static readonly (string Name, uint Mask, int Bits)[] s_leaves = Leaves();

    private static readonly uint s_r = Z80Isa.Description.RegisterMask("R");

    /// <summary>
    ///  Every Z80 encoding has effects, and pairs stand for their halves.
    /// </summary>
    [TestMethod]
    public void EveryZ80EncodingHasEffects()
    {
        InstructionSet set = Z80Isa.InstructionSet;
        IsaDescription description = set.Description;
        set.HasEffects.Should().BeTrue();
        for (int encoding = 0; encoding < set.Encodings.Count; encoding++)
        {
            set.Effects(encoding).IsKnown.Should().BeTrue(set.MnemonicName(set.GetEncoding(encoding).Mnemonic));
        }

        description.RegisterMask("HL").Should().Be(description.RegisterMask("H") | description.RegisterMask("L"));
        description.RegisterMask("IX").Should().Be(description.RegisterMask("IXH") | description.RegisterMask("IXL"));
        description.RegisterMask("IXH").Should().NotBe(0);
        description.Registers.Should().NotContain(register => register.Name == "IXH", "the debugger's frame lists the registers line");
    }

    /// <summary>
    ///  Runs every Z80 encoding from random states on the core, which the SingleStepTests certify, and checks
    ///  the data both ways, as the 6502 family's test does: what is not written keeps its value, constants take
    ///  theirs, SP moves by what is pushed and pulled; a register or flag not read changes nothing else, on the
    ///  bus, the ports or in the result; and each one read or written makes a difference in some case.
    /// </summary>
    [TestMethod]
    public void Z80EffectsMatchExecution()
    {
        InstructionSet set = Z80Isa.InstructionSet;
        Z80RecordingBus bus = new();
        Z80Processor<Z80RecordingBus> cpu = new(bus);
        Z80Snapshot baseline = cpu.CaptureState();
        Random random = new(80);
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
                Z80Registers start = Boundary(RandomState(random), index);
                for (int offset = 0; offset < size; offset++)
                {
                    ushort address = (ushort)(start.PC + offset);
                    template[address] = bytes[offset];
                    bus.Memory[address] = bytes[offset];
                }

                Outcome outcome = Run(cpu, bus, baseline, template, start);
                string name = $"{label} case {index}";
                CheckOutcome(effects, start, outcome.Registers, name, failures, ref observed);
                Perturb(cpu, bus, baseline, template, effects, start, outcome, random, name, failures, ref observed);
            }

            CheckObserved(effects, form, set.MnemonicName(value.Mnemonic), observed, label, failures);
        }

        string.Join(Environment.NewLine, failures).Should().BeEmpty();
    }

    /// <summary>
    ///  Checks the Z80's effects against every SingleStepTests vector: what is not written is unchanged,
    ///  constants take their value, and SP moves by what is pushed and pulled.
    /// </summary>
    [TestMethod]
    [TestCategory("Conformance")]
    public void Z80EffectsMatchSingleStepVectors()
    {
        string root = Path.Join(ExternalTestData.Cache, Z80OracleTests.SingleStepPin);
        if (!File.Exists(Path.Join(root, "manifest.json")))
        {
            Assert.Inconclusive("Z80 fixtures are missing. Run tools\\Fetch-Z80Tests.ps1 with PowerShell 7.");
        }

        InstructionSet set = Z80Isa.InstructionSet;
        List<string> failures = [];
        long total = 0;
        int files = 0;
        foreach (string path in Directory.EnumerateFiles(Path.Join(root, "v1"), "*.json").Order(StringComparer.Ordinal))
        {
            string name = "v1/" + Path.GetFileName(path);
            using JsonDocument document = JsonDocument.Parse(ExternalTestData.Read(Z80OracleTests.SingleStepPin, name));
            files++;
            Observed observed = default;
            foreach (JsonElement test in document.RootElement.EnumerateArray())
            {
                JsonElement initial = test.GetProperty("initial");
                Z80Registers start = Registers(initial);
                byte[] memory = new byte[8];
                foreach (JsonElement cell in initial.GetProperty("ram").EnumerateArray())
                {
                    int offset = (ushort)(cell[0].GetUInt16() - start.PC);
                    if (offset < memory.Length) { memory[offset] = cell[1].GetByte(); }
                }

                set.TryDecode(memory, out int encoding).Should().BeTrue(name);
                int before = failures.Count;
                Z80Registers end = Registers(test.GetProperty("final"));
                CheckOutcome(set.Effects(encoding), start, end, $"{name} {test.GetProperty("name").GetString()}", failures, ref observed);
                if (failures.Count > before) { break; }
                total++;
            }
        }

        Console.WriteLine($"Z80: {total:N0} vectors in {files} files checked.");
        string.Join(Environment.NewLine, failures).Should().BeEmpty();
        files.Should().Be(1604);
    }

    // What the data says, checked against one execution from a start state.
    private static void CheckOutcome(
        InstructionEffects effects,
        Z80Registers start,
        Z80Registers end,
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
            if (before == after || mask == s_r) { continue; }
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
        Z80Processor<Z80RecordingBus> cpu,
        Z80RecordingBus bus,
        Z80Snapshot baseline,
        byte[] template,
        InstructionEffects effects,
        Z80Registers start,
        Outcome outcome,
        Random random,
        string label,
        List<string> failures,
        ref Observed observed)
    {
        foreach ((string name, uint mask, int bits) in s_leaves)
        {
            int change = random.Next(1, 1 << bits);
            Z80Registers changed = Set(start, name, Get(start, name) ^ change);
            Outcome other = Run(cpu, bus, baseline, template, changed);
            Z80Registers expected = outcome.Registers;
            uint skip = mask == s_r ? mask : 0;
            if ((effects.RegistersMayWrite & mask) != 0) { skip |= mask; }
            else if ((effects.RegistersWritten & mask) == 0) { expected = Set(expected, name, Get(changed, name)); }
            if (mask == s_r) { skip |= mask; }
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
            Z80Registers changed = start;
            changed.F ^= flag;
            Outcome other = Run(cpu, bus, baseline, template, changed);
            Z80Registers expected = outcome.Registers;
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
    // can write a register with its own value, as LD B,B and AND A do; those are not expected to change it, but
    // AND A's and OR A's flags are.
    private static void CheckObserved(InstructionEffects effects, OperandForm form, string mnemonic, Observed observed, string label, List<string> failures)
    {
        string[] operands = form.Name.Split(',');
        bool idempotent = (mnemonic == "LD" && operands.Length == 2 && operands[0] == operands[1])
            || (mnemonic is "AND" or "OR" && form.Name == "A");

        foreach ((string name, uint mask, _) in s_leaves)
        {
            if (effects.ReadsAny(mask) && (observed.ReadRegisters & mask) == 0)
            {
                failures.Add($"{label}: {name} is read, but changing it never made a difference.");
            }

            if (mask != s_r && !idempotent && effects.ChangesAny(mask) && (observed.Registers & mask) == 0)
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

    private static bool Same(Z80Registers expected, Z80Registers actual, uint skipRegisters, byte skipFlags, Outcome first, Outcome second)
    {
        foreach ((string name, uint mask, _) in s_leaves)
        {
            if ((skipRegisters & mask) == 0 && Get(expected, name) != Get(actual, name)) { return false; }
        }

        if (((expected.F ^ actual.F) & ~skipFlags) != 0
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

    private static Outcome Run(Z80Processor<Z80RecordingBus> cpu, Z80RecordingBus bus, Z80Snapshot baseline, byte[] template, Z80Registers start)
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

    // Some cases sit where a rare change happens: BC at 1, where a block instruction ends and reads A for its
    // flags; B at 1 for the port blocks; low halves at $FF and 0, where a pair's increment or decrement carries
    // into its high half.
    private static Z80Registers Boundary(Z80Registers registers, int index)
    {
        switch (index % 8)
        {
            case 1:
                registers.B = 0;
                registers.C = 1;
                break;
            case 2:
                registers.B = 1;
                break;
            case 3 or 4:
                byte low = index % 8 == 3 ? (byte)0xFF : (byte)0;
                registers.C = registers.E = registers.L = low;
                registers.IX = (ushort)((registers.IX & 0xFF00) | low);
                registers.IY = (ushort)((registers.IY & 0xFF00) | low);
                registers.SP = (ushort)((registers.SP & 0xFF00) | low);
                break;
        }

        return registers;
    }

    private static Z80Registers RandomState(Random random) => new()
    {
        A = (byte)random.Next(256),
        F = (byte)random.Next(256),
        B = (byte)random.Next(256),
        C = (byte)random.Next(256),
        D = (byte)random.Next(256),
        E = (byte)random.Next(256),
        H = (byte)random.Next(256),
        L = (byte)random.Next(256),
        AlternateAF = (ushort)random.Next(0x10000),
        AlternateBC = (ushort)random.Next(0x10000),
        AlternateDE = (ushort)random.Next(0x10000),
        AlternateHL = (ushort)random.Next(0x10000),
        IX = (ushort)random.Next(0x10000),
        IY = (ushort)random.Next(0x10000),
        SP = (ushort)random.Next(0x10000),
        PC = (ushort)random.Next(0x10000),
        I = (byte)random.Next(256),
        R = (byte)random.Next(256),
        WZ = (ushort)random.Next(0x10000),
        Q = (byte)random.Next(256),
        Iff1 = random.Next(2) != 0,
        Iff2 = random.Next(2) != 0,
        InterruptMode = (byte)random.Next(3)
    };

    private static Z80Registers Registers(JsonElement state) => new()
    {
        A = state.GetProperty("a").GetByte(),
        F = state.GetProperty("f").GetByte(),
        B = state.GetProperty("b").GetByte(),
        C = state.GetProperty("c").GetByte(),
        D = state.GetProperty("d").GetByte(),
        E = state.GetProperty("e").GetByte(),
        H = state.GetProperty("h").GetByte(),
        L = state.GetProperty("l").GetByte(),
        AlternateAF = state.GetProperty("af_").GetUInt16(),
        AlternateBC = state.GetProperty("bc_").GetUInt16(),
        AlternateDE = state.GetProperty("de_").GetUInt16(),
        AlternateHL = state.GetProperty("hl_").GetUInt16(),
        IX = state.GetProperty("ix").GetUInt16(),
        IY = state.GetProperty("iy").GetUInt16(),
        SP = state.GetProperty("sp").GetUInt16(),
        PC = state.GetProperty("pc").GetUInt16(),
        I = state.GetProperty("i").GetByte(),
        R = state.GetProperty("r").GetByte(),
        WZ = state.GetProperty("wz").GetUInt16(),
        Q = state.GetProperty("q").GetByte(),
        Iff1 = state.GetProperty("iff1").GetInt32() != 0,
        Iff2 = state.GetProperty("iff2").GetInt32() != 0,
        InterruptMode = state.GetProperty("im").GetByte(),
        AfterEnable = state.GetProperty("ei").GetInt32() != 0,
        AfterLoadInterrupt = state.GetProperty("p").GetInt32() != 0
    };

    private static int Get(Z80Registers registers, string name) => name switch
    {
        "A" => registers.A,
        "B" => registers.B,
        "C" => registers.C,
        "D" => registers.D,
        "E" => registers.E,
        "H" => registers.H,
        "L" => registers.L,
        "I" => registers.I,
        "R" => registers.R,
        "SP" => registers.SP,
        "AF'" => registers.AlternateAF,
        "BC'" => registers.AlternateBC,
        "DE'" => registers.AlternateDE,
        "HL'" => registers.AlternateHL,
        "IXH" => registers.IX >> 8,
        "IXL" => registers.IX & 0xFF,
        "IYH" => registers.IY >> 8,
        "IYL" => registers.IY & 0xFF,
        _ => throw new ArgumentOutOfRangeException(nameof(name), name, "Not a Z80 register the test sets.")
    };

    private static Z80Registers Set(Z80Registers registers, string name, int value)
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
            case "I": registers.I = (byte)value; break;
            case "R": registers.R = (byte)value; break;
            case "SP": registers.SP = (ushort)value; break;
            case "AF'": registers.AlternateAF = (ushort)value; break;
            case "BC'": registers.AlternateBC = (ushort)value; break;
            case "DE'": registers.AlternateDE = (ushort)value; break;
            case "HL'": registers.AlternateHL = (ushort)value; break;
            case "IXH": registers.IX = (ushort)((registers.IX & 0xFF) | (value << 8)); break;
            case "IXL": registers.IX = (ushort)((registers.IX & 0xFF00) | value); break;
            case "IYH": registers.IY = (ushort)((registers.IY & 0xFF) | (value << 8)); break;
            case "IYL": registers.IY = (ushort)((registers.IY & 0xFF00) | value); break;
            default: throw new ArgumentOutOfRangeException(nameof(name), name, "Not a Z80 register the test sets.");
        }

        return registers;
    }

    private static IsaDescription Description => Z80Isa.Description;

    private static (string Name, uint Mask, int Bits)[] Leaves()
    {
        IsaDescription description = Z80Isa.Description;
        List<(string, uint, int)> leaves = [];
        for (int bit = 0; bit < description.EffectRegisters.Count; bit++)
        {
            string name = description.EffectRegisters[bit];
            if (name is "F" or "PC" || description.RegisterMask(name) != 1u << bit) { continue; }
            leaves.Add((name, 1u << bit, name is "SP" or "AF'" or "BC'" or "DE'" or "HL'" ? 16 : 8));
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
