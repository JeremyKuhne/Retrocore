// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using System.Text.Json;
using Retrocore.Isa;
using Observed = (uint Registers, byte Flags, uint ReadRegisters, byte ReadFlags);
using Outcome = (
    Retrocore.Cpu.M6502.ProcessorRegisters Registers,
    System.Collections.Generic.List<(ushort Address, byte Value, Retrocore.Cpu.BusOperation Operation)> Accesses,
    Retrocore.Cpu.ProcessorExecutionStatus Status);

namespace Retrocore.Tests;

/// <summary>
///  The <c>effects</c> lines of the instruction-set descriptions: the format, the 6502 family's data, and that
///  data checked against execution.
/// </summary>
[TestClass]
public class InstructionEffectsTests
{
    private const string Tiny = """
        [isa]
        registers A:8 X:8 S:8 P:8 PC:16
        flags P N=7 V=6 C=0
        flag N negative "Negative."
        flag V overflow "Overflow."
        flag C carry "Carry."
        stack S
        effects ADD                 reads A carry       writes A negative carry
        effects ADD:Imm             reads A             writes A carry=0
        effects :Idx                reads X
        effects PSH                 reads P S           writes S            push 1
        effects PUL                 reads S             writes P S          pull 1
        effects TST                 reads A             writes negative=bit7 overflow=bit6
        effects NOP none
        effects in Big NOP                              writes carry=1
        effects TAX                 reads A             writes X            copies X=A
        effects BRC                 reads carry negative overflow           taken carry=0|negative!=overflow
        [forms]
        Imp ""
        Imm "#{}"   fields=byte
        Idx "{},X"  fields=byte memory
        Abs "{}"    fields=byte memory
        [Small]
        00 NOP Imp
        01 ADD Imm
        02 ADD Idx
        03 ADD Abs
        04 PSH Imp
        05 PUL Imp
        06 TST Abs
        08 TAX Imp
        09 BRC Imm
        [Big : Small]
        07 NOP Abs
        """;

    private const int A = 0;
    private const int X = 1;
    private const int S = 2;
    private const int P = 3;

    private const int CasesPerOpcode = 64;

    private static readonly int RegisterA = Index("A");
    private static readonly int RegisterX = Index("X");
    private static readonly int RegisterY = Index("Y");
    private static readonly int RegisterS = Index("S");
    private static readonly byte AllFlags = (byte)M6502Isa.Description.Flags.Sum(flag => 1 << flag.Bit);

    /// <summary>
    ///  Registers and flags parse to bits; a form's line adds to the instruction's, an Instruction:Form line
    ///  replaces it, and naming the flags register reads or writes every flag.
    /// </summary>
    [TestMethod]
    public void EffectsParseToBits()
    {
        InstructionSet set = IsaParser.Parse(Tiny).InstructionSets["Small"];
        set.HasEffects.Should().BeTrue();

        InstructionEffects absolute = Effects(set, 0x03);
        absolute.IsKnown.Should().BeTrue();
        absolute.RegistersRead.Should().Be(1u << A);
        absolute.RegistersWritten.Should().Be(1u << A);
        absolute.FlagsRead.Should().Be(0x01);
        absolute.FlagsWritten.Should().Be(0x81);
        absolute.FlagsSet.Should().Be(0);
        absolute.FlagsCleared.Should().Be(0);

        InstructionEffects indexed = Effects(set, 0x02);
        indexed.RegistersRead.Should().Be((1u << A) | (1u << X), "the form's line adds X");
        indexed.FlagsRead.Should().Be(0x01);

        InstructionEffects immediate = Effects(set, 0x01);
        immediate.FlagsRead.Should().Be(0, "ADD:Imm replaces ADD's line");
        immediate.FlagsWritten.Should().Be(0x01);
        immediate.FlagsCleared.Should().Be(0x01);

        InstructionEffects push = Effects(set, 0x04);
        push.Reads(P).Should().BeTrue();
        push.FlagsRead.Should().Be(0xC1, "reading P reads every flag");
        push.Pushed.Should().Be(1);
        push.Writes(S).Should().BeTrue();

        InstructionEffects pull = Effects(set, 0x05);
        pull.FlagsWritten.Should().Be(0xC1);
        pull.Pulled.Should().Be(1);

        InstructionEffects test = Effects(set, 0x06);
        test.FlagsFromOperand.Should().Be(0xC0);
        test.OperandBit(7).Should().Be(7);
        test.OperandBit(6).Should().Be(6);
        test.OperandBit(0).Should().Be(-1);

        InstructionEffects none = Effects(set, 0x00);
        none.IsKnown.Should().BeTrue();
        none.Should().Be(new InstructionEffects { IsKnown = true });
    }

