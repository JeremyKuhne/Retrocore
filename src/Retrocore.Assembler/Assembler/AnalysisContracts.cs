// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using Retrocore.Documentation;
using Retrocore.Isa;
using Retrocore.Machines;
using System.Numerics;

namespace Retrocore.Assembler;

/// <summary>
///  Checks documented <c>Keeps:</c> and <c>Uses:</c> contracts against an assembled program's code, without
///  running it.
/// </summary>
/// <remarks>
///  <para>
///   Each documented routine with a <c>Keeps:</c> or <c>Uses:</c> section is followed by
///   <see cref="AnalysisRoutineEngine"/>. A call to a routine with a contract takes that contract, as the
///   documentation promises it to callers; a call to any other code takes that code's own analysis. A register
///   <c>Keeps:</c> lists that a path to a return changes, or, where there is a <c>Uses:</c> section, a register
///   changed that <c>Uses:</c>, <c>Out:</c> and <c>Keeps:</c> do not list, is a finding. Memory in
///   <c>Keeps:</c> is not checked yet.
///  </para>
/// </remarks>
internal sealed partial class AnalysisContracts
{
    private readonly InstructionSet _set;
    private readonly DocumentationSet _documentation;
    private readonly byte[] _memory = new byte[0x10000];
    private readonly bool[] _defined = new bool[0x10000];
    private readonly bool[] _data = new bool[0x10000];
    private readonly List<ushort> _instructions = [];
    private readonly bool[] _patched = new bool[0x10000];
    private readonly HashSet<ushort> _referenced = [];
    private readonly Dictionary<ushort, AnalysisContract> _contracts = [];
    private readonly Dictionary<ushort, DocumentationTopic> _routines = [];
    private readonly Dictionary<ushort, AnalysisRoutineSummary?> _analyzed = [];
    private readonly AnalysisRoutineEngine _engine;
    private readonly uint _general;

    /// <summary>
    ///  Prepares the check of one assembled program.
    /// </summary>
    /// <param name="result">The assembly, whose sections give the code.</param>
    /// <param name="documentation">Its documentation.</param>
    /// <param name="set">The instruction set the routines are in; routines in another are left out.</param>
    /// <param name="model">The model whose sections apply, such as <c>Enhanced</c>; empty for none.</param>
    /// <param name="others">Other modules' documentation, for <c>Inherit:</c>.</param>
    /// <param name="map">
    ///  What kind of memory each address is in the state the program runs in, such as a machine's at reset, or null:
    ///  then memory holds where values came from but no bits of them.
    /// </param>
    internal AnalysisContracts(
        AssemblyResult result,
        DocumentationSet documentation,
        InstructionSet set,
        string model = "",
        IEnumerable<DocumentationSet>? others = null,
        MemoryMap? map = null)
    {
        _set = set;
        _documentation = documentation;
        foreach (AssemblySection section in result.Sections)
        {
            ReadOnlySpan<byte> bytes = section.Bytes.Span;
            for (int offset = 0; offset < bytes.Length; offset++)
            {
                int address = (section.RunOrigin + offset) & 0xFFFF;
                _memory[address] = bytes[offset];
                _defined[address] = true;
            }
        }

        // The bytes the source assembles as data, as tables: only those of ROM read as constants. Code there may run
        // elsewhere, as AppleSoft's character reader runs in page zero with its operand rewritten.
        foreach (AssemblySourceMapEntry entry in result.SourceMap)
        {
            if (entry.Size == 0) { continue; }
            if (entry.InstructionSet?.GetMnemonic(entry.Operation) >= 0)
            {
                _instructions.Add((ushort)entry.Address);
                continue;
            }

            for (int offset = 0; offset < entry.Size; offset++) { _data[(entry.Address + offset) & 0xFFFF] = true; }
        }

        _engine = new(set, _memory, _defined, Callee, RoutineAt, AnalysisEvaluator.For(set), map, _data, _patched);
        Scan(result);
        IsaDescription description = set.Description;
        _general = _engine.Registers & ~AnalysisRoutineEngine.StackRegisters(set);
        foreach (string name in description.EffectRegisters)
        {
            if (name is "I" or "R" or "DP" || name.EndsWith('\''))
            {
                _general &= ~description.RegisterMask(name);
            }
        }

        DocumentationResolver resolver = new(documentation, others);
        long? Symbol(string name) => result.Symbols.TryGetValue(name, out long value) ? value : null;
        foreach (DocumentationTopic documented in documentation.Topics)
        {
            if (documented.Kind != DocumentationKind.Routine || documented.Value is not { } value)
            {
                continue;
            }

            InstructionSet? routineSet = documentation.InstructionSetAt(documented.Path, documented.Line);
            if (routineSet is not null && !ReferenceEquals(routineSet, set)) { continue; }
            DocumentationTopic topic = resolver.Effective(documented);
            ushort address = (ushort)value;
            HashSet<ushort> own = [];
            foreach (string label in topic.EntryLabels.Select(entry => documentation.EntrySymbol(documented, entry)))
            {
                if (documentation.Symbols.TryGetValue(label, out long entry) && (ushort)entry != address)
                {
                    own.Add((ushort)entry);
                }
            }

            _routines.TryAdd(address, topic);
            if (Read(topic, model, Symbol, own, address) is { } contract)
            {
                _contracts.TryAdd(address, contract);
                foreach (ushort entry in own) { _contracts.TryAdd(entry, contract); }
            }
        }
    }

