// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using Retrocore.Isa;
using System.Globalization;
using System.Text.Json.Nodes;
using System.Text.RegularExpressions;

namespace Retrocore.Debug;

// Memory views: readMemory and writeMemory, the memory banks a reference can name, and the memory events that keep
// open views current.
internal sealed partial class DebugSession
{
    // The menu context of a variable that holds an address, which Open in Retrocore Memory shows on. VS Code's own
    // memory icon, which opens only the Hex Editor, shows on anything with a memory reference, so the variables and
    // the watch and hover values VS Code is sent have none: retro/memory/variable and other evaluates give it.
    private const string MemoryMenu = "memory";

    /// <summary>
    ///  Takes the memory references out of variables bound for VS Code's views, marking those that had one for
    ///  Open in Retrocore Memory instead.
    /// </summary>
    /// <param name="variables">A variables response.</param>
    /// <returns>The same response.</returns>
    private static JsonObject WithoutMemoryReferences(JsonObject variables)
    {
        foreach (JsonObject variable in (variables["variables"] as JsonArray ?? []).OfType<JsonObject>())
        {
            JsonNode? reference = variable["memoryReference"];
            variable.Remove("memoryReference");
            if (reference is not null)
            {
                variable["__vscodeVariableMenuContext"] = MemoryMenu;
            }
        }

        return variables;
    }

    /// <summary>
    ///  The evaluate context Retrocore Memory resolves addresses with, which gets memory references.
    /// </summary>
    private const string AddressContext = "retrocore";

    /// <summary>
    ///  An evaluate result, without its memory reference for the Watch view and hovers, which would show VS Code's
    ///  Hex Editor icon on it; Open in Retrocore Memory evaluates with its own context.
    /// </summary>
    /// <param name="args">The evaluate request's arguments.</param>
    /// <param name="result">The result.</param>
    /// <returns>The result.</returns>
    private static JsonObject Evaluated(JsonObject args, JsonObject result)
    {
        if (args.String("context") is "watch" or "hover" or "variables")
        {
            result.Remove("memoryReference");
        }

        return result;
    }

    /// <summary>
    ///  Answers retro/memory/variable: the memory reference of a variable VS Code was sent without one, by the
    ///  variables reference of its container and its name, for Open in Retrocore Memory.
    /// </summary>
    /// <param name="args">The request's arguments.</param>
    /// <returns>The variable's memory reference.</returns>
    private JsonObject MemoryVariable(JsonObject args)
    {
        string name = Required(args, "name");
        JsonArray variables = Variables(args.Int("variablesReference") ?? 0)["variables"] as JsonArray ?? [];
        string? reference = variables.OfType<JsonObject>()
            .FirstOrDefault(variable => variable["name"]?.GetValue<string>() == name)?["memoryReference"]?.GetValue<string>();

        return new JsonObject
        {
            ["memoryReference"] = reference ?? throw new InvalidOperationException($"{name} does not hold an address.")
        };
    }

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
    ///  Answers retro/memory/read: the bytes of a range with every unreadable run marked, for Retrocore Memory.
    /// </summary>
    /// <remarks>
    ///  <para>
    ///   Unlike readMemory, which stops at the first unreadable byte, this reads past gaps, so a view of a bank
    ///   such as bank 1 at $D000-$DFFF shows the bank where it is. Unreadable bytes read as zero. The view is
    ///   tracked as readMemory's are, so memory events name its reference when its bytes change.
    ///  </para>
    /// </remarks>
    private JsonObject ReadMemoryRange(JsonObject args)
    {
        string reference = Required(args, "memoryReference");
        long address = MemoryReference(reference, out DebugMemoryBank? bank);
        long offset = args.Long("offset") ?? 0;
        int count = args.Int("count") ?? 0;
        if (count is < 0 or > 0x10000)
        {
            throw new ArgumentOutOfRangeException(nameof(args), "count must be 0-65536.");
        }

        byte[] data = new byte[count];
        MemoryRuns unreadable = new();
        MemoryRuns readOnly = new();
        for (int index = 0; index < count; index++)
        {
            long at = address + offset + index;
            byte? value = MemoryByte(bank, at);
            data[index] = value ?? 0;
            unreadable.Add(index, value is null);
            readOnly.Add(index, value is not null && !Writable(bank, (ushort)at));
        }

        Track(reference, bank, address, offset, count);
        return new JsonObject
        {
            ["address"] = $"0x{address + offset:X4}",
            ["data"] = Convert.ToBase64String(data),
            ["unreadable"] = unreadable.End(count),
            ["readOnly"] = readOnly.End(count)
        };
    }

    /// <summary>
    ///  Answers retro/memory/labels: the labels in a memory view's space, from the debug modules that apply at each
    ///  address now, for Retrocore Memory's gutter and inspector.
    /// </summary>
    /// <remarks>
    ///  <para>
    ///   A label counts where its module's code or data is in memory now, as the call stack and disassembly decide,
    ///   so a ROM's labels go when the language card maps RAM over it. An address takes the first module's label,
    ///   and within a module the first name in order. Constants the CPU's instructions address memory through, such
    ///   as the Monitor's <c>CH</c> at $24, name the bytes no label does, whatever is mapped there.
    ///  </para>
    /// </remarks>
    private JsonObject MemoryLabels(JsonObject args)
    {
        MemoryReference(Required(args, "memoryReference"), out DebugMemoryBank? bank);
        SortedDictionary<int, string> labels = LabelsIn(bank, constants: true);
        return new JsonObject
        {
            ["labels"] = labels.Select(pair => (JsonNode?)new JsonObject
            {
                ["address"] = pair.Key,
                ["name"] = pair.Value
            }).ToJsonArray()
        };
    }

