// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using Retrocore.Assembler;
using Retrocore.Isa;

namespace Retrocore.Tests;

/// <summary>
///  The instruction-set description agrees with the generated opcode tables it is read from.
/// </summary>
[TestClass]
public class IsaDescriptionTests
{
    /// <summary>
    ///  Every opcode decodes to the same instruction and form, and every mnemonic and form encodes to the same
    ///  opcode as the assembler's tables.
    /// </summary>
    /// <param name="variant">The CPU variant.</param>
    [TestMethod]
    [DataRow(ProcessorVariant.Mos6502)]
    [DataRow(ProcessorVariant.Wdc65C02)]
    [DataRow(ProcessorVariant.Rockwell65C02)]
    public void EncodingsMatchOpcodeTables(ProcessorVariant variant)
    {
        InstructionSet set = M6502Isa.Get(variant);
        ReadOnlySpan<OpCode> table = OpcodeTable.Get(variant);

        set.Encodings.Count.Should().Be(256);
        Dictionary<(string, AddressMode), byte> canonical = [];
        for (int code = 0; code < 256; code++)
        {
            IsaEncoding encoding = set.Encodings[code];
            encoding.Opcode.Should().Be((uint)code);
            encoding.OpcodeLength.Should().Be(1);
            set.InstructionName(encoding.Mnemonic).Should().Be(table[code].Instruction.ToString());
            set.Forms[encoding.Form].Name.Should().Be(table[code].AddressMode.ToString());
            set.Size(code).Should().Be(InstructionEncoding.GetSize(table[code].AddressMode));
            set.TryDecode([(byte)code], out int decoded).Should().BeTrue();
            decoded.Should().Be(code);
            set.Flow(code).Should().Be(ExpectedFlow(table[code]), table[code].ToString());
            encoding.Undocumented.Should().Be(ExpectedUndocumented(variant, table[code]), table[code].ToString());

            // The first encoding of a mnemonic and mode is canonical, except that NOP prefers $EA.
            (string, AddressMode) key = (set.MnemonicName(encoding.Mnemonic), table[code].AddressMode);
            if (!canonical.ContainsKey(key) || code == InstructionEncoding.OfficialNop) { canonical[key] = (byte)code; }
        }

        for (int mnemonic = 0; mnemonic < set.MnemonicCount; mnemonic++)
        {
            string name = set.MnemonicName(mnemonic);
            foreach (AddressMode mode in Enum.GetValues<AddressMode>())
            {
                bool expected = canonical.TryGetValue((name, mode), out byte opcode);
                int form = set.Description.Form(mode.ToString())?.Id ?? -1;
                set.TryGet(mnemonic, form, out int encoding).Should().Be(expected, $"{name} {mode}");
                if (expected)
                {
                    set.Encodings[encoding].Opcode.Should().Be(opcode, $"{name} {mode}");
                }
            }
        }
    }

    /// <summary>
    ///  The 65SC02 subset excludes the bit and low-power instructions with the assembler's message.
    /// </summary>
    [TestMethod]
    public void SubsetExcludesInstructions()
    {
        InstructionSet set = M6502Isa.Description.InstructionSets["65SC02"];
        set.Exclusion(set.GetMnemonic("WAI")).Should().Be("Instruction '{0}' is not in the 65SC02 subset.");
        set.Exclusion(set.GetMnemonic("BBR3")).Should().NotBeNull();
        set.Exclusion(set.GetMnemonic("LDA")).Should().BeNull();
        set.GetMnemonic("smb7").Should().NotBe(InstructionSet.UnknownMnemonic);
    }

    /// <summary>
    ///  Malformed descriptions name the offending line.
    /// </summary>
    [TestMethod]
    public void ErrorsNameTheLine()
    {
        Action parse = () => IsaParser.Parse("[isa]\nendian sideways\n");
        parse.Should().Throw<FormatException>().WithMessage("Line 2:*");
    }

    // The flow classes the disassembler hard-coded before the description declared them.
    private static InstructionFlow ExpectedFlow(OpCode opcode) => opcode.Instruction switch
    {
        Instruction.BBR
            or Instruction.BBS
            or Instruction.BCC
            or Instruction.BCS
            or Instruction.BEQ
            or Instruction.BMI
            or Instruction.BNE
            or Instruction.BPL
            or Instruction.BVC
            or Instruction.BVS => InstructionFlow.ConditionalBranch,
        Instruction.BRA => InstructionFlow.Jump,
        Instruction.JMP => opcode.AddressMode == AddressMode.Absolute ? InstructionFlow.Jump : InstructionFlow.IndirectJump,
        Instruction.JSR => InstructionFlow.Call,
        Instruction.RTS or Instruction.RTI => InstructionFlow.Return,
        Instruction.BRK => InstructionFlow.Break,
        Instruction.WAI => InstructionFlow.Wait,
        Instruction.STP or Instruction.JAM => InstructionFlow.Stop,
        _ => InstructionFlow.Next
    };

    // The undocumented encodings the disassembler hard-coded before the description marked them.
    private static bool ExpectedUndocumented(ProcessorVariant variant, OpCode opcode) =>
        variant == ProcessorVariant.Mos6502
            && ((byte)opcode.Instruction >= (byte)Instruction.JAM
                || (opcode.Instruction == Instruction.NOP && opcode.Code != InstructionEncoding.OfficialNop)
                || (opcode.Instruction == Instruction.SBC && opcode.Code == InstructionEncoding.UndocumentedImmediateSbc));
}
