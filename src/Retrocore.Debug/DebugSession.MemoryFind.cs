// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using Retrocore.Assembler;
using Retrocore.Isa;
using System.Text.Json.Nodes;
using System.Text.RegularExpressions;

namespace Retrocore.Debug;

// retro/memory/find: Retrocore Memory's find by instruction, such as STA $C0??.
internal sealed partial class DebugSession
{
    /// <summary>
    ///  Answers retro/memory/find: the nearest instruction in a memory view's space whose text matches a pattern.
    /// </summary>
    /// <remarks>
    ///  <para>
    ///   The <c>pattern</c> is an instruction as the listing shows it, such as <c>STA $C0??</c>, <c>JSR COUT</c> or
    ///   <c>LD A,(*)</c>: <c>?</c> stands for any one character and <c>*</c> for any run of them; case and the
    ///   spaces around commas do not matter. It matches an instruction's text with its operand as a number or as
    ///   its label. Every byte is tried as an instruction's start, from <c>from</c> forward, or back with
    ///   <c>backward</c>, wrapping around once.
    ///  </para>
    ///  <para>
    ///   The answer gives the match's <c>address</c>, <c>size</c> and <c>text</c>, or a null address where nothing
    ///   matches.
    ///  </para>
    /// </remarks>
    private JsonObject MemoryFind(JsonObject args)
    {
        MemoryReference(Required(args, "memoryReference"), out DebugMemoryBank? bank);
        Regex matcher = InstructionPattern(args.String("pattern") ?? "");
        int from = args.Int("from") ?? 0;
        bool backward = args.Bool("backward") ?? false;

        InstructionSet set = bank?.InstructionSet ?? Target.InstructionSet;
        ListingMemory memory = new(bank is null ? Target : new BankMemory(bank), address => MemoryByte(bank, address));
        (_, SortedDictionary<int, string> names) = LabelsAndNames(bank, memory);
        int? directPage = DirectPage(set);
        Span<byte> bytes = stackalloc byte[LongestInstruction];
        for (int step = 0; step < 0x10000; step++)
        {
            int address = ((backward ? from - step : from + step) % 0x10000 + 0x10000) % 0x10000;
            int available = 0;
            while (available < Math.Min(LongestInstruction, 0x10000 - address) && memory.Readable(address + available))
            {
                bytes[available] = memory.Peek((ushort)(address + available));
                available++;
            }

            if (available == 0
                || !Disassembler.TryDecode(bytes[..available], (ushort)address, set, out DisassembledInstruction instruction))
            {
                continue;
            }

            string text = instruction.ToString();
            (int? target, int? shown) = ListingOperands.OperandAddress(instruction, directPage);
            string named = ListingOperands.Named(text, target, shown, names);
            if (matcher.IsMatch(Normalized(text)) || matcher.IsMatch(Normalized(named)))
            {
                return new JsonObject { ["address"] = address, ["size"] = instruction.Size, ["text"] = named };
            }
        }

        return new JsonObject { ["address"] = null };
    }

    // A find pattern as a regular expression over normalized text: ? any one character, * any run.
    private static Regex InstructionPattern(string pattern)
    {
        string normal = Normalized(pattern);
        if (normal.Length == 0) { throw new ArgumentException("Type an instruction such as STA $C0??."); }
        string expression = string.Concat(normal.Select(character => character switch
        {
            '?' => ".",
            '*' => ".*",
            _ => Regex.Escape(character.ToString())
        }));

        return new Regex($"^{expression}$", RegexOptions.IgnoreCase | RegexOptions.CultureInvariant);
    }

    // Text with runs of spaces made one and none around commas, so LD A, B is LD A,B.
    private static string Normalized(string text) => SpacedComma().Replace(Spaces().Replace(text.Trim(), " "), ",");

    [GeneratedRegex(@"\s+")]
    private static partial Regex Spaces();

    [GeneratedRegex(@"\s*,\s*")]
    private static partial Regex SpacedComma();
}