    /// <summary>
    ///  Checks every routine with a contract.
    /// </summary>
    /// <returns>The findings, the routines checked, the items not verified, and the routines not followed.</returns>
    internal AnalysisContractReport Check()
    {
        List<AnalysisContractFinding> findings = [];
        List<string> skipped = [];
        int count = 0;
        int unverified = 0;
        IsaDescription description = _set.Description;
        foreach ((ushort address, AnalysisContract contract) in _contracts)
        {
            if (address != contract.Address) { continue; }
            AnalysisRoutineSummary? summary = Analyzed(address);
            if (summary is not { Returns: true })
            {
                skipped.Add($"{contract.Topic.Name} (${address:X4}): {summary?.Incomplete ?? "it never returns"}");
                continue;
            }

            count++;

            // Only a sure change is a finding; a register or flag unknown at a return is not verified.
            uint changedRegisters = _engine.Registers & ~summary.KeptRegisters & ~summary.UnknownRegisters;
            byte changedFlags = (byte)(_engine.Flags & ~summary.KeptFlags & ~summary.UnknownFlags);
            foreach ((string item, uint registers, byte flags) in contract.KeepItems)
            {
                uint changed = registers & changedRegisters;
                byte changedFlag = (byte)(flags & changedFlags);
                if (changed == 0 && changedFlag == 0)
                {
                    if (((registers & summary.UnknownRegisters) | (uint)(flags & summary.UnknownFlags)) != 0)
                    {
                        unverified++;
                    }

                    continue;
                }

                int slot = changed != 0 ? BitOperations.TrailingZeroCount(changed) : 32 + BitOperations.TrailingZeroCount(changedFlag);
                ushort? at = summary.ChangedAt.TryGetValue(slot, out ushort where) ? where : null;
                findings.Add(Finding(contract, item, AnalysisContractProblem.NotKept, at));
            }

            if (contract.Listed is not { } listed) { continue; }
            uint unlisted = _general & changedRegisters & ~listed & ~contract.Kept;
            for (int bit = 0; bit < 32; bit++)
            {
                if ((unlisted & (1u << bit)) == 0) { continue; }
                ushort? at = summary.ChangedAt.TryGetValue(bit, out ushort where) ? where : null;
                findings.Add(Finding(contract, description.EffectRegisters[bit], AnalysisContractProblem.NotListed, at));
            }
        }

        findings.Sort((first, second) => first.Address != second.Address
            ? first.Address.CompareTo(second.Address)
            : string.CompareOrdinal(first.Item, second.Item));

        // A condition is fixed only where every routine that reached it, from its start or any of its Entry:
        // labels, was followed to the end and found it went the same one way; a routine the analysis gave up on
        // may have left a way unfollowed.
        foreach (ushort address in _contracts.Keys) { Analyzed(address); }
        Dictionary<ushort, int> conditions = [];
        foreach (AnalysisRoutineSummary? analyzed in _analyzed.Values)
        {
            if (analyzed is null) { continue; }
            foreach ((ushort at, int ways) in analyzed.Conditions)
            {
                int these = analyzed.Incomplete is null ? ways : 3;
                conditions[at] = (conditions.TryGetValue(at, out int seen) ? seen : 0) | these;
            }
        }

        Unreached(conditions);
        return new(findings, count, unverified, skipped, conditions);
    }