    // Whether a module's code is installed: in the bank that holds its area, such as the system ROM while the language
    // card's RAM is mapped over it, or in memory as the CPU maps it for code in no area; a card's firmware with no
    // card in its slot has no bank and is not.
    private bool Installed(IDebugModule module)
    {
        if (module.Area is not { } area) { return module.InMemory(Target); }
        foreach (DebugMemoryBank bank in Target.Banks)
        {
            foreach ((ushort start, int _) in bank.Ranges)
            {
                if (Equals(bank.AreaOf(start), area)) { return module.InMemory(new BankMemory(bank)); }
            }
        }

        return module.InMemory(Target);
    }

    // The labels in a space, by address, from the debug modules that apply at each address now, and with constants
    // the equates its CPU's instructions address memory through.
    private SortedDictionary<int, string> LabelsIn(DebugMemoryBank? bank, bool constants)
    {
        IDebugMemory memory = bank is null ? Target : new BankMemory(bank);
        SortedDictionary<int, string> labels = [];
        foreach (IDebugModule module in _debug.Modules)
        {
            foreach ((string name, long value) in module.Labels)
            {
                if (value is < 0 or > 0xFFFF || labels.ContainsKey((int)value)) { continue; }
                ushort address = (ushort)value;
                if (bank is not null && bank.AreaOf(address) is null) { continue; }
                if (DebugInfo.Active(module, memory, address) && module.LabelApplies(memory, address))
                {
                    labels[address] = name;
                }
            }
        }

        // Then the constants the CPU's instructions address memory through, such as the Monitor's CH, which name RAM
        // rather than code, so they apply whatever is mapped there, while the code that uses them is in memory; a
        // label at the same address comes first.
        if (!constants) { return labels; }
        IsaDescription cpu = (bank?.InstructionSet ?? Target.InstructionSet).Description;
        foreach (IDebugModule module in _debug.Modules)
        {
            if (!module.AddressConstants.Any() || !Installed(module)) { continue; }
            foreach ((string name, long value, IsaDescription constantCpu) in module.AddressConstants)
            {
                if (!ReferenceEquals(constantCpu, cpu) || value is < 0 or > 0xFFFF || labels.ContainsKey((int)value))
                {
                    continue;
                }

                if (bank is not null && bank.AreaOf((ushort)value) is null) { continue; }
                labels[(int)value] = name;
            }
        }

        return labels;
    }

    /// <summary>
    ///  Answers retro/memory/characters: the machine's character set as its screen shows it now, so Retrocore
    ///  Memory's text column draws the machine's own characters.
    /// </summary>
    /// <remarks>
    ///  <para>
    ///   <c>glyphs</c> holds each code's rows in turn, one byte a row with the leftmost pixel in bit 7, and
    ///   <c>flashed</c> the same for the other phase of flashing characters, when there are any. <c>text</c> is the
    ///   character each code shows, NUL for graphics. A machine the debugger cannot draw gives no character set.
    ///  </para>
    /// </remarks>
    private JsonObject MemoryCharacters()
    {
        if (Target.CharacterSet is not { } characters) { return []; }
        int width = Math.Min(characters.CharacterWidth, 8);
        int height = characters.CharacterHeight;
        byte[] glyphs = new byte[256 * height];
        byte[] flashed = new byte[256 * height];
        char[] text = new char[256];
        for (int code = 0; code < 256; code++)
        {
            text[code] = characters.Character((byte)code);
            for (int line = 0; line < height; line++)
            {
                for (int pixel = 0; pixel < width; pixel++)
                {
                    byte bit = (byte)(0x80 >> pixel);
                    int row = (code * height) + line;
                    if (characters.IsLit((byte)code, line, pixel, flashed: false)) { glyphs[row] |= bit; }
                    if (characters.IsLit((byte)code, line, pixel, flashed: true)) { flashed[row] |= bit; }
                }
            }
        }

        return new JsonObject
        {
            ["width"] = width,
            ["height"] = height,
            ["glyphs"] = Convert.ToBase64String(glyphs),
            ["flashed"] = glyphs.AsSpan().SequenceEqual(flashed) ? null : Convert.ToBase64String(flashed),
            ["text"] = new string(text)
        };
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
    private IEnumerable<(string? Name, string Label, string Reference, bool ReadOnly, string Reads, string Writes, bool Coprocessor, bool BigEndian)> MemoryBanks()
    {
        bool big = Target.InstructionSet.Endianness == Endianness.Big;
        yield return (null, "Memory as the CPU maps it now", Reference(bank: null, 0), false, "$0000-$FFFF", "$0000-$FFFF", false, big);
        foreach (DebugMemoryBank bank in Target.Banks)
        {
            yield return (
                bank.Name,
                bank.Label,
                Reference(bank, bank.Ranges[0].Start),
                bank.Poke is null,
                Mapped(bank, write: false),
                bank.Poke is null ? "" : Mapped(bank, write: true),
                bank.InstructionSet is not null,
                bank.InstructionSet is { } isa ? isa.Endianness == Endianness.Big : big);
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
            ["writes"] = bank.ReadOnly ? null : bank.Writes,
            ["coprocessor"] = bank.Coprocessor,
            ["bigEndian"] = bank.BigEndian
}).ToJsonArray()
    };

    // Hex digits after 0x, or alone when they start with a digit, so a label such as BEEF stays a label.
    [GeneratedRegex(@"^(?:0[xX](?<digits>[0-9a-fA-F]+)|(?<digits>[0-9][0-9a-fA-F]*))$")]
    private static partial Regex HexReference();
}
