// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using Retrocore.Documentation;
using System.Globalization;

namespace Retrocore.Debug;

/// <summary>
///  Checks documented <c>Keeps:</c> (and optionally <c>Uses:</c>) contracts when calls return.
/// </summary>
/// <remarks>
///  <para>
///   A call is the JSR to a documented routine; it returns when the PC reaches the JSR's address + 3 with the
///   stack back at its depth, as for call cycle counts. A stack reset abandons the calls it discards.
///  </para>
/// </remarks>
internal sealed class DebugContracts
{
    private const int MaximumPending = 256;

    private readonly Func<ushort, DebugContract?> _lookup;
    private readonly bool _checkChanges;
    private readonly DebugRegisters _registers;
    private readonly IReadOnlyList<string> _used;
    private readonly List<(DebugContract Contract, ushort Return, int Stack, DebugFrame Registers, byte[] Memory)> _pending = [];

    /// <summary>
    ///  Creates the checker.
    /// </summary>
    /// <param name="lookup">Gets the contract of the routine at an address, or null.</param>
    /// <param name="checkChanges">Whether to report registers changed that <c>Uses:</c> does not list.</param>
    /// <param name="registers">The CPU's registers and flags by name.</param>
    /// <param name="used">The registers <c>Uses:</c> accounts for.</param>
    internal DebugContracts(Func<ushort, DebugContract?> lookup, bool checkChanges, DebugRegisters registers, IReadOnlyList<string> used)
    {
        _registers = registers;
        _used = used;
        _lookup = lookup;
        _checkChanges = checkChanges;
    }

    /// <summary>
    ///  Forgets pending calls.
    /// </summary>
    internal void Clear() => _pending.Clear();

    /// <summary>
    ///  Gets whether observing an instruction can change anything: it makes a call, or its stack is back where a
    ///  pending call's was. Otherwise <see cref="Observe"/> neither reads the registers nor reports anything.
    /// </summary>
    /// <param name="stack">The stack pointer before the instruction.</param>
    /// <param name="call">Whether the instruction makes a call.</param>
    /// <returns>Whether to observe the instruction.</returns>
    internal bool Observes(int stack, bool call) => call || (_pending.Count != 0 && stack >= _pending[^1].Stack);

    /// <summary>
    ///  Observes an instruction boundary.
    /// </summary>
    /// <param name="registers">The registers before the instruction.</param>
    /// <param name="call">The call the instruction makes, or null.</param>
    /// <param name="peek">Reads memory without side effects.</param>
    /// <returns>The broken promises of a call that returned here, or none.</returns>
    internal IReadOnlyList<string> Observe(in DebugFrame registers, (ushort Target, int Length)? call, Func<ushort, byte> peek)
    {
        // Most instructions return no call, so they share the empty list rather than each allocating one.
        IReadOnlyList<string> broken = [];
        ushort pc = registers.ProgramCounter;
        int stack = registers.StackPointer;
        while (_pending.Count != 0 && stack >= _pending[^1].Stack)
        {
            (DebugContract contract, ushort returnAddress, int callStack, DebugFrame entry, byte[] memory) = _pending[^1];
            _pending.RemoveAt(_pending.Count - 1);
            if (stack == callStack && pc == returnAddress)
            {
                if (Compare(contract, entry, registers, memory, peek) is { } found) { broken = found; }
                break;
            }
        }

        if (call is ({ } target, int callLength) && _pending.Count < MaximumPending)
        {
            if (_lookup(target) is { } contract)
            {
                List<byte> memory = [];
                foreach ((_, ushort address, int length) in contract.Memory)
                {
                    for (int offset = 0; offset < length; offset++) { memory.Add(peek((ushort)(address + offset))); }
                }

                _pending.Add((contract, (ushort)(pc + callLength), stack, registers, [.. memory]));
            }
        }

        return broken;
    }

    // The promises a call broke, or null when it kept them all, so a kept call allocates nothing.
    private List<string>? Compare(
        DebugContract contract,
        in DebugFrame entry,
        in DebugFrame exit,
        byte[] memory,
        Func<ushort, byte> peek)
    {
        List<string>? broken = null;
        void Report(string item, long before, long after) =>
            (broken ??= []).Add(string.Create(
                CultureInfo.InvariantCulture,
                $"{contract.Routine} returned with {item} changed: ${before:X2} at entry, ${after:X2} at return. Its documentation says it keeps {item}."));

        foreach (string register in contract.Registers)
        {
            (long before, long after) = Value(register, entry, exit);
            if (before != after) { Report(register, before, after); }
        }

        int offset = 0;
        foreach ((string name, ushort address, int length) in contract.Memory)
        {
            for (int index = 0; index < length; index++)
            {
                byte now = peek((ushort)(address + index));
                if (now != memory[offset + index])
                {
                    Report(length == 1 ? name : $"{name}+{index}", memory[offset + index], now);
                    break;
                }
            }

            offset += length;
        }

        if (!_checkChanges || contract.Changes is not { } changes) { return broken; }
        foreach (string register in _used)
        {
            if (changes.Contains(register) || contract.Registers.Contains(register)) { continue; }
            (long before, long after) = Value(register, entry, exit);
            if (before != after)
            {
                (broken ??= []).Add(string.Create(
                    CultureInfo.InvariantCulture,
                    $"{contract.Routine} changed {register} (${before:X2} to ${after:X2}), which its documentation does not list."));
            }
        }

        return broken;
    }

    private (long Before, long After) Value(string register, in DebugFrame entry, in DebugFrame exit) =>
        (_registers.Kept(entry, register) ?? 0, _registers.Kept(exit, register) ?? 0);

