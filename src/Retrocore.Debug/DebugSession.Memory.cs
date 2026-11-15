// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using System.Globalization;
using System.Text.RegularExpressions;
using System.Text.Json.Nodes;

namespace Retrocore.Debug;

// Memory views: readMemory and writeMemory, the memory banks a reference can name, and the memory events that keep
// open views current.
internal sealed partial class DebugSession
{
    // The variables reference of the Memory scope, which lists the CPU's memory and the machine's banks.
    private const int BanksScope = 99999;

    // The most memory references to keep sending memory events for.
    private const int MemoryViewLimit = 32;

    // The memory views that have read, oldest first, each by its reference as the view gave it: a memory event must
    // name a view's reference exactly for VS Code to refresh it.
    private readonly List<MemoryView> _memoryViews = [];

    // Running frames since the last memory events, which go out every few frames while the machine runs.
    private int _memoryFrames;

    /// <summary>
    ///  Resolves a memory reference: an address, which may name a bank first, such as <c>0x0400</c>,
    ///  <c>aux:0x0400</c> or <c>aux:TEXT_PAGE</c>.
    /// </summary>
    /// <remarks>
    ///  <para>
    ///   Digits alone are hex, as in the references the debugger hands out, and anything else is an expression,
    ///   for references typed into a memory view.
    ///  </para>
    /// </remarks>
    /// <param name="reference">The reference.</param>
    /// <param name="bank">The bank it names, or null for memory as the CPU maps it now.</param>
    /// <returns>The address, which may be outside the CPU's 64K.</returns>
    private long MemoryReference(string reference, out DebugMemoryBank? bank)
    {
        string address = ExpressionEvaluator.SplitBank(Target, reference.Trim(), out bank).Trim();
        if (HexReference().Match(address) is { Success: true } hex)
        {
            return long.Parse(hex.Groups["digits"].Value, NumberStyles.HexNumber, CultureInfo.InvariantCulture);
        }

        return new ExpressionEvaluator(Target, _debug, address).Evaluate();
    }

    // The reference that names an address, in a bank or as the CPU maps it.
    // The prefix an instruction address carries in its own address space: a coprocessor's bank, which has its own
    // instruction set, such as z80:; none for the machine CPU's, whose banks are views of its own addresses.
    private static string SpaceOf(DebugMemoryBank? bank) => bank?.InstructionSet is null ? "" : $"{bank.Name}:";

    private static string Reference(DebugMemoryBank? bank, int address) =>
        bank is null ? $"0x{address:X4}" : $"{bank.Name}:0x{address:X4}";

    // A byte of a bank, or of memory as the CPU maps it; null where there is none.
    private byte? MemoryByte(DebugMemoryBank? bank, long address)
    {
        if (address is < 0 or > 0xFFFF) { return null; }
        return bank is null ? Target.Peek((ushort)address) : bank.Peek((ushort)address);
    }

    /// <summary>
    ///  Answers readMemory: the bytes from a reference without side effects, up to the first that cannot be read,
    ///  such as one outside a bank or the CPU's 64K, with the rest of the request as unreadable bytes.
    /// </summary>
    private JsonObject ReadMemory(JsonObject args)
    {
        string reference = Required(args, "memoryReference");
        long address = MemoryReference(reference, out DebugMemoryBank? bank);
        long offset = args.Long("offset") ?? 0;
        long start = address + offset;
        int count = (args.Int("count") ?? 0);
        if (count is < 0 or > 0x10000)
        {
            throw new ArgumentOutOfRangeException(nameof(args), "count must be 0-65536.");
        }

        // Everything after the first unreadable byte counts as unreadable, as VS Code takes the unreadable bytes to
        // be the end of what it asked for; it asks again past them.
        List<byte> data = [];
        for (int index = 0; index < count && MemoryByte(bank, start + index) is { } value; index++) { data.Add(value); }
        int unreadable = count - data.Count;
        Track(reference, bank, address, offset, count);

        JsonObject response = new JsonObject
        {
            ["address"] = $"0x{Math.Clamp(start, 0, 0xFFFF):X4}",
            ["data"] = Convert.ToBase64String([.. data])
        };

        if (unreadable != 0) { response["unreadableBytes"] = unreadable; }
        return response;
    }