    // What the image's statements say of its code: the bytes stores to a fixed address change, which may be another
    // instruction's operand, and the code addresses a table or an operand names other than as a branch's, jump's
    // or call's target, which code may be entered at through a vector or a pushed address.
    private void Scan(AssemblyResult result)
    {
        foreach (ushort address in _instructions)
        {
            if (!_engine.TryDecode(address, out DisassembledInstruction instruction)) { continue; }
            if (_set.EncodingAccess(instruction.EncodingId) != MemoryAccess.Read && _engine.StaticAddress(instruction) is int stored and >= 0)
            {
                _patched[stored] = true;
                _patched[(stored + 1) & 0xFFFF] = true;
            }
        }

        // Each symbol by its name and by its last part, as Inner of Routine::Inner, the first of them where two share it.
        Dictionary<string, ushort> symbols = [with(StringComparer.Ordinal)];
        foreach ((string symbol, long value) in result.Symbols)
        {
            symbols.TryAdd(symbol, (ushort)value);
            int scope = symbol.LastIndexOf("::", StringComparison.Ordinal);
            if (scope >= 0) { symbols.TryAdd(symbol[(scope + 2)..], (ushort)value); }
        }

        foreach (AssemblySourceMapEntry entry in result.SourceMap)
        {
            if (entry.Size == 0 || entry.Operand.Length == 0) { continue; }
            ushort? target = null;
            if (entry.InstructionSet?.GetMnemonic(entry.Operation) >= 0 && _engine.TryDecode((ushort)entry.Address, out DisassembledInstruction instruction))
            {
                target = instruction.DirectTarget;
            }

            foreach (System.Text.RegularExpressions.Match name in Identifier().Matches(entry.Operand))
            {
                if (symbols.TryGetValue(name.Value, out ushort address) && address != target)
                {
                    _referenced.Add(address);
                }

            }
        }
    }

    [System.Text.RegularExpressions.GeneratedRegex(@"[A-Za-z_][A-Za-z0-9_:.]*")]
    private static partial System.Text.RegularExpressions.Regex Identifier();

    // A condition that went one way stays fixed only when the analysis reached everything that leads to it: walking
    // back from it over fall-throughs and direct branches and jumps, through instructions the analysis reached, it
    // meets none it did not. The walk stops at an address analyzed as a routine's start, whose analysis took any
    // values there. Otherwise code no routine was followed through, as BBC BASIC's branch to NUMBER_TO_STRING_POINT,
    // may arrive with other values, and the condition counts as going both ways.
    private void Unreached(Dictionary<ushort, int> conditions)
    {
        HashSet<ushort> visited = [];
        foreach (AnalysisRoutineSummary? analyzed in _analyzed.Values)
        {
            // An analysis that gave up, as at its step limit, may not have carried what it reached any further.
            if (analyzed is { Incomplete: null }) { visited.UnionWith(analyzed.Visited); }
        }

        Dictionary<ushort, List<ushort>> predecessors = Predecessors();
        foreach (ushort at in conditions.Keys.ToArray())
        {
            if (conditions[at] == 3) { continue; }
            HashSet<ushort> seen = [at];
            Queue<ushort> work = new([at]);
            while (work.TryDequeue(out ushort address))
            {
                if (_analyzed.ContainsKey(address)) { continue; }

                // Code a table or an operand names may be entered there, from code no analysis followed.
                if (_referenced.Contains(address))
                {
                    conditions[at] = 3;
                    break;
                }

                if (!predecessors.TryGetValue(address, out List<ushort>? before)) { continue; }

                foreach (ushort from in before)
                {
                    if (!visited.Contains(from))
                    {
                        conditions[at] = 3;
                        work.Clear();
                        break;
                    }

                    if (seen.Add(from)) { work.Enqueue(from); }
                }
            }
        }
    }