    /// <summary>
    ///  Builds the contracts of every documented routine in a module.
    /// </summary>
    /// <param name="resolver">The module's documentation resolver.</param>
    /// <param name="model">The launched model, such as <c>Enhanced</c>, for model-specific sections.</param>
    /// <param name="registers">The CPU's registers and flags, which a <c>Keeps:</c> item may name.</param>
    /// <param name="symbol">
    ///  The module's value of a symbol, or null when it does not define it, for sections under conditions such as
    ///  <c>MODEL = 1</c>.
    /// </param>
    /// <returns>Contracts by routine and entry address.</returns>
    internal static Dictionary<ushort, DebugContract> Build(
        DocumentationResolver resolver,
        string model,
        DebugRegisters registers,
        Func<string, long?>? symbol = null)
    {
        Dictionary<ushort, DebugContract> contracts = [];
        DocumentationSet set = resolver.Current;
        foreach (DocumentationTopic documented in set.Topics)
        {
            if (documented.Kind != DocumentationKind.Routine || documented.Value is not { } value) { continue; }
            DocumentationTopic topic = resolver.Effective(documented);
            bool Applies(DocumentationSection section) => DocumentationResolver.Applies(section.Condition, model, symbol);

            (List<string> kept, List<(string, ushort, int)> memory) = Kept(
                topic.SectionsNamed("Keeps").Where(Applies).SelectMany(section => section.Items).Select(WithoutNote));

            HashSet<string>? changes = null;
            if (topic.SectionsNamed("Uses").Any(Applies))
            {
                changes = [with(StringComparer.OrdinalIgnoreCase)];
                IEnumerable<string> uses = topic.SectionsNamed("Uses").Where(Applies).SelectMany(section => section.Items).Select(WithoutNote);
                changes.UnionWith(uses);
                foreach (DocumentationEntry entry in topic.SectionsNamed("Out").Where(Applies).SelectMany(section => section.Entries))
                {
                    changes.UnionWith(entry.Name.Split(['/', ','], StringSplitOptions.RemoveEmptyEntries).Select(part => part.Trim()));
                }
            }

            // An Entry: whose meaning ends in "; keeps ..." promises that instead, and no Uses:, at a call there.
            Dictionary<string, IReadOnlyList<string>> entryKeeps = [];
            foreach (DocumentationEntry entry in topic.SectionsNamed("Entry").Where(Applies).SelectMany(section => section.Entries))
            {
                if (entry.Keeps is { } keeps) { entryKeeps[set.EntrySymbol(documented, entry.Name)] = keeps; }
            }

            if (kept.Count != 0 || memory.Count != 0 || changes is not null)
            {
                contracts.TryAdd((ushort)value, new(topic.Name, kept, memory, changes));
            }

            foreach (string label in topic.EntryLabels.Select(entry => set.EntrySymbol(documented, entry)))
            {
                if (!set.Symbols.TryGetValue(label, out long entry) || set.Find(label) is not null) { continue; }
                if (entryKeeps.TryGetValue(label, out IReadOnlyList<string>? own))
                {
                    (List<string> entryKept, List<(string, ushort, int)> entryMemory) = Kept(own);
                    if (entryKept.Count != 0 || entryMemory.Count != 0)
                    {
                        contracts.TryAdd((ushort)entry, new(topic.Name, entryKept, entryMemory, Changes: null));
                    }
                }
                else if (contracts.TryGetValue((ushort)value, out DebugContract? contract))
                {
                    contracts.TryAdd((ushort)entry, contract);
                }
            }
        }

        return contracts;

        // The registers, flags and memory a Keeps: list names.
        (List<string> Kept, List<(string, ushort, int)> Memory) Kept(IEnumerable<string> items)
        {
            List<string> kept = [];
            List<(string, ushort, int)> memory = [];
            foreach (string item in items)
            {
                string upper = item.ToUpperInvariant();
                if (registers.Knows(upper))
                {
                    // Registers read in capitals; flags keep their words, as in "kept carry".
                    kept.Add(registers.IndexOf(item) >= 0 ? upper : item.ToLowerInvariant());
                }
                else if (Memory(set, item) is { } location)
                {
                    memory.Add((item, location.Address, location.Length));
                }
            }

            return (kept, memory);
        }
    }

    // A kept memory item: a symbol, symbol+n, or a range symbol..symbol+n.
    // A Uses or Keeps item without the note in parentheses that may follow it: "Y (for a sound channel)" is Y, as
    // the documentation check reads it.
    private static string WithoutNote(string item)
    {
        int note = item.IndexOf(" (", StringComparison.Ordinal);
        return note > 0 && item.EndsWith(')') ? item[..note] : item;
    }

    private static (ushort Address, int Length)? Memory(DocumentationSet set, string item)
    {
        string[] range = item.Split("..");
        if (Address(set, range[0]) is not { } start) { return null; }
        if (range.Length == 1) { return ((ushort)start, 1); }
        return Address(set, range[1]) is { } end && end >= start ? ((ushort)start, (int)(end - start + 1)) : null;
    }

    private static long? Address(DocumentationSet set, string text)
    {
        string[] parts = text.Split('+');
        if (!set.Symbols.TryGetValue(parts[0].Trim(), out long value)) { return null; }
        for (int index = 1; index < parts.Length; index++)
        {
            string number = parts[index].Trim();
            bool hex = number.StartsWith('$');
            NumberStyles style = hex ? NumberStyles.HexNumber : NumberStyles.Integer;
            if (!long.TryParse(hex ? number[1..] : number, style, CultureInfo.InvariantCulture, out long add))
            {
                return null;
            }

            value += add;
        }

        return value;
    }
}