    /// <summary>
    ///  Parts make a pair stand for its halves, operand slots take the form's registers, a bracketed operand
    ///  reads its address register, may-write and may-push mark one path's changes, and a push can name its
    ///  stack.
    /// </summary>
    [TestMethod]
    public void PartsSlotsAndConditionalEffects()
    {
        const string Pairs = """
            [isa]
            literal-forms
            registers A:8 F:8 H:8 L:8 AF:16 HL:16 IX:16 SP:16 U:16 PC:16
            flags F Z=6 C=0
            flag Z zero "Zero."
            flag C carry "Carry."
            parts AF=A,F HL=H,L IX=IXH,IXL
            stack SP
            effects LD                  reads $2            writes $1
            effects ADD                 reads $1 $2         writes $1 zero carry
            effects CALL:Z,nn           reads zero SP       may-write SP        may-push 2
            effects PSHU                reads A U           writes U            push U 1
            effects POP                 reads SP            writes $1 SP        pull 2
            [forms]
            Implied ""
            [Cpu]
            00 LD A,H
            01 LD [HL],A
            02 LD IXH,A
            03 ADD HL,IX
            04 CALL Z,nn
            05 PSHU Implied
            06 POP AF
            """;

        IsaDescription description = IsaParser.Parse(Pairs);
        InstructionSet set = description.InstructionSets["Cpu"];
        uint a = description.RegisterMask("A"), h = description.RegisterMask("H"), l = description.RegisterMask("L");
        uint ixh = description.RegisterMask("IXH"), ixl = description.RegisterMask("IXL"), sp = description.RegisterMask("SP");
        description.RegisterMask("HL").Should().Be(h | l);
        description.RegisterMask("IX").Should().Be(ixh | ixl);
        description.EffectRegisters.Should().HaveCount(12, "IXH and IXL follow the registers line");

        Effects(set, 0x00).RegistersRead.Should().Be(h);
        Effects(set, 0x00).RegistersWritten.Should().Be(a);
        Effects(set, 0x01).RegistersRead.Should().Be(h | l | a, "[HL] reads HL for its address");
        Effects(set, 0x01).RegistersWritten.Should().Be(0);
        Effects(set, 0x02).RegistersWritten.Should().Be(ixh);

        InstructionEffects add = Effects(set, 0x03);
        add.RegistersRead.Should().Be(h | l | ixh | ixl);
        add.RegistersWritten.Should().Be(h | l);
        add.FlagsWritten.Should().Be(0x41);

        InstructionEffects call = Effects(set, 0x04);
        call.FlagsRead.Should().Be(0x40);
        call.RegistersWritten.Should().Be(0);
        call.RegistersMayWrite.Should().Be(sp);
        call.ChangesAny(sp).Should().BeTrue();
        (call.Pushed, call.MayPush).Should().Be(((byte)0, (byte)2));
        (1u << call.StackRegister).Should().Be(sp);

        InstructionEffects push = Effects(set, 0x05);
        (1u << push.StackRegister).Should().Be(description.RegisterMask("U"));
        push.Pushed.Should().Be(1);

        InstructionEffects pop = Effects(set, 0x06);
        pop.RegistersWritten.Should().Be(a | description.RegisterMask("F") | sp);
        pop.FlagsWritten.Should().Be(0x41, "writing AF writes F, every flag");
    }