    // Each instruction's predecessors among those the source assembles: the instruction before it, where that one
    // can go on, and the branches and jumps that target it. A call's callee is entered as a routine of its own.
    private Dictionary<ushort, List<ushort>> Predecessors()
    {
        Dictionary<ushort, List<ushort>> predecessors = [];
        foreach (ushort address in _instructions)
        {
            if (!_engine.TryDecode(address, out DisassembledInstruction instruction)) { continue; }
            ushort from = address;
            ushort next = (ushort)(address + instruction.Size);
            DisassemblyFlow flow = instruction.Flow;
            if (GoesOn(flow)) { Add(next, from); }

            if (flow is DisassemblyFlow.Jump or DisassemblyFlow.ConditionalBranch && instruction.DirectTarget is { } target)
            {
                Add(target, from);
            }
        }

        return predecessors;

        static bool GoesOn(DisassemblyFlow flow) => flow switch
        {
            DisassemblyFlow.Jump or DisassemblyFlow.IndirectJump or DisassemblyFlow.Return => false,
            DisassemblyFlow.Break or DisassemblyFlow.Stop => false,
            _ => true
        };

        void Add(ushort to, ushort from)
        {
            if (!predecessors.TryGetValue(to, out List<ushort>? list))
            {
                list = [];
                predecessors[to] = list;
            }

            list.Add(from);
        }
    }

    private static AnalysisContractFinding Finding(AnalysisContract contract, string item, AnalysisContractProblem kind, ushort? at) =>
        new(contract.Topic.Name, contract.Address, item, kind, at, contract.Topic.Path, contract.Topic.Line);

    /// <summary>
    ///  Gets the analysis of the code at an address, as a routine: what it keeps when called.
    /// </summary>
    /// <param name="address">The address.</param>
    /// <returns>The summary, or null while that same analysis is under way, as for a recursive call.</returns>
    internal AnalysisRoutineSummary? Analyzed(ushort address)
    {
        if (_analyzed.TryGetValue(address, out AnalysisRoutineSummary? known)) { return known; }
        _analyzed[address] = null;
        IReadOnlySet<ushort>? own = _contracts.TryGetValue(address, out AnalysisContract? contract) ? contract.Own : null;
        AnalysisRoutineSummary summary = _engine.Analyze(address, own);
        _analyzed[address] = summary;
        return summary;
    }

    // A call takes the callee's contract where it has one, as its callers rely on it, or its code's analysis.
    private AnalysisRoutineSummary? Callee(ushort address) =>
        _contracts.TryGetValue(address, out AnalysisContract? contract) ? Documented(contract) : Analyzed(address);

    // A branch, jump or fall-through to a documented routine's start is a tail call into it.
    private AnalysisRoutineSummary? RoutineAt(ushort address) =>
        _contracts.TryGetValue(address, out AnalysisContract? contract) && contract.Address == address ? Documented(contract) : null;