    /// <summary>
    ///  Answers writeMemory: writes RAM at a reference, in a bank or where the CPU reads it now.
    /// </summary>
    /// <remarks>
    ///  <para>
    ///   Without <c>allowPartial</c>, a write that cannot finish, such as one reaching ROM, changes nothing. Other
    ///   views can show the bytes written under another reference, so they are told to read again.
    ///  </para>
    /// </remarks>
    private JsonObject WriteMemory(JsonObject args)
    {
        string reference = Required(args, "memoryReference");
        long start = MemoryReference(reference, out DebugMemoryBank? bank) + (args.Long("offset") ?? 0);
        byte[] bytes = Convert.FromBase64String(Required(args, "data"));
        bool partial = args.Bool("allowPartial") ?? false;
        List<(ushort Address, byte Old)> written = [];
        string? failure = null;
        for (int index = 0; index < bytes.Length && failure is null; index++)
        {
            long address = start + index;
            if (MemoryByte(bank, address) is not { } old)
            {
                failure = bank is null
                    ? "The bytes must be within the CPU's 64K."
                    : $"{bank.Label} has no byte at ${address:X4}.";
            }
            else if (bank is null)
            {
                try
                {
                    Target.Poke((ushort)address, bytes[index]);
                    written.Add(((ushort)address, old));
                }
                catch (ArgumentException exception)
                {
                    failure = exception.Message;
                }
            }
            else if (bank.Poke is null)
            {
                failure = $"{bank.Label} is read-only.";
            }
            else if (bank.Poke((ushort)address, bytes[index]))
            {
                written.Add(((ushort)address, old));
            }
            else
            {
                failure = $"{bank.Label} has no byte at ${address:X4}.";
            }
        }

        if (failure is not null && (!partial || written.Count == 0))
        {
            // Put back what was written, so the write changes nothing.
            foreach ((ushort address, byte old) in written)
            {
                if (bank is null) { Target.Poke(address, old); }
                else { bank.Poke?.Invoke(address, old); }
            }

            throw new ArgumentException(failure);
        }

        Invalidate();
        NotifyMemory(except: reference);
        Notify("invalidated", new JsonObject { ["areas"] = new JsonArray("variables") });
        return new JsonObject { ["bytesWritten"] = written.Count };
    }

    // Notes what a memory view has read, for the memory events that refresh it: the bytes from the lowest offset
    // it has read to the highest, and what they are now.
    private void Track(string reference, DebugMemoryBank? bank, long address, long offset, int count)
    {
        MemoryView? view = _memoryViews.Find(item => item.Reference == reference);
        if (view is null)
        {
            view = new(reference) { First = offset, End = offset + count };
            _memoryViews.Add(view);
            if (_memoryViews.Count > MemoryViewLimit) { _memoryViews.RemoveAt(0); }
        }
        else if (view.Bank != bank || view.Address != address)
        {
            // An expression such as HL that now resolves elsewhere: the view starts over there.
            view.First = offset;
            view.End = offset + count;
        }
        else
        {
            view.First = Math.Min(view.First, offset);
            view.End = Math.Max(view.End, offset + count);
        }

        view.Bank = bank;
        view.Address = address;
        view.Seen = Hash(view);
    }

    // A hash of the bytes a view has read, as they are now, with unreadable bytes apart from every value.
    private ulong Hash(MemoryView view)
    {
        ulong hash = 14695981039346656037;
        for (long offset = view.First; offset < view.End; offset++)
        {
            hash = (hash ^ (ulong)(MemoryByte(view.Bank, view.Address + offset) ?? 0x100)) * 1099511628211;
        }

        return hash;
    }