    /// <summary>
    ///  An <c>effects in Set</c> line wins over the description's in that set and the sets built on it.
    /// </summary>
    [TestMethod]
    public void SetLinesWinInTheSetAndThoseBuiltOnIt()
    {
        IsaDescription description = IsaParser.Parse(Tiny);
        Effects(description.InstructionSets["Small"], 0x00).FlagsSet.Should().Be(0);
        Effects(description.InstructionSets["Big"], 0x00).FlagsSet.Should().Be(0x01);
        Effects(description.InstructionSets["Big"], 0x07).FlagsSet.Should().Be(0x01);
    }

    /// <summary>
    ///  A description without effects lines has none, and every encoding says so.
    /// </summary>
    [TestMethod]
    public void DescriptionsWithoutEffectsHaveNone()
    {
        InstructionSet set = IsaParser.Parse("[isa]\n[forms]\nImp \"\"\n[Cpu]\n00 NOP Imp\n").InstructionSets["Cpu"];
        set.HasEffects.Should().BeFalse();
        set.Effects(0).IsKnown.Should().BeFalse();
    }

    /// <summary>
    ///  A copy and a condition parse: TAX sets X to A, and BRC is taken when carry is clear or negative and
    ///  overflow differ, which every combination of the three flags checks; not taken, it says carry is set.
    /// </summary>
    [TestMethod]
    public void CopiesAndConditionsParse()
    {
        InstructionSet set = IsaParser.Parse(Tiny).InstructionSets["Small"];
        set.TryDecode([0x08], out int tax).Should().BeTrue();
        InstructionEffects copy = set.Effects(tax);
        copy.CopyCount.Should().Be(1);
        copy.GetCopy(0, out int destination, out int source);
        (destination, source).Should().Be((X, A));

        set.TryDecode([0x09, 0x00], out int brc).Should().BeTrue();
        InstructionEffects branch = set.Effects(brc);
        const byte N = 0x80, V = 0x40, C = 0x01;
        branch.ConditionFlags.Should().Be(N | V | C);
        for (int row = 0; row < 8; row++)
        {
            byte flags = (byte)(((row & 1) != 0 ? C : 0) | ((row & 2) != 0 ? N : 0) | ((row & 4) != 0 ? V : 0));
            bool taken = (flags & C) == 0 || ((flags & N) != 0) != ((flags & V) != 0);
            branch.Taken(0xFF, flags).Should().Be(taken, $"flags ${flags:X2}");
        }

        branch.Taken(0, 0).Should().BeNull();
        branch.Taken(C, 0).Should().BeTrue();
        branch.Implied(taken: false, known: 0, values: 0, out byte implied, out byte values);
        implied.Should().Be(C);
        values.Should().Be(C);
        branch.Implied(taken: true, known: C | N, values: C | N, out implied, out values);
        implied.Should().Be(N | V | C);
        values.Should().Be(N | C);
    }

