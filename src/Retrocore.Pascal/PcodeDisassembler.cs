// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using System.Globalization;
using Retrocore.Media;
using Touki.Text;

namespace Retrocore.Pascal;

/// <summary>
///  Decodes p-code: one instruction, or a whole procedure from its entry to the return at its exit.
/// </summary>
/// <remarks>
///  <para>
///   Offsets are from the start of the segment, which the system loads on a word boundary, so the word-aligned
///   operands of <c>LDC</c> and <c>XJP</c> are aligned on the offset. A negative jump's operand is an offset back from
///   the procedure's attributes (its jump table pointer, JTAB) to a self-relative word that holds the target. An
///   <c>XJP</c>'s missing cases point at its own <c>UJP</c>, and so are given its target.
///  </para>
/// </remarks>
public static class PcodeDisassembler
{
    /// <summary>
    ///  Decodes the p-code at an offset in a segment.
    /// </summary>
    /// <param name="code">The segment's code.</param>
    /// <param name="offset">Where the p-code is.</param>
    /// <param name="jumpTable">The offset of the procedure's attributes, which negative jumps count back from.</param>
    /// <returns>The instruction.</returns>
    /// <exception cref="InvalidDataException">The p-code runs past the end of the code.</exception>
    public static PcodeInstruction Decode(ReadOnlySpan<byte> code, int offset, int jumpTable)
    {
        if ((uint)offset >= (uint)code.Length) { throw new InvalidDataException($"No p-code at {offset}."); }

        PcodeOpcode opcode = Pcode.Opcode(code[offset]);
        int at = offset + 1;
        List<int> operands = [];
        List<int> targets = [];
        byte[] data = [];
        switch (opcode.Operands)
        {
            case PcodeOperands.Byte:
            case PcodeOperands.StandardProcedure:
                operands.Add(Byte(code, ref at));
                break;
            case PcodeOperands.Jump:
                int jump = (sbyte)Byte(code, ref at);
                operands.Add(jump);
                targets.Add(Target(code, at, jump, jumpTable));
                break;
            case PcodeOperands.Big:
                operands.Add(Big(code, ref at));
                break;
            case PcodeOperands.LevelBig:
            case PcodeOperands.SegmentBig:
                operands.Add(Byte(code, ref at));
                operands.Add(Big(code, ref at));
                break;
            case PcodeOperands.TwoBytes:
                operands.Add(Byte(code, ref at));
                operands.Add(Byte(code, ref at));
                break;
            case PcodeOperands.Word:
                operands.Add(Word(code, ref at));
                break;
            case PcodeOperands.String:
            case PcodeOperands.Bytes:
                int length = Byte(code, ref at);
                operands.Add(length);
                data = Slice(code, ref at, length);
                break;
            case PcodeOperands.Words:
                int count = Byte(code, ref at);
                operands.Add(count);
                at = (at + 1) & ~1;
                data = Slice(code, ref at, count * 2);
                break;
            case PcodeOperands.CaseJump:
                at = (at + 1) & ~1;
                int low = (short)Word(code, ref at);
                int high = (short)Word(code, ref at);
                operands.Add(low);
                operands.Add(high);
                int jumpOut = at;
                if (Byte(code, ref at) != Pcode.Ujp)
                {
                    throw new InvalidDataException($"The XJP at {offset} has no UJP.");
                }

                int jumpBy = (sbyte)Byte(code, ref at);
                int otherwise = Target(code, at, jumpBy, jumpTable);
                targets.Add(otherwise);
                if (high - low is < 0 or > 1024)
                {
                    throw new InvalidDataException($"The XJP at {offset} has {high - low + 1} cases.");
                }

                for (int index = low; index <= high; index++)
                {
                    int entry = at;
                    int relative = Word(code, ref at);

                    // A missing case points at the UJP, which goes on to the otherwise target.
                    targets.Add(entry - relative == jumpOut ? otherwise : entry - relative);
                }

                break;
            case PcodeOperands.Comparison:
                int type = Byte(code, ref at);
                operands.Add(type);
                if (type is 10 or 12) { operands.Add(Big(code, ref at)); }
                break;
            case PcodeOperands.None:
            default:
                break;
        }

        return new PcodeInstruction(offset, opcode, at - offset, operands, data, targets);
    }

    /// <summary>
    ///  Decodes a p-code procedure, from its entry through the return at or after its exit and after any code a jump
    ///  leads to.
    /// </summary>
    /// <param name="segment">Its segment.</param>
    /// <param name="procedure">The procedure.</param>
    /// <returns>Its instructions, in order.</returns>
    /// <exception cref="ArgumentException">The procedure is assembled code, not p-code.</exception>
    /// <exception cref="InvalidDataException">A p-code runs past the end of the segment.</exception>
    public static IReadOnlyList<PcodeInstruction> Disassemble(PascalSegment segment, PascalProcedure procedure)
    {
        ArgumentNullException.ThrowIfNull(segment);
        ArgumentNullException.ThrowIfNull(procedure);
        if (procedure.IsNative) { throw new ArgumentException("The procedure is assembled code.", nameof(procedure)); }

        List<PcodeInstruction> instructions = [];
        int offset = procedure.Entry;
        int farthest = procedure.Exit;
        while (true)
        {
            // A jump into the jump table, as in the system's unnamed initialization segment, ends at the table.
            if (offset >= procedure.Attributes) { return instructions; }

            PcodeInstruction instruction = Decode(segment.Code, offset, procedure.Attributes);
            instructions.Add(instruction);
            offset = instruction.Next;
            foreach (int target in instruction.Targets)
            {
                if (target < procedure.Attributes) { farthest = Math.Max(farthest, target); }
            }

            if (instruction.Opcode.Returns && instruction.Offset >= farthest) { return instructions; }
        }
    }

