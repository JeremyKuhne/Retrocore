// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using System.Text.Json.Nodes;
using Retrocore.Assembler;

namespace Retrocore.Debug;

// The disassemble request, which VS Code's Disassembly view reads, and where instruction breakpoints are set.
internal sealed partial class DebugSession
{
    // The longest instruction of any CPU the debugger runs: a Z80 indexed instruction.
    private const int LongestInstruction = 4;

    private JsonObject Disassemble(JsonObject args)
    {
        string reference = Required(args, "memoryReference");
        long start = MemoryReference(reference, out DebugMemoryBank? bank) + (args.Int("offset") ?? 0);

        // A bank disassembles as if it were mapped, with the lines and labels of the modules whose code is there.
        IDebugMemory memory = bank is null ? Target : new BankMemory(bank);

        int skip = args.Int("instructionOffset") ?? 0;
        int count = (args.Int("instructionCount") ?? 0);
        bool symbols = args.Bool("resolveSymbols") ?? true;
        if (count is < 0 or > 0x10000 || start is < 0 or > 0xFFFF)
        {
            throw new ArgumentOutOfRangeException(nameof(args));
        }

        List<JsonNode?> instructions = [];
        int address = (int)start;
        if (skip < 0)
        {
            address = Before(memory, address, -skip, out int missing);
            for (int index = 0; index < missing && instructions.Count < count; index++)
            {
                instructions.Add(new JsonObject
                {
                    ["address"] = "0x0",
                    ["instruction"] = "",
                    ["presentationHint"] = "invalid"
                });
            }
        }
        else
        {
            for (int index = 0; index < skip && address <= 0xFFFF; index++)
            {
                address += Decode(memory, address).Size;
            }
        }

        while (instructions.Count < count)
        {
            if (address > 0xFFFF)
            {
                instructions.Add(new JsonObject
                {
                    ["address"] = $"0x{address:X}",
                    ["instruction"] = "",
                    ["presentationHint"] = "invalid"
                });

                address++;
                continue;
            }

            (int size, string text) = Decode(memory, address);
            string bytes = string.Join(" ", Enumerable.Range(0, size).Select(index => $"{memory.Peek((ushort)(address + index)):X2}"));
            SourceLine? line = _debug.Position(memory, (ushort)address)?.Chain[^1];
            instructions.Add(new JsonObject
            {
                ["address"] = $"0x{address:X4}",
                ["instructionBytes"] = bytes,
                ["instruction"] = text,
                ["symbol"] = symbols ? Symbol(memory, (ushort)address) : null,
                ["location"] = line is { } source ? new JsonObject
                {
                    ["name"] = Path.GetFileName(source.Path),
                    ["path"] = source.Path
                } : null,
                ["line"] = line?.Line
            });

            address += size;
        }

        return new JsonObject { ["instructions"] = instructions.ToJsonArray() };
    }

    /// <summary>
    ///  Finds where to start disassembling so a given number of instructions end at an address: the earliest
    ///  start, within reach, whose instructions land exactly on it.
    /// </summary>
    /// <param name="memory">The memory to decode: the CPU's, or a bank's.</param>
    /// <param name="address">The address the instructions end at.</param>
    /// <param name="count">The instructions wanted before it.</param>
    /// <param name="missing">How many fewer than that there are, such as near $0000.</param>
    /// <returns>The address of the first instruction.</returns>
    private int Before(IDebugMemory memory, int address, int count, out int missing)
    {
        for (int from = Math.Max(0, address - count * LongestInstruction); from < address; from++)
        {
            List<int> starts = [];
            int at = from;
            while (at < address)
            {
                starts.Add(at);
                at += Decode(memory, at).Size;
            }

            if (at != address) { continue; }
            missing = Math.Max(0, count - starts.Count);
            return starts[Math.Max(0, starts.Count - count)];
        }

        missing = count;
        return address;
    }

    // Decodes the instruction at an address, or a byte that does not start one.
    private (int Size, string Text) Decode(IDebugMemory memory, int address)
    {
        Span<byte> bytes = stackalloc byte[LongestInstruction];
        int available = Math.Min(LongestInstruction, 0x10000 - address);
        for (int index = 0; index < available; index++) { bytes[index] = memory.Peek((ushort)(address + index)); }
        return Disassembler.TryDecode(bytes[..available], (ushort)address, Target.InstructionSet, out DisassembledInstruction instruction)
            ? (instruction.Size, instruction.ToString())
            : (1, $".byte ${bytes[0]:X2}");
    }

    // The label at exactly an address, from the module that applies there.
    private string? Symbol(IDebugMemory memory, ushort address)
    {
        foreach (IDebugModule module in _debug.Modules)
        {
            if (!DebugInfo.Active(module, memory, address) || module.Position(memory, address) is null) { continue; }
            return module.Label(address) is { } label && module.TryResolve(label, out long value) && value == address
                ? label
                : null;
        }

        return null;
    }
}