    /// <summary>
    ///  Malformed or incomplete effects fail to parse, naming the line where there is one.
    /// </summary>
    /// <param name="replace">Text of the tiny description to replace.</param>
    /// <param name="with">What replaces it.</param>
    /// <param name="message">The expected message pattern.</param>
    [TestMethod]
    [DataRow("reads A carry ", "reads A Q ", "Line 8: 'Q' is not a register*")]
    [DataRow("reads A carry ", "reads A carry=1 ", "Line 8: Only written flags take a value*")]
    [DataRow("writes A carry=0", "writes A carry=2", "Line 9: Expected flag=0, flag=1, flag=bitN or flag=?*")]
    [DataRow("effects NOP none", "effects NOP none\neffects TSX reads S", "Line 15: No encoding takes the effects for 'TSX'.")]
    [DataRow("effects NOP none", "effects NOP none\neffects ADD:Abs none\neffects ADD:Idx none", "Line 8: No encoding takes the effects for 'ADD'.")]
    [DataRow("effects in Big ", "effects in Huge ", "Effects name an unknown instruction set 'Huge'.")]
    [DataRow("effects PUL ", "effects PUL PSH ", "Line 12: Effects for 'PSH' are malformed or already given.")]
    [DataRow("push 1", "push", "Line 11: Expected 'push [Register] n'*")]
    [DataRow("stack S\n", "", "Line 10: 'push' needs a 'stack' line*")]
    [DataRow("reads P S           writes S", "reads P             writes S", "Line 11: Pushes and pulls read and write S*")]
    [DataRow("effects NOP none", "effects NOP none\nparts P=A,X", "Line 15: Expected 'parts Register=Part,Part ...' before any effects line.")]
    [DataRow("effects NOP none", "effects NOP none reads A", "Line 14: Expected 'effects*")]
    [DataRow("effects NOP none", "effects NOP", "Line 14: Expected 'effects*")]
    [DataRow("effects NOP none", "# no NOP", "Instruction set 'Small': no effects line gives NOP Imp.")]
    [DataRow("taken carry=0|negative!=overflow", "taken carry!=0", "Line 17: Expected 'taken' and a condition*")]
    [DataRow("taken carry=0|negative!=overflow", "taken", "Line 17: Expected 'taken' and a condition*")]
    [DataRow("taken carry=0|negative!=overflow", "taken carry=0|", "Line 17: Expected 'taken' and a condition*")]
    [DataRow("reads carry negative overflow ", "reads carry negative ", "Line 17: A condition's flags are read*")]
    [DataRow("copies X=A", "copies X=Q", "Line 16: Expected 'copies Register=Register'*")]
    [DataRow("copies X=A", "copies X=A X=A X=A X=A X=A", "Line 16: Expected one to four copies.")]
    public void MalformedEffectsFail(string replace, string with, string message)
    {
        Tiny.Should().Contain(replace);
        Action parse = () => IsaParser.Parse(Tiny.Replace(replace, with, StringComparison.Ordinal));
        parse.Should().Throw<FormatException>().WithMessage(message);
    }

    /// <summary>
    ///  Every 6502 family set, the 65SC02 subset included, says what each of its encodings does.
    /// </summary>
    [TestMethod]
    public void EveryM6502EncodingHasEffects()
    {
        foreach (InstructionSet set in M6502Isa.Description.InstructionSets.Values)
        {
            set.HasEffects.Should().BeTrue(set.Name);
            for (int encoding = 0; encoding < set.Encodings.Count; encoding++)
            {
                set.Effects(encoding).IsKnown.Should().BeTrue($"{set.Name} {set.MnemonicName(set.GetEncoding(encoding).Mnemonic)}");
            }
        }
    }

