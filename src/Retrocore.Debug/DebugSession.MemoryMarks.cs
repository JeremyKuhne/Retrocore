// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using Retrocore.Assembler;
using Retrocore.Isa;
using System.Text.Json.Nodes;

namespace Retrocore.Debug;

// retro/memory/mark: Retrocore Memory's marks, names and comments, kept in the launch's hints file.
internal sealed partial class DebugSession
{
    // The hints file marks are kept in, or null where the launch names none and has no program or source to put one
    // beside, until the first mark chooses one; and what it holds.
    private string? _hintsPath;
    private MemoryHints _hints = MemoryHints.Empty;

    // The space a memory view's marks are kept under: its bank's name, or empty for memory as the CPU maps it.
    private static string HintSpace(DebugMemoryBank? bank) => bank?.Name ?? "";

    // Finds and reads a launch's hints file: its hints setting, or <name>.hints.json beside its program or source.
    private void LoadHints(JsonObject args, string? sourceFile, string? program)
    {
        string? beside = sourceFile ?? program ?? args.String("debugFile");
        string? path = args.String("hints") ?? (beside is null ? null : Path.ChangeExtension(beside, ".hints.json"));
        _hintsPath = path is null ? null : Path.GetFullPath(path);
        _hints = MemoryHints.Empty;
        if (_hintsPath is null) { return; }
        try
        {
            _hints = ReadHints(_hintsPath);
        }
        catch (InvalidDataException exception)
        {
            Notify("output", new JsonObject
            {
                ["category"] = "console",
                ["output"] = exception.Message + " Marks are left out until it is fixed.\n"
            });
        }
    }

    // Reads a hints file, or nothing where there is none yet.
    private static MemoryHints ReadHints(string path)
    {
        if (!File.Exists(path)) { return MemoryHints.Empty; }
        try
        {
            return MemoryHints.Read(path);
        }
        catch (Exception exception) when (exception is System.Text.Json.JsonException
            or IOException
            or UnauthorizedAccessException
            or InvalidOperationException
            or FormatException
            or OverflowException
            or InvalidDataException)
        {
            throw new InvalidDataException($"The hints file {path} could not be read: {exception.Message}", exception);
        }
    }

    /// <summary>
    ///  Answers retro/memory/mark: marks a range as code, data or neither, or names or comments on an address, and
    ///  writes the hints file.
    /// </summary>
    /// <remarks>
    ///  <para>
    ///   One of <c>kind</c> (<c>code</c>, <c>data</c> or <c>clear</c>, for <c>count</c> bytes from <c>address</c>),
    ///   <c>name</c> or <c>comment</c>; an empty name or comment takes it away. Code marked takes its instruction's
    ///   bytes out of data, and data marked takes out code whose instruction runs into it.
    ///  </para>
    ///  <para>
    ///   The mark is made to the file as it is now, so marks made elsewhere, or edits to it, are kept; a file that
    ///   cannot be read is left alone, and the mark fails. A launch with no file to keep marks in answers
    ///   <c>needsFile</c> and marks nothing until a request gives one as <c>hints</c>. Otherwise the answer gives
    ///   the file's <c>path</c> and the <c>address</c> and <c>count</c> of the bytes the mark covers, a code mark's
    ///   being its instruction's.
    ///  </para>
    /// </remarks>
    private JsonObject MemoryMark(JsonObject args)
    {
        MemoryReference(Required(args, "memoryReference"), out DebugMemoryBank? bank);
        int address = args.Int("address") ?? throw new ArgumentException("address is required.");
        int count = args.Int("count") ?? 1;
        if (address is < 0 or > 0xFFFF || count < 1 || address + count > 0x10000)
        {
            throw new ArgumentOutOfRangeException(nameof(args), "A mark covers 1 or more bytes in $0000-$FFFF.");
        }

        string? path = _hintsPath ?? (args.String("hints") is { Length: > 0 } chosen ? Path.GetFullPath(chosen) : null);
        if (path is null) { return new JsonObject { ["needsFile"] = true }; }

        // The edit is made to a fresh copy and kept only once it is written.
        MemoryHints hints = ReadHints(path);
        string space = HintSpace(bank);
        if (args.String("kind") is { } kind)
        {
            hints.Mark(space, address, count, kind, at => InstructionSize(bank, at));
            if (kind == "code") { count = InstructionSize(bank, address); }
        }
        else if (args["name"] is not null)
        {
            string name = (args.String("name") ?? "").Trim();
            NameUnused(bank, address, name);
            hints.Name(space, address, name);
        }
        else if (args["comment"] is not null)
        {
            hints.Comment(space, address, (args.String("comment") ?? "").Trim());
        }
        else
        {
            throw new ArgumentException("A mark gives kind, name or comment.");
        }

        hints.Write(path);
        _hintsPath = path;
        _hints = hints;
        return new JsonObject { ["path"] = path, ["address"] = address, ["count"] = count };
    }

