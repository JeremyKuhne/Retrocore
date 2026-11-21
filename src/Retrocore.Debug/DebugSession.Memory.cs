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

    // The most memory references without an editor subscriber to keep sending memory events for.
    private const int MemoryViewLimit = 32;

    // The memory views that have read, least recently used first. Live editor subscribers are not evicted.
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

        return new ExpressionEvaluator(Target, _debug, address, bank: bank).Evaluate();
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

        Track(reference, bank, address, offset, count, args.String("subscriber"));
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
    ///  <para>
    ///   Each has its <c>kind</c>: what its documentation declares it, such as <c>routine</c> or <c>table</c>; else
    ///   <c>code</c> or <c>data</c> by the statement at it, or <c>constant</c> for a constant; or null. A label on
    ///   data has the <c>size</c> of its data: the data statements, and the bytes the hints file marks as data, from
    ///   it to the next name or the first byte that is neither.
    ///  </para>
    /// </remarks>
    private JsonObject MemoryLabels(JsonObject args)
    {
        MemoryReference(Required(args, "memoryReference"), out DebugMemoryBank? bank);
        IDebugMemory memory = bank is null ? Target : new BankMemory(bank);
        (SortedDictionary<int, string> labels, SortedDictionary<int, string> names) = LabelsAndNames(bank, memory);
        IReadOnlyList<(int Start, int Length)> marked = MarkHints.Data(HintSpace(bank));
        bool Marked(int address) => marked.Any(range => address >= range.Start && address < range.Start + range.Length);

        JsonArray list = [];
        foreach ((int address, string name) in names)
        {
            DebugPosition? position = _debug.Position(memory, (ushort)address);
            bool data = position is { Data: true } || Marked(address);
            string? statement = position is not null ? "code" : labels.ContainsKey(address) ? null : "constant";
            string? kind = DocumentedKind(name, address) ?? (data ? "data" : statement);
            list.Add((JsonNode)new JsonObject
            {
                ["address"] = address,
                ["name"] = name,
                ["kind"] = kind,
                ["size"] = data ? DataSize(memory, names, address, Marked) : null
            });
        }

        return new JsonObject { ["labels"] = list };
    }

    // What a name's documentation declares it, such as routine or table, from the first module documenting it at
    // that address.
    private string? DocumentedKind(string name, int address)
    {
        foreach (IDebugModule module in _debug.Modules)
        {
            if (module.Documentation.Find(name) is { } topic && (topic.Value is null || topic.Value == address))
            {
                return topic.Kind.ToString().ToLowerInvariant();
            }
        }

        return null;
    }

    // How many bytes of data run from a name: its data statements and marked bytes, to the next name or the first
    // byte that is neither.
    private int DataSize(IDebugMemory memory, SortedDictionary<int, string> names, int address, Func<int, bool> marked)
    {
        int at = address;
        while (at <= 0xFFFF && (at == address || !names.ContainsKey(at)))
        {
            DebugPosition? position = _debug.Position(memory, (ushort)at);
            if (position is { Data: true, Start: { } start, Size: > 0 } && start + position.Size > at)
            {
                at = start + position.Size;
            }
            else if (marked(at))
            {
                at++;
            }
            else
            {
                break;
            }
        }

        // A statement can run past the next name, which then starts its own.
        int next = names.Keys.FirstOrDefault(key => key > address, 0x10000);
        return Math.Min(at, next) - address;
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
        (SortedDictionary<int, string> Labels, SortedDictionary<int, string> Names) found = LabelsAndNames(bank, memory, constants);
        return constants ? found.Names : found.Labels;
    }

    // The labels in a space, and with constants also the labels and equates together, found in one pass through
    // the modules, reading memory as given, such as a listing's, which keeps what the modules find.
    private (SortedDictionary<int, string> Labels, SortedDictionary<int, string> Names) LabelsAndNames(
        DebugMemoryBank? bank,
        IDebugMemory memory,
        bool constants = true)
    {
        SortedDictionary<int, string> labels = [];

        // The names marked in Retrocore Memory come first, as they do when disassembling.
        foreach ((int marked, string name) in MarkHints.Names(HintSpace(bank)))
        {
            if (bank is null || bank.AreaOf((ushort)marked) is not null) { labels[marked] = name; }
        }

        // Each address's first label wins, as each is skipped once named.
        foreach ((int address, string name, bool _) in SourceNames(bank, memory, SourceNameKinds.Labels, labels.ContainsKey))
        {
            labels[address] = name;
        }

        // Then the constants the CPU's instructions address memory through, such as the Monitor's CH, which name RAM
        // rather than code, so they apply whatever is mapped there, while the code that uses them is in memory; a
        // label at the same address comes first.
        if (!constants) { return (labels, labels); }
        SortedDictionary<int, string> names = [];
        foreach ((int address, string name) in labels) { names.Add(address, name); }
        foreach ((int address, string name, bool _) in SourceNames(bank, memory, SourceNameKinds.Constants, names.ContainsKey))
        {
            // A constant names what the CPU's instructions reach at its address, so in a bank's view it names the
            // bank's byte only where the CPU reads the bank there now: the Monitor's BRKV is main RAM's $03F0, not
            // auxiliary RAM's, unless the machine reads auxiliary RAM there. A coprocessor's space is its own CPU's view.
            if (bank is { InstructionSet: null } && !bank.ReadBy(Target, (ushort)address)) { continue; }
            names[address] = name;
        }

        return (labels, names);
    }

    // Each label the sources give an address in a space that applies now, and each constant the space's CPU addresses
    // memory through, as kinds asks, in the modules' order, leaving out addresses skip says are already named.
    private IEnumerable<(int Address, string Name, bool Constant)> SourceNames(
        DebugMemoryBank? bank,
        IDebugMemory memory,
        SourceNameKinds kinds,
        Func<int, bool> skip)
    {
        IEnumerable<IDebugModule> labelled = kinds.HasFlag(SourceNameKinds.Labels) ? _debug.Modules : [];
        foreach (IDebugModule module in labelled)
        {
            foreach ((string name, long value) in module.Labels)
            {
                if (value is < 0 or > 0xFFFF || skip((int)value)) { continue; }
                ushort address = (ushort)value;
                if (bank is not null && bank.AreaOf(address) is null) { continue; }
                if (DebugInfo.Active(module, memory, address) && module.LabelApplies(memory, address))
                {
                    yield return (address, name, false);
                }
            }
        }

        if (!kinds.HasFlag(SourceNameKinds.Constants)) { yield break; }
        IsaDescription cpu = (bank?.InstructionSet ?? Target.InstructionSet).Description;
        foreach (IDebugModule module in _debug.Modules)
        {
            if (!module.AddressConstants.Any() || !Installed(module)) { continue; }
            foreach ((string name, long value, IsaDescription constantCpu) in module.AddressConstants)
            {
                if (!ReferenceEquals(constantCpu, cpu) || value is < 0 or > 0xFFFF || skip((int)value)) { continue; }
                if (bank is not null && bank.AreaOf((ushort)value) is null) { continue; }
                yield return ((int)value, name, true);
            }
        }
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

    // Notes what a memory view has read, for the memory events that refresh it.
    private void Track(string reference, DebugMemoryBank? bank, long address, long offset, int count, string? subscriber = null)
    {
        MemoryView? view = _memoryViews.Find(item => item.Reference == reference && item.Subscriber == subscriber);
        if (view is null)
        {
            if (subscriber is null && _memoryViews.Count(item => item.Subscriber is null) >= MemoryViewLimit)
            {
                MemoryView oldest = _memoryViews.First(item => item.Subscriber is null);
                _memoryViews.Remove(oldest);
            }

            view = new(reference, subscriber);
        }
        else if (view.Bank != bank || view.Address != address)
        {
            // An expression such as HL that now resolves elsewhere: the view starts over there.
            view.Ranges.Clear();
            _memoryViews.Remove(view);
        }
        else { _memoryViews.Remove(view); }

        view.Bank = bank;
        view.Address = address;
        view.Add(offset, offset + count);
        view.Seen = Hash(view);
        _memoryViews.Add(view);
    }

    private JsonObject UnsubscribeMemory(JsonObject args)
    {
        string subscriber = Required(args, "subscriber");
        _memoryViews.RemoveAll(view => view.Subscriber == subscriber);
        return [];
    }

    // A hash of the bytes a view has read, as they are now, with unreadable bytes apart from every value.
    private ulong Hash(MemoryView view)
    {
        ulong hash = 14695981039346656037;
        foreach ((long first, long end) in view.Ranges)
        {
            for (long offset = first; offset < end; offset++)
            {
                hash = (hash ^ (ulong)(MemoryByte(view.Bank, view.Address + offset) ?? 0x100)) * 1099511628211;
            }
        }

        return hash;
    }

    // Tells each memory view whose bytes changed since it last saw them to read again; the view that just wrote
    // knows what it wrote.
    private void NotifyMemory(string? except = null)
    {
        _memoryFrames = 0;
        NotifyBasic();
        Dictionary<string, long>? changed = null;
        foreach (MemoryView view in _memoryViews)
        {
            ulong hash = Hash(view);
            if (hash == view.Seen) { continue; }
            view.Seen = hash;
            if (view.Reference == except) { continue; }
            changed ??= [with(StringComparer.Ordinal)];
            long end = Math.Max(view.Ranges.Count == 0 ? 0 : view.Ranges[^1].End, 0);
            changed[view.Reference] = Math.Max(changed.GetValueOrDefault(view.Reference), end);
        }

        if (changed is null) { return; }
        foreach ((string reference, long end) in changed)
        {
            // The range starts at zero: VS Code 1.100 takes count as the end offset when it invalidates a region.
            Notify("memory", new JsonObject
            {
                ["memoryReference"] = reference,
                ["offset"] = 0,
                ["count"] = end
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
                    && (write ? bank.Areas.Contains(Target.WriteArea((ushort)address)) : bank.ReadBy(Target, (ushort)address));

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
