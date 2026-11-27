// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using Retrocore.Assembler;
using Retrocore.Isa;

namespace Retrocore.Tests;

/// <summary>
///  The <c>taken</c> conditions of the effects lines (docs/backlog/StaticAnalysis.md) against execution: every
///  conditional branch, call and return of every CPU is run on its core from random flags, and goes where its
///  condition says.
/// </summary>
[TestClass]
public class BranchConditionTests
{
    private const int CasesPerEncoding = 64;

    // Conditions on something other than flags: a register count, or a bit of memory.
    private static readonly HashSet<string> s_notOnFlags = ["DJNZ", "BBR", "BBS"];

    /// <summary>
    ///  Each conditional encoding has a condition on the flags it reads, unless it decides on something else, and
    ///  is taken exactly when the condition holds.
    /// </summary>
    /// <param name="name">The instruction set.</param>
    /// <param name="seed">The random cases' seed, fixed so a failure repeats.</param>
    [TestMethod]
    [DataRow("Mos6502", 6502)]
    [DataRow("Wdc65C02", 65021)]
    [DataRow("Rockwell65C02", 65022)]
    [DataRow("Z80", 80)]
    [DataRow("M6809", 6809)]
    [DataRow("I8080", 8080)]
    [DataRow("I8085", 8085)]
    public void ConditionsMatchExecution(string name, int seed)
    {
        InstructionSet set = CpuCatalog.Get(name);
        AnalysisEvaluator evaluator = AnalysisEvaluator.For(set) ?? throw new AssertFailedException($"No core for {name}.");
        IsaDescription description = set.Description;
        Random random = new(seed);
        byte[] bytes = new byte[8];
        byte[] reads = new byte[8];
        int[] registers = new int[description.EffectRegisters.Count];
        List<string> failures = [];
        int checkedEncodings = 0;
        for (int encoding = 0; encoding < set.Encodings.Count; encoding++)
        {
            InstructionEffects effects = set.Effects(encoding);
            IsaEncoding value = set.GetEncoding(encoding);
            string mnemonic = set.MnemonicName(value.Mnemonic);
            string label = $"{mnemonic} {set.GetForm(value.Form).Name}";
            if (!IsConditional(set, encoding, effects))
            {
                // A condition on an encoding this test would not run is a condition nothing checks.
                if (effects.ConditionFlags != 0)
                {
                    failures.Add($"{label}: has a 'taken' condition, but is not conditional");
                }

                continue;
            }

            if (effects.ConditionFlags == 0)
            {
                if (!s_notOnFlags.Contains(mnemonic.TrimEnd('0', '1', '2', '3', '4', '5', '6', '7')))
                {
                    failures.Add($"{label}: conditional, but no 'taken' condition");
                }

                continue;
            }

            checkedEncodings++;
            for (int index = 0; index < CasesPerEncoding; index++)
            {
                int size = Encode(set, encoding, random, bytes);
                ushort pc = (ushort)random.Next(0x10000);
                for (int bit = 0; bit < registers.Length; bit++) { registers[bit] = random.Next(256); }
                registers = Widen(description, registers, random);
                int before = random.Next(256);
                int flags = before;
                bool expected = effects.Taken(0xFF, (byte)before) == true;
                random.NextBytes(reads);
                int stack = effects.StackRegister;
                int pointer = stack >= 0 ? registers[stack] : 0;
                if (!evaluator.TryRun(pc, bytes.AsSpan(0, size), registers, ref flags, reads, out _, out ushort next))
                {
                    failures.Add($"{label}: did not run");
                    break;
                }

                // A conditional call or return moves the stack exactly when it is taken.
                if (stack >= 0 && (effects.MayPush | effects.MayPull) != 0 && (registers[stack] != pointer) != expected)
                {
                    failures.Add($"{label}: with flags ${before:X2} the stack {(expected ? "did not move" : "moved")}");
                    break;
                }

                // A branch to the next instruction cannot be told from one not taken.
                ushort fallThrough = (ushort)(pc + size);
                if (next == fallThrough && expected) { continue; }
                if ((next != fallThrough) != expected)
                {
                    failures.Add($"{label}: with flags ${before:X2} it was {(expected ? "not " : "")}taken");
                    break;
                }
            }
        }

        failures.Should().BeEmpty();
        checkedEncodings.Should().BeGreaterThan(0);
    }

    /// <summary>
    ///  A condition says what taking it, or not, tells of its flags.
    /// </summary>
    [TestMethod]
    public void OutcomesImplyFlags()
    {
        InstructionSet set = CpuCatalog.Get("M6809");
        IsaDescription description = set.Description;
        int zero = Bit(description, "zero"), carry = Bit(description, "carry");
        InstructionEffects bhi = Effects(set, "BHI");

        // BHI taken: carry and zero are clear. Not taken, either may be set, unless one is known clear.
        bhi.Implied(taken: true, known: 0, values: 0, out byte implied, out byte values);
        implied.Should().Be((byte)((1 << zero) | (1 << carry)));
        values.Should().Be(0);
        bhi.Implied(taken: false, known: 0, values: 0, out implied, out _);
        implied.Should().Be(0);
        bhi.Implied(taken: false, known: (byte)(1 << carry), values: 0, out implied, out values);
        implied.Should().Be((byte)((1 << zero) | (1 << carry)));
        values.Should().Be((byte)(1 << zero));

        bhi.Taken(known: (byte)(1 << carry), values: (byte)(1 << carry)).Should().BeFalse();
        bhi.Taken(known: (byte)(1 << carry), values: 0).Should().BeNull();
    }

    // A conditional branch, call or return: a branch's flow, a conditional call, or a return on some paths only.
    private static bool IsConditional(InstructionSet set, int encoding, InstructionEffects effects)
    {
        if (set.Flow(encoding) == InstructionFlow.ConditionalBranch || set.GetEncoding(encoding).IsConditional)
        {
            return true;
        }

        bool returns = effects.MayPull != 0 && effects.Pulled == 0 && effects.MayPush == 0;
        return returns || (effects.MayPush != 0 && effects.Pushed == 0);
    }

    private static int[] Widen(IsaDescription description, int[] registers, Random random)
    {
        for (int bit = 0; bit < registers.Length; bit++)
        {
            string name = description.EffectRegisters[bit];
            IsaRegister? register = description.Registers.FirstOrDefault(candidate => candidate.Name == name);
            if (register is { Bits: 16 }) { registers[bit] = random.Next(0x10000); }
        }

        return registers;
    }

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

    private static InstructionEffects Effects(InstructionSet set, string mnemonic)
    {
        for (int encoding = 0; encoding < set.Encodings.Count; encoding++)
        {
            if (set.MnemonicName(set.GetEncoding(encoding).Mnemonic) == mnemonic) { return set.Effects(encoding); }
        }

        throw new AssertFailedException($"No {mnemonic}.");
    }

    private static int Bit(IsaDescription description, string word) =>
        description.Flags.Single(flag => flag.Words.Contains(word)).Bit;
}