    // Refuses a name a source's label or the machine's constant has at another address in the space, which would make
    // two addresses' operands read alike.
    private void NameUnused(DebugMemoryBank? bank, int address, string name)
    {
        if (name.Length == 0) { return; }
        IDebugMemory memory = bank is null ? Target : new BankMemory(bank);
        foreach ((int other, string taken) in LabelsAndNames(bank, memory).Names)
        {
            if (other != address && string.Equals(taken, name, StringComparison.Ordinal))
            {
                throw new ArgumentException($"${other:X4} is already named {name}.", nameof(name));
            }
        }
    }

    /// <summary>
    ///  Answers retro/memory/note: the <c>name</c> and <c>comment</c> the hints file gives an address now, or null.
    /// </summary>
    private JsonObject MemoryNote(JsonObject args)
    {
        MemoryReference(Required(args, "memoryReference"), out DebugMemoryBank? bank);
        int address = args.Int("address") ?? throw new ArgumentException("address is required.");
        string space = HintSpace(bank);
        MemoryHints hints = _hintsPath is null ? _hints : ReadHints(_hintsPath);
        return new JsonObject
        {
            ["name"] = hints.Names(space).TryGetValue(address, out string? name) ? name : null,
            ["comment"] = hints.Comments(space).TryGetValue(address, out string? comment) ? comment : null
        };
    }

    /// <summary>
    ///  Answers retro/memory/starts: which of an editor's Decode from here <c>starts</c> a mark of <c>count</c>
    ///  bytes at <c>address</c> leaves, taking out each whose instruction is in those bytes or runs into them, except
    ///  a code mark's own (<c>keep</c>).
    /// </summary>
    private JsonObject MemoryStarts(JsonObject args)
    {
        MemoryReference(Required(args, "memoryReference"), out DebugMemoryBank? bank);
        int address = args.Int("address") ?? throw new ArgumentException("address is required.");
        int end = address + (args.Int("count") ?? 1);
        int? keep = args.Int("keep");
        JsonArray kept = [];
        foreach (JsonNode? node in args["starts"] as JsonArray ?? [])
        {
            if (node?.GetValue<int>() is not int start || start is < 0 or > 0xFFFF) { continue; }
            bool covered = start < end && start + InstructionSize(bank, start) > address;
            if (start == keep || !covered) { kept.Add((JsonNode)start); }
        }

        return new JsonObject { ["starts"] = kept };
    }

    // The bytes of the instruction at an address of a space, or 1 where none decodes.
    private int InstructionSize(DebugMemoryBank? bank, int address)
    {
        InstructionSet set = bank?.InstructionSet ?? Target.InstructionSet;
        Span<byte> bytes = stackalloc byte[LongestInstruction];
        int available = 0;
        while (available < Math.Min(LongestInstruction, 0x10000 - address) && MemoryByte(bank, address + available) is { } value)
        {
            bytes[available++] = value;
        }

        return Disassembler.TryDecode(bytes[..available], (ushort)address, set, out DisassembledInstruction instruction)
            ? instruction.Size
            : 1;
    }
}