    // What a routine promises: Keeps:, and where there is a Uses:, every register it and Out: do not list; without
    // Uses:, what its code is found to keep as well.
    private AnalysisRoutineSummary Documented(AnalysisContract contract)
    {
        uint kept = contract.Kept;
        byte keptFlags = contract.KeptFlags;
        uint unknown = 0;
        byte unknownFlags = (byte)(_engine.Flags & ~keptFlags & ~contract.OutFlags);
        if (contract.Listed is { } listed)
        {
            kept |= _engine.Registers & ~listed;
        }
        else if (Analyzed(contract.Address) is { Returns: true, Incomplete: null } code)
        {
            // Without Uses:, what the documentation does not settle comes from the code.
            kept |= code.KeptRegisters;
            keptFlags |= code.KeptFlags;
            unknown = code.UnknownRegisters & ~kept;
            unknownFlags = (byte)(code.UnknownFlags & ~keptFlags);
        }
        else
        {
            unknown = _engine.Registers & ~kept;
        }

        return new()
        {
            KeptRegisters = kept,
            KeptFlags = keptFlags,
            UnknownRegisters = unknown,
            UnknownFlags = unknownFlags,
            Returns = true,
            Documented = true,
            ChangesCallerStack = Analyzed(contract.Address)?.ChangesCallerStack == true
        };
    }

    // A routine's contract, or null when it documents none.
    private AnalysisContract? Read(DocumentationTopic topic, string model, Func<string, long?> symbol, HashSet<ushort> own, ushort address)
    {
        bool Applies(DocumentationSection section) => DocumentationResolver.Applies(section.Condition, model, symbol);
        List<DocumentationSection> keeps = [.. topic.SectionsNamed("Keeps").Where(Applies)];
        List<DocumentationSection> uses = [.. topic.SectionsNamed("Uses").Where(Applies)];
        if (keeps.Count == 0 && uses.Count == 0) { return null; }

        List<(string Item, uint Registers, byte Flags)> items = [];
        uint kept = 0;
        byte keptFlags = 0;
        foreach (string item in keeps.SelectMany(section => section.Items).Select(WithoutNote))
        {
            (uint registers, byte flags) = Names(item);
            if (registers == 0 && flags == 0) { continue; }
            items.Add((item, registers, flags));
            kept |= registers;
            keptFlags |= flags;
        }

        byte outFlags = 0;
        foreach (DocumentationEntry entry in topic.SectionsNamed("Out").Where(Applies).SelectMany(section => section.Entries))
        {
            outFlags |= Names(entry.Name).Flags;
        }

        uint? listed = null;
        if (uses.Count != 0)
        {
            uint mask = 0;
            foreach (string item in uses.SelectMany(section => section.Items).Select(WithoutNote))
            {
                mask |= Names(item).Registers;
            }

            foreach (DocumentationEntry entry in topic.SectionsNamed("Out").Where(Applies).SelectMany(section => section.Entries))
            {
                mask |= Names(entry.Name).Registers;
            }

            listed = mask;
        }

        return new(topic, address, kept, keptFlags, listed, items, own) { OutFlags = outFlags };
    }

    // The registers and flags a documentation name stands for: a register, a pair as its parts, the flags register
    // as every flag, a flag by its word, a list split at slashes and commas, all or none.
    private (uint Registers, byte Flags) Names(string item)
    {
        IsaDescription description = _set.Description;
        if (item.Equals("all", StringComparison.OrdinalIgnoreCase))
        {
            return (_engine.Registers, _engine.Flags);
        }

        uint registers = 0;
        byte flags = 0;
        foreach (string part in item.Split(['/', ','], StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries))
        {
            uint mask = description.RegisterMask(part.ToUpperInvariant());
            if (mask != 0)
            {
                registers |= mask & _engine.Registers;
                foreach (IsaFlag flag in description.Flags)
                {
                    if ((mask & description.RegisterMask(flag.Register)) != 0)
                    {
                        flags |= (byte)(1 << flag.Bit);
                    }
                }

                continue;
            }

            foreach (IsaFlag flag in description.Flags)
            {
                if (flag.Words.Any(word => word.Equals(part, StringComparison.OrdinalIgnoreCase)))
                {
                    flags |= (byte)(1 << flag.Bit);
                }
            }
        }

        return (registers, flags);
    }

    private static string WithoutNote(string item)
    {
        int note = item.IndexOf(" (", StringComparison.Ordinal);
        return note > 0 && item.EndsWith(')') ? item[..note] : item;
    }
}