    /// <summary>
    ///  The variants differ where the CPUs do: the CMOS BRK clears decimal mode, in every set built on the
    ///  65C02, and BIT immediate changes only zero.
    /// </summary>
    [TestMethod]
    public void M6502VariantsDifferWhereTheCpusDo()
    {
        IsaDescription description = M6502Isa.Description;
        int decimalBit = Flag(description, "decimal");
        Effects(M6502Isa.Get(ProcessorVariant.Mos6502), 0x00).FlagsCleared.Should().Be(0);
        foreach (string name in new[] { "Wdc65C02", "Rockwell65C02", "65SC02" })
        {
            Effects(description.InstructionSets[name], 0x00).FlagsCleared.Should().Be((byte)(1 << decimalBit), name);
        }

        // The NMOS XAA and LAX #n take a constant that differs from chip to chip, which the core cannot know.
        InstructionSet nmos = M6502Isa.Get(ProcessorVariant.Mos6502);
        uint a = description.RegisterMask("A");
        Effects(nmos, 0x8B).RegistersHidden.Should().Be(a);
        Effects(nmos, 0xAB).RegistersHidden.Should().Be(a | description.RegisterMask("X"));
        Effects(nmos, 0xA9).RegistersHidden.Should().Be(0, "LDA #n is no such instruction");

        InstructionEffects immediate = Effects(M6502Isa.Get(ProcessorVariant.Wdc65C02), 0x89);
        immediate.FlagsWritten.Should().Be((byte)(1 << Flag(description, "zero")));
        immediate.FlagsFromOperand.Should().Be(0);
        Effects(M6502Isa.Get(ProcessorVariant.Wdc65C02), 0x2C).OperandBit(7).Should().Be(7);
        Effects(M6502Isa.Get(ProcessorVariant.Mos6502), 0x89).Should().Be(new InstructionEffects { IsKnown = true });
    }

    /// <summary>
    ///  Runs every opcode from random states on the core, which the SingleStepTests certify, and checks the
    ///  data both ways: what it says is not written keeps its value, constants take their value, a copied flag
    ///  is the operand's bit, the stack moves by the bytes pushed and pulled; and changing a register or flag
    ///  the data says is not read changes nothing else, on the bus or in the result, while each one it says is
    ///  read, or written, makes a difference in some case.
    /// </summary>
    /// <param name="variant">The CPU variant.</param>
    [TestMethod]
    [DataRow(ProcessorVariant.Mos6502)]
    [DataRow(ProcessorVariant.Wdc65C02)]
    [DataRow(ProcessorVariant.Rockwell65C02)]
    public void M6502EffectsMatchExecution(ProcessorVariant variant)
    {
        InstructionSet set = M6502Isa.Get(variant);
        RecordingBus bus = new();
        Processor<RecordingBus> cpu = new(bus, variant);
        ProcessorSnapshot baseline = cpu.CaptureState();
        Random random = new(6502 + (int)variant);
        byte[] template = new byte[65536];
        List<string> failures = [];
        for (int opcode = 0; opcode < 256; opcode++)
        {
            set.TryDecode([(byte)opcode], out int encoding).Should().BeTrue($"opcode ${opcode:X2}");
            InstructionEffects effects = set.Effects(encoding);
            random.NextBytes(template);
            template.CopyTo(bus.Memory, 0);
            Observed observed = default;
            int before = failures.Count;
            for (int index = 0; index < CasesPerOpcode && failures.Count == before; index++)
            {
                ProcessorRegisters start = new()
                {
                    ProgramCounter = (ushort)random.Next(0x10000),
                    StackPointer = (byte)random.Next(256),
                    Accumulator = (byte)random.Next(256),
                    X = (byte)random.Next(256),
                    Y = (byte)random.Next(256),
                    Status = (StatusRegister)random.Next(256)
                };

                template[start.ProgramCounter] = (byte)opcode;
                bus.Memory[start.ProgramCounter] = (byte)opcode;
                Outcome outcome = Run(cpu, bus, baseline, template, start);
                string label = $"{variant} ${opcode:X2} case {index}";
                CheckOutcome(effects, start, outcome, label, failures, ref observed);
                Perturb(cpu, bus, baseline, template, effects, start, outcome, random, label, failures, ref observed);
            }

            CheckObserved(effects, observed, $"{variant} ${opcode:X2}", failures);
        }

        string.Join(Environment.NewLine, failures).Should().BeEmpty();
    }