    // Tells each memory view whose bytes changed since it last saw them to read again; the view that just wrote
    // knows what it wrote.
    private void NotifyMemory(string? except = null)
    {
        _memoryFrames = 0;
        NotifyBasic();
        foreach (MemoryView view in _memoryViews)
        {
            ulong hash = Hash(view);
            if (hash == view.Seen) { continue; }
            view.Seen = hash;
            if (view.Reference == except) { continue; }

            // The range starts at zero: VS Code 1.100 takes count as the end offset when it invalidates a region.
            Notify("memory", new JsonObject
            {
                ["memoryReference"] = view.Reference,
                ["offset"] = 0,
                ["count"] = Math.Max(view.End, 0)
            });
        }
    }

    // Checks the memory views every eighth running frame, about four times a second.
    private void NotifyRunningMemory()
    {
        if (++_memoryFrames >= 8) { NotifyMemory(); }
    }

    /// <summary>
    ///  Lists the CPU's memory and the machine's banks: each one's memory reference, and where the memory map
    ///  reads and writes it now.
    /// </summary>
    private IEnumerable<(string? Name, string Label, string Reference, bool ReadOnly, string Reads, string Writes)> MemoryBanks()
    {
        yield return (null, "Memory as the CPU maps it now", Reference(bank: null, 0), false, "$0000-$FFFF", "$0000-$FFFF");
        foreach (DebugMemoryBank bank in Target.Banks)
        {
            yield return (
                bank.Name,
                bank.Label,
                Reference(bank, bank.Ranges[0].Start),
                bank.Poke is null,
                Mapped(bank, write: false),
                bank.Poke is null ? "" : Mapped(bank, write: true));
        }
    }

    // Where the memory map reads or writes a bank now, such as "$0000-$01FF, $0400-$07FF", or "nowhere".
    private string Mapped(DebugMemoryBank bank, bool write)
    {
        List<string> runs = [];
        foreach ((ushort start, int length) in bank.Ranges)
        {
            int? first = null;
            for (int address = start; address <= start + length; address++)
            {
                bool mapped = address < start + length
                    && bank.Areas.Contains(write ? Target.WriteArea((ushort)address) : Target.ReadArea((ushort)address));

                if (mapped)
                {
                    first ??= address;
                }
                else if (first is { } from)
                {
                    runs.Add($"${from:X4}-${address - 1:X4}");
                    first = null;
                }
            }
        }

        return runs.Count == 0 ? "nowhere" : string.Join(", ", runs);
    }

    // The Memory scope: the CPU's memory and each bank, with the memory reference that opens it in a memory view.
    private JsonObject BankVariables()
    {
        List<JsonNode?> variables = [];
        foreach ((string? name, string label, string reference, bool readOnly, string reads, string writes) in MemoryBanks())
        {
            string value = name is null
                ? $"{label}: $0000-$FFFF"
                : readOnly ? $"{label}: read at {reads}" : $"{label}: read at {reads}; written at {writes}";

            variables.Add(new JsonObject
            {
                ["name"] = name ?? "CPU",
                ["value"] = value,
                ["variablesReference"] = 0,
                ["memoryReference"] = reference,
                ["presentationHint"] = readOnly ? new JsonObject
                {
                    ["attributes"] = new JsonArray("readOnly")
                } : null
            });
        }

        return new JsonObject { ["variables"] = variables.ToJsonArray() };
    }

    // Answers retro/memoryBanks, for the extension's Open Memory command.
    private JsonObject MemoryBankList() => new JsonObject
    {
        ["banks"] = MemoryBanks().Select(bank => new JsonObject
{
            ["name"] = bank.Name,
            ["label"] = bank.Label,
            ["memoryReference"] = bank.Reference,
            ["readOnly"] = bank.ReadOnly,
            ["reads"] = bank.Reads,
            ["writes"] = bank.ReadOnly ? null : bank.Writes
}).ToJsonArray()
    };

    // Hex digits after 0x, or alone when they start with a digit, so a label such as BEEF stays a label.
    [GeneratedRegex(@"^(?:0[xX](?<digits>[0-9a-fA-F]+)|(?<digits>[0-9][0-9a-fA-F]*))$")]
    private static partial Regex HexReference();
}