    /// <summary>
    ///  Formats an instruction as its mnemonic and operands, such as <c>LOD 1, 4</c> or <c>UJP $0034</c>.
    /// </summary>
    /// <param name="instruction">The instruction.</param>
    /// <returns>The text.</returns>
    public static string Format(PcodeInstruction instruction)
    {
        ArgumentNullException.ThrowIfNull(instruction);
        PcodeOpcode opcode = instruction.Opcode;
        IReadOnlyList<int> operands = instruction.Operands;
        string mnemonic = opcode.Mnemonic == "SLDC" ? $"SLDC {opcode.Code}" : opcode.Mnemonic;
        return opcode.Operands switch
        {
            PcodeOperands.None => mnemonic,
            PcodeOperands.Byte or PcodeOperands.Big => $"{mnemonic} {operands[0]}",
            PcodeOperands.LevelBig or PcodeOperands.SegmentBig or PcodeOperands.TwoBytes => $"{mnemonic} {operands[0]}, {operands[1]}",
            PcodeOperands.Word => $"{mnemonic} {(short)operands[0]}",
            PcodeOperands.Jump => $"{mnemonic} {Address(instruction.Targets[0])}",
            PcodeOperands.StandardProcedure => $"{mnemonic} {Pcode.StandardProcedure(operands[0])}",
            PcodeOperands.String => $"{mnemonic} '{Text(instruction.Data)}'",
            PcodeOperands.Bytes => $"{mnemonic} {operands[0]}: {string.Join(' ', instruction.Data.Select(value => $"${value:X2}"))}",
            PcodeOperands.Words => $"{mnemonic} {operands[0]}: {Words(instruction.Data)}",
            PcodeOperands.CaseJump =>
                $"{mnemonic} {operands[0]}..{operands[1]}, else {Address(instruction.Targets[0])}: {string.Join(' ', instruction.Targets.Skip(1).Select(Address))}",
            PcodeOperands.Comparison => $"{opcode.Mnemonic}{Comparison(operands)}",
            _ => mnemonic
        };
    }

    private static string Comparison(IReadOnlyList<int> operands) => operands[0] switch
    {
        2 => "REAL",
        4 => "STR",
        6 => "BOOL",
        8 => "POWR",
        10 => $"BYT {operands[1]}",
        12 => $"WORD {operands[1]}",
        _ => $" {operands[0]}"
    };

    private static string Address(int offset) => offset < 0 ? "?" : $"${offset:X4}";

    private static string Words(byte[] data) =>
        string.Join(' ', Enumerable.Range(0, data.Length / 2).Select(index => $"${data[index * 2] | (data[(index * 2) + 1] << 8):X4}"));

    private static string Text(byte[] data)
    {
        using ValueStringBuilder builder = new(stackalloc char[256]);
        foreach (byte value in data)
        {
            char character = (char)(value & 0x7F);
            if (character == '\'')
            {
                builder.Append("''");
            }
            else if (character is >= ' ' and < (char)0x7F)
            {
                builder.Append(character);
            }
            else
            {
                builder.Append("\\x");
                builder.Append(value.ToString("X2", CultureInfo.InvariantCulture));
            }
        }

        return builder.ToString();
    }

    // A jump forward from the next p-code, or through the jump table: the word at JTAB plus the offset is
    // self-relative.
    private static int Target(ReadOnlySpan<byte> code, int next, int jump, int jumpTable)
    {
        if (jump >= 0) { return next + jump; }

        int entry = jumpTable + jump;
        if (entry < 0 || entry + 1 >= code.Length) { return -1; }

        int target = entry - (code[entry] | (code[entry + 1] << 8));
        return target < 0 || target >= code.Length ? -1 : target;
    }

    private static int Byte(ReadOnlySpan<byte> code, ref int at)
    {
        if (at >= code.Length) { throw new InvalidDataException($"The p-code runs past the end of the code at {at}."); }
        return code[at++];
    }

    private static int Word(ReadOnlySpan<byte> code, ref int at) => Byte(code, ref at) | (Byte(code, ref at) << 8);

    // One byte below 128; otherwise its low 7 bits are the high byte of a two-byte number.
    private static int Big(ReadOnlySpan<byte> code, ref int at)
    {
        int first = Byte(code, ref at);
        return first < 0x80 ? first : ((first & 0x7F) << 8) | Byte(code, ref at);
    }

    private static byte[] Slice(ReadOnlySpan<byte> code, ref int at, int length)
    {
        if (at + length > code.Length)
        {
            throw new InvalidDataException($"The p-code runs past the end of the code at {at}.");
        }

        byte[] data = code.Slice(at, length).ToArray();
        at += length;
        return data;
    }
}