    /// <summary>
    ///  Checks the 6502 family's effects against every SingleStepTests vector: what the data says is not
    ///  written is unchanged, constants take their value, a copied flag is the operand's bit, and the stack
    ///  moves by the bytes pushed and pulled, with one write for each byte pushed.
    /// </summary>
    /// <param name="variant">The CPU variant.</param>
    /// <param name="directory">The upstream fixture directory.</param>
    [TestMethod]
    [TestCategory("Conformance")]
    [DataRow(ProcessorVariant.Mos6502, "6502")]
    [DataRow(ProcessorVariant.Wdc65C02, "wdc65c02")]
    [DataRow(ProcessorVariant.Rockwell65C02, "rockwell65c02")]
    public void M6502EffectsMatchSingleStepVectors(ProcessorVariant variant, string directory)
    {
        InstructionSet set = M6502Isa.Get(variant);
        List<string> failures = [];
        long total = 0;
        for (int opcode = 0; opcode < 256; opcode++)
        {
            byte[] bytes = ExternalTestData.Read(ExternalTestData.SingleStepPin, $"{directory}/v1/{opcode:x2}.json");
            if (bytes.Length == 0 && variant == ProcessorVariant.Wdc65C02 && opcode is 0xCB or 0xDB)
            {
                continue;
            }

            set.TryDecode([(byte)opcode], out int encoding).Should().BeTrue();
            InstructionEffects effects = set.Effects(encoding);
            using JsonDocument document = JsonDocument.Parse(bytes);
            int index = 0;
            Observed observed = default;
            foreach (JsonElement test in document.RootElement.EnumerateArray())
            {
                ProcessorRegisters start = Registers(test.GetProperty("initial"));
                List<(ushort Address, byte Value, BusOperation Operation)> accesses = [];
                foreach (JsonElement cycle in test.GetProperty("cycles").EnumerateArray())
                {
                    accesses.Add((
                        cycle[0].GetUInt16(),
                        cycle[1].GetByte(),
                        cycle[2].GetString() == "read" ? BusOperation.Read : BusOperation.Write));
                }

                Outcome outcome = (Registers(test.GetProperty("final")), accesses, ProcessorExecutionStatus.InstructionComplete);
                int before = failures.Count;
                CheckOutcome(effects, start, outcome, $"{directory}/{opcode:x2} case {index}", failures, ref observed);
                if (failures.Count > before) { break; }
                index++;
                total++;
            }
        }

        Console.WriteLine($"{directory}: {total:N0} vectors checked.");
        string.Join(Environment.NewLine, failures).Should().BeEmpty();
        total.Should().Be(variant == ProcessorVariant.Wdc65C02 ? 2540000 : 2560000);
    }

