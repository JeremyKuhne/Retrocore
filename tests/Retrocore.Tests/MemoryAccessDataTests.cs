// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using Retrocore.Assembler;
using Retrocore.Isa;

namespace Retrocore.Tests;

/// <summary>
///  The instruction-set descriptions' <c>access</c> lines against execution: an encoding that writes memory, beyond
///  what it pushes, says so, as the routine analysis relies on to forget what memory held.
/// </summary>
[TestClass]
public class MemoryAccessDataTests
{
    private const int CasesPerEncoding = 16;

    // Writes a port feeds, which the evaluator does not run: their access lines are written by hand.
    private static readonly HashSet<string> s_portFed = ["INI", "IND", "INIR", "INDR"];

    /// <summary>
    ///  Every encoding that writes memory other than by pushing is a write or a read-write, and every one that is
    ///  runs and writes in some case, but the Z80's block inputs, which a port feeds and the evaluator does not run.
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
    public void WritesAreDeclared(string name, int seed)
    {
        InstructionSet set = CpuCatalog.Get(name);
        AnalysisEvaluator evaluator = AnalysisEvaluator.For(set) ?? throw new AssertFailedException($"No core for {name}.");
        IsaDescription description = set.Description;
        Random random = new(seed);
        byte[] bytes = new byte[8];
        byte[] reads = new byte[16];
        int[] registers = new int[description.EffectRegisters.Count];
        List<string> failures = [];
        for (int encoding = 0; encoding < set.Encodings.Count; encoding++)
        {
            IsaEncoding value = set.GetEncoding(encoding);
            string label = $"{set.MnemonicName(value.Mnemonic)} {set.GetForm(value.Form).Name}";
            MemoryAccess access = set.EncodingAccess(encoding);
            bool ran = false, wrote = false;
            for (int index = 0; index < CasesPerEncoding; index++)
            {
                int size = Encode(set, encoding, random, bytes);
                ushort pc = (ushort)random.Next(0x10000);
                Disassembler.TryDecode(bytes.AsSpan(0, size), pc, set, out DisassembledInstruction instruction).Should().BeTrue();
                InstructionEffects effects = instruction.Effects;
                for (int bit = 0; bit < registers.Length; bit++) { registers[bit] = Random(description, bit, random); }
                int flags = random.Next(256);
                random.NextBytes(reads);

                // A port, a halt or more reads than given end the case without a result.
                if (!evaluator.TryRun(pc, bytes.AsSpan(0, size), registers, ref flags, reads, out _, out _))
                {
                    continue;
                }

                ran = true;
                wrote |= evaluator.WriteCount > effects.Pushed + effects.MayPush;
            }

            string mnemonic = set.MnemonicName(value.Mnemonic);
            if (!ran && access != MemoryAccess.Read && !s_portFed.Contains(mnemonic))
            {
                failures.Add($"{label}: its access is {access}, but it never ran to show it");
            }
            else if (wrote && access == MemoryAccess.Read)
            {
                failures.Add($"{label}: writes memory, but its access is read");
            }
            else if (ran && !wrote && access != MemoryAccess.Read)
            {
                failures.Add($"{label}: its access is {access}, but it never wrote");
            }
        }

        foreach (string failure in failures) { Console.WriteLine(failure); }
        failures.Should().BeEmpty();
    }

    private static int Random(IsaDescription description, int bit, Random random)
    {
        string name = description.EffectRegisters[bit];
        IsaRegister? register = description.Registers.FirstOrDefault(candidate => candidate.Name == name);
        return random.Next(register is { Bits: 16 } ? 0x10000 : 0x100);
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
}
