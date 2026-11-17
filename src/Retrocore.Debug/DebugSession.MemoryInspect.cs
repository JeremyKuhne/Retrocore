// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using Retrocore.Basic;
using System.Text.Json.Nodes;
using System.Text.RegularExpressions;

namespace Retrocore.Debug;

// retro/memory/inspect: what Retrocore Memory's inspector says about the address at the cursor.
internal sealed partial class DebugSession
{
    // How far past a code label an address still reads as in it, such as COUT+3.
    private const int LabelReach = 0x100;

    /// <summary>
    ///  Answers retro/memory/inspect: where an address of a memory view's space is and what the debugger knows of it.
    /// </summary>
    /// <remarks>
    ///  <para>
    ///   For a <c>memoryReference</c> and an <c>address</c>: the <c>region</c> of the machine's map it is in, such as
    ///   <c>Text page 1</c>, with its <c>kind</c> and the <c>detail</c> of where in it, such as <c>row 3, column 12</c>;
    ///   what the memory map does with it now, <c>mapped</c>, on a machine with banks; the <c>label</c> it is or is
    ///   in, with the <c>offset</c> past it and its documentation's <c>summary</c>; the source <c>path</c> and
    ///   <c>line</c> that emitted it; and the BASIC's floating point <c>values</c> starting there, each a
    ///   <c>label</c> and <c>value</c>. Anything unknown is null.
    ///  </para>
    /// </remarks>
    private JsonObject MemoryInspect(JsonObject args)
    {
        MemoryReference(Required(args, "memoryReference"), out DebugMemoryBank? bank);
        int address = args.Int("address") ?? throw new ArgumentException("address is required.");
        if (address is < 0 or > 0xFFFF)
        {
            throw new ArgumentOutOfRangeException(nameof(args), "The address is in $0000-$FFFF.");
        }

        IDebugMemory memory = bank is null ? Target : new BankMemory(bank);
        DebugRegion? region = DebugRegion.At(Target.Regions, address);

        // The name at the address, a constant such as CH included; else the code label it is in, as COUT+3.
        (SortedDictionary<int, string> labels, SortedDictionary<int, string> names) = LabelsAndNames(bank, memory);
        string? label = null;
        int offset = 0;
        if (names.TryGetValue(address, out string? named))
        {
            label = named;
        }
        else if (labels.Keys.LastOrDefault(start => start <= address, -1) is var start and >= 0 && address - start < LabelReach)
        {
            label = labels[start];
            offset = address - start;
        }

        SourceLine? source = _debug.Position(memory, (ushort)address)?.Chain[^1];
        return new JsonObject
        {
            ["address"] = address,
            ["region"] = region?.Name,
            ["kind"] = region?.Kind,
            ["detail"] = region?.Detail?.Invoke(address - region.Start),
            ["mapped"] = Mapping(bank, (ushort)address),
            ["label"] = label,
            ["offset"] = offset,
            ["summary"] = label is null ? null : SymbolSummary(label),
            ["path"] = source?.Path,
            ["line"] = source?.Line,
            ["values"] = Floats(memory, address)
        };
    }

    // What the memory map does with an address now, on a machine with banks: in the CPU's view, what it reads and
    // writes there; in a bank's, whether the CPU reaches the bank there.
    private string? Mapping(DebugMemoryBank? bank, ushort address)
    {
        if (Target.Banks.Count == 0) { return null; }
        Enum read = Target.ReadArea(address), write = Target.WriteArea(address);
        if (bank is null)
        {
            return read.Equals(write) ? $"Reads and writes {AreaName(read)}" : $"Reads {AreaName(read)}, writes {AreaName(write)}";
        }

        if (bank.AreaOf(address) is null) { return $"{bank.Label} has no byte here"; }
        bool reads = bank.Areas.Contains(read), writes = bank.Areas.Contains(write);
        return (reads, writes) switch
        {
            (true, true) => "The CPU reads and writes it here now",
            (true, false) => $"The CPU reads it here now, and writes {AreaName(write)}",
            (false, true) => $"The CPU writes it here now, and reads {AreaName(read)}",
            _ => $"Not mapped now: the CPU reads {AreaName(read)} here"
        };
    }

    // An area as a sentence names it: the label of a bank that is that area alone, such as slot 6 ROM (Disk II boot);
    // else its own name in words, such as main language card, as a bank of several areas names them all.
    private string AreaName(Enum area)
    {
        if (Target.Banks.FirstOrDefault(bank => bank.Areas.Count == 1 && bank.Areas[0].Equals(area)) is { } owner)
        {
            string text = owner.Label;
            return text.Length > 1 && char.IsLower(text[1]) ? char.ToLowerInvariant(text[0]) + text[1..] : text;
        }

        return string.Join(' ', AreaWords().Split(area.ToString()).Select(word => word switch
        {
            "Ram" => "RAM",
            "Rom" => "ROM",
            "Io" => "I/O",
            "None" => "nothing",
            _ => word.ToLowerInvariant()
        }));
    }

    // The words of an area's name, such as Slot 1 Rom in Slot1Rom.
    [GeneratedRegex("(?<=[a-z])(?=[A-Z0-9])|(?<=[0-9])(?=[A-Z])")]
    private static partial Regex AreaWords();

    // The BASIC's floating point numbers that start at an address: AppleSoft's, Color BASIC's and Business BASIC's
    // five bytes, exponent first; Level II's single and double, exponent last. None for an integer BASIC.
    private JsonArray Floats(IDebugMemory memory, int address)
    {
        JsonArray values = [];
        BasicDialect? basic = Target.Basic;
        if (basic is null || ReferenceEquals(basic, BasicDialect.Integer) || ReferenceEquals(basic, BasicDialect.Apple1))
        {
            return values;
        }

        void Add(string label, int length, bool exponentFirst, int digits)
        {
            if (address + length > 0x10000) { return; }
            byte[] bytes = [.. Enumerable.Range(address, length).Select(at => memory.Peek((ushort)at))];
            values.Add((JsonNode)new JsonObject
            {
                ["label"] = label,
                ["value"] = BasicNumbers.Format(BasicNumbers.ReadFloat(bytes, exponentFirst), digits)
            });
        }

        if (ReferenceEquals(basic, BasicDialect.Level2))
        {
            Add("Single, 4 bytes", 4, exponentFirst: false, digits: 6);
            Add("Double, 8 bytes", 8, exponentFirst: false, digits: 16);
        }
        else
        {
            Add("Float, 5 bytes", 5, exponentFirst: true, digits: 9);
        }

        return values;
    }
}