    // What the data says, checked against one execution from a start state.
    private static void CheckOutcome(
        InstructionEffects effects,
        ProcessorRegisters start,
        Outcome outcome,
        string label,
        List<string> failures,
        ref Observed observed)
    {
        ProcessorRegisters end = outcome.Registers;
        for (int index = 0; index < effects.CopyCount; index++)
        {
            // A copy leaves its destination with the source's value from before the instruction.
            effects.GetCopy(index, out int destination, out int source);
            if (GetRegister(end, destination) != GetRegister(start, source))
            {
                failures.Add($"{label}: {Name(destination)} is ${GetRegister(end, destination):X2}, not {Name(source)}'s ${GetRegister(start, source):X2}.");
            }
        }

        foreach ((int register, byte before, byte after) in RegisterPairs(start, end))
        {
            if (before != after) { observed.Registers |= 1u << register; }
            if (!effects.Writes(register) && before != after)
            {
                failures.Add($"{label}: {Name(register)} changed from ${before:X2} to ${after:X2} but is not written.");
            }
        }

        byte startFlags = (byte)start.Status;
        byte endFlags = (byte)end.Status;
        observed.Flags |= (byte)((startFlags ^ endFlags) & AllFlags);
        byte unwritten = (byte)(AllFlags & ~effects.FlagsWritten);
        if (((startFlags ^ endFlags) & unwritten) != 0)
        {
            failures.Add($"{label}: flags changed from ${startFlags:X2} to ${endFlags:X2}, outside the written ${effects.FlagsWritten:X2}.");
        }

        if ((endFlags & effects.FlagsSet) != effects.FlagsSet || (endFlags & effects.FlagsCleared) != 0)
        {
            failures.Add($"{label}: flags ${endFlags:X2} miss the set ${effects.FlagsSet:X2} or cleared ${effects.FlagsCleared:X2}.");
        }

        if (effects.FlagsFromOperand != 0)
        {
            // The memory operand is the instruction's last read, as for BIT.
            int operand = -1;
            foreach ((_, byte value, BusOperation operation) in outcome.Accesses)
            {
                if (operation == BusOperation.Read) { operand = value; }
            }

            for (int bit = 0; bit < 8; bit++)
            {
                int source = effects.OperandBit(bit);
                if (source >= 0 && ((endFlags >> bit) & 1) != ((operand >> source) & 1))
                {
                    failures.Add($"{label}: flag bit {bit} is not bit {source} of the operand ${operand:X2}.");
                }
            }
        }

        if (outcome.Status == ProcessorExecutionStatus.InstructionComplete && (effects.Pushed | effects.Pulled) != 0)
        {
            int stackWrites = 0;
            foreach ((ushort address, _, BusOperation operation) in outcome.Accesses)
            {
                if (operation == BusOperation.Write && address >> 8 == 1) { stackWrites++; }
            }

            byte expected = (byte)(start.StackPointer - effects.Pushed + effects.Pulled);
            if (end.StackPointer != expected || stackWrites != effects.Pushed)
            {
                failures.Add($"{label}: S went from ${start.StackPointer:X2} to ${end.StackPointer:X2} with {stackWrites} stack writes; "
                    + $"expected ${expected:X2} and {effects.Pushed}.");
            }
        }
    }

    // Changes each register and flag in turn: one not read must change nothing but itself.
    private static void Perturb(
        Processor<RecordingBus> cpu,
        RecordingBus bus,
        ProcessorSnapshot baseline,
        byte[] template,
        InstructionEffects effects,
        ProcessorRegisters start,
        Outcome outcome,
        Random random,
        string label,
        List<string> failures,
        ref Observed observed)
    {
        byte change = (byte)random.Next(1, 256);
        int[] registers = [RegisterA, RegisterX, RegisterY, RegisterS];
        foreach (int register in registers)
        {
            ProcessorRegisters changed = start;
            if (register == RegisterA) { changed.Accumulator ^= change; }
            else if (register == RegisterX) { changed.X ^= change; }
            else if (register == RegisterY) { changed.Y ^= change; }
            else { changed.StackPointer ^= change; }

            Outcome other = Run(cpu, bus, baseline, template, changed);
            ProcessorRegisters expected = outcome.Registers;
            if (!effects.Writes(register))
            {
                // Unwritten, the register keeps its changed value; everything else must match.
                expected = SetRegister(expected, register, GetRegister(changed, register));
            }

            bool differs = !Same(expected, other.Registers, outcome, other);
            if (differs) { observed.ReadRegisters |= 1u << register; }
            if (differs && !effects.Reads(register))
            {
                failures.Add($"{label}: changing {Name(register)}, which is not read, changed the result.");
            }
        }

        for (int bit = 0; bit < 8; bit++)
        {
            byte mask = (byte)(1 << bit);
            if ((AllFlags & mask) == 0) { continue; }
            ProcessorRegisters changed = start;
            changed.Status ^= (StatusRegister)mask;
            Outcome other = Run(cpu, bus, baseline, template, changed);
            ProcessorRegisters expected = outcome.Registers;
            if (!effects.WritesFlag(bit)) { expected.Status ^= (StatusRegister)mask; }
            bool differs = !Same(expected, other.Registers, outcome, other);
            if (differs) { observed.ReadFlags |= mask; }
            if (differs && !effects.ReadsFlag(bit))
            {
                failures.Add($"{label}: changing flag bit {bit}, which is not read, changed the result.");
            }
        }
    }

    // Each register and flag the data says is read or written made a difference in some case.
    private static void CheckObserved(InstructionEffects effects, Observed observed, string label, List<string> failures)
    {
        int[] registers = [RegisterA, RegisterX, RegisterY, RegisterS];
        foreach (int register in registers)
        {
            if (effects.Reads(register) && (observed.ReadRegisters & (1u << register)) == 0)
            {
                failures.Add($"{label}: {Name(register)} is read, but changing it never made a difference.");
            }

            if (effects.Writes(register) && (observed.Registers & (1u << register)) == 0)
            {
                failures.Add($"{label}: {Name(register)} is written, but never changed.");
            }
        }

        byte flagsRead = (byte)(effects.FlagsRead & ~observed.ReadFlags);
        byte flagsWritten = (byte)(effects.FlagsWritten & ~observed.Flags);
        if (flagsRead != 0)
        {
            failures.Add($"{label}: flags ${flagsRead:X2} are read, but changing them never made a difference.");
        }

        if (flagsWritten != 0)
        {
            failures.Add($"{label}: flags ${flagsWritten:X2} are written, but never changed.");
        }
    }

    private static bool Same(ProcessorRegisters expected, ProcessorRegisters actual, Outcome first, Outcome second)
    {
        if (expected.ProgramCounter != actual.ProgramCounter
            || expected.Accumulator != actual.Accumulator
            || expected.X != actual.X
            || expected.Y != actual.Y
            || expected.StackPointer != actual.StackPointer
            || expected.Status != actual.Status
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

    private static Outcome Run(Processor<RecordingBus> cpu, RecordingBus bus, ProcessorSnapshot baseline, byte[] template, ProcessorRegisters start)
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

    private static IEnumerable<(int Register, byte Before, byte After)> RegisterPairs(ProcessorRegisters before, ProcessorRegisters after) =>
    [
        (RegisterA, before.Accumulator, after.Accumulator),
        (RegisterX, before.X, after.X),
        (RegisterY, before.Y, after.Y),
        (RegisterS, before.StackPointer, after.StackPointer)
    ];

    private static byte GetRegister(ProcessorRegisters registers, int register)
    {
        if (register == RegisterA) { return registers.Accumulator; }
        if (register == RegisterX) { return registers.X; }
        return register == RegisterY ? registers.Y : registers.StackPointer;
    }

    private static ProcessorRegisters SetRegister(ProcessorRegisters registers, int register, byte value)
    {
        if (register == RegisterA) { registers.Accumulator = value; }
        else if (register == RegisterX) { registers.X = value; }
        else if (register == RegisterY) { registers.Y = value; }
        else { registers.StackPointer = value; }
        return registers;
    }

    private static ProcessorRegisters Registers(JsonElement state) => new()
    {
        ProgramCounter = state.GetProperty("pc").GetUInt16(),
        StackPointer = state.GetProperty("s").GetByte(),
        Accumulator = state.GetProperty("a").GetByte(),
        X = state.GetProperty("x").GetByte(),
        Y = state.GetProperty("y").GetByte(),
        Status = (StatusRegister)state.GetProperty("p").GetByte()
    };

    private static InstructionEffects Effects(InstructionSet set, byte opcode)
    {
        set.TryDecode([opcode], out int encoding).Should().BeTrue();
        return set.Effects(encoding);
    }

    private static int Flag(IsaDescription description, string word) =>
        description.Flags.Single(flag => flag.Words.Contains(word)).Bit;

    private static int Index(string name)
    {
        IReadOnlyList<IsaRegister> registers = M6502Isa.Description.Registers;
        for (int index = 0; index < registers.Count; index++)
        {
            if (registers[index].Name == name) { return index; }
        }

        throw new InvalidOperationException($"No register {name}.");
    }

    private static string Name(int register) => M6502Isa.Description.Registers[register].Name;
}
