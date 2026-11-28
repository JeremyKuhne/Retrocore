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

    // The direct calls to each address, by the call's address, and the states the analysis saw at calls to an
    // Entry: label with a contract, for checking it with each caller's values.
    private readonly Dictionary<ushort, List<ushort>> _callSites = [];
    private readonly Dictionary<ushort, List<AnalysisRoutineState>> _callStates = [];
    private ushort? _observing;

    // Where code may be entered other than by falling into it: labels and the targets of jumps and branches, at any
    // byte, and addresses the code writes as numbers, at an instruction's start.
    private readonly HashSet<ushort> _entered = [];
    private readonly HashSet<ushort> _instructionSet = [];

    // Addresses the code writes as numbers, which a computed jump or call may go to: an operand that is no direct
    // target, as LDX #$100B, and every word of data, each with the next address too, as an RTS goes one past what
    // was pushed.
    private readonly HashSet<ushort> _numbers = [];

    // The numbers data holds, which a vector jump, as JMP (Vector), or an RTS table may go to.
    private readonly HashSet<ushort> _vectors = [];

    // The direct targets of jumps, branches and calls, where code surely goes.
    private readonly HashSet<ushort> _targets = [];

    // The addresses of exported labels, which programs outside the assembly may call with any values.
    private readonly HashSet<ushort> _exported = [];

    // The jumps and branches to each address, by their addresses.
    private readonly Dictionary<ushort, List<ushort>> _jumpSites = [];
    private const int MaximumCallStates = 16;
    private const int MaximumRunSteps = 64;
    private const int MaximumInstruction = 5;
    private readonly MemoryMap? _map;
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
        _map = map;
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

        _engine = new(set, _memory, _defined, Callee, RoutineAt, AnalysisEvaluator.For(set), map, _data, _patched)
        {
            CallObserver = ObserveCall
        };

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

        // Each routine's contract at its start first, then entries' keeps clauses, then other entries' contracts,
        // each where nothing came before, in source order.
        List<(ushort At, AnalysisContract Contract)> entered = [];
        List<(ushort At, AnalysisContract Contract)> plain = [];
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

            // An Entry: whose meaning ends in "; keeps ..." has that in place of the routine's Keeps:, unless the
            // label is a routine of its own with a contract; a label at the same address takes the clause too.
            Dictionary<ushort, (string Name, IReadOnlyList<string> Keeps)> clauses = [];
            foreach (DocumentationEntry entry in topic.SectionsNamed("Entry")
                .Where(section => DocumentationResolver.Applies(section.Condition, model, Symbol))
                .SelectMany(section => section.Entries))
            {
                string label = documentation.EntrySymbol(documented, entry.Name);
                if (entry.Keeps is { } keeps
                    && documentation.Symbols.TryGetValue(label, out long at)
                    && (ushort)at != address
                    && !(documentation.Find(label) is { } found
                        && resolver.Effective(found).HasContract(section => DocumentationResolver.Applies(section.Condition, model, Symbol))))
                {
                    clauses.TryAdd((ushort)at, (entry.Name, keeps));
                }
            }

            foreach ((ushort at, (string name, IReadOnlyList<string> keeps)) in clauses)
            {
                if (Read(topic, model, Symbol, own, address, keeps) is { } clause)
                {
                    entered.Add((at, clause with { Entry = name }));
                }
            }

            // A call to another entry takes the routine's contract where the label has no comment of its own, as the
            // debugger takes it; one with a comment is a routine of its own.
            _routines.TryAdd(address, topic);
            if (Read(topic, model, Symbol, own, address, keeps: null) is { } contract)
            {
                _contracts.TryAdd(address, contract);
                foreach (string label in topic.EntryLabels.Select(entry => documentation.EntrySymbol(documented, entry)))
                {
                    if (documentation.Symbols.TryGetValue(label, out long entry)
                        && (ushort)entry != address
                        && !clauses.ContainsKey((ushort)entry)
                        && documentation.Find(label) is null)
                    {
                        plain.Add(((ushort)entry, contract));
                    }
                }
            }
        }

        foreach ((ushort at, AnalysisContract contract) in entered.Concat(plain)) { _contracts.TryAdd(at, contract); }
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

        // Every routine first, so what each one visits is known when its entries are checked.
        foreach (ushort address in _contracts.Keys) { Analyzed(address); }
        foreach ((ushort address, AnalysisContract contract) in _contracts)
        {
            AnalysisRoutineSummary? summary = Analyzed(address);

            // An Entry: label keeps what the routine says, or what its keeps clause says: a sure change from there is
            // a finding, unless the entry keeps it with the values each of its callers passes.
            if (address != contract.Address)
            {
                if (summary is { Returns: true }) { unverified += CheckEntry(address, contract, summary, findings); }
                continue;
            }

            if (summary is not { Returns: true })
            {
                skipped.Add($"{contract.Topic.Name} (${address:X4}): {summary?.Incomplete ?? "it never returns"}");
                continue;
            }

            // A routine followed only in part may change on a path not followed what no path followed changes.
            unverified += CheckKeeps(contract, summary, findings);
            if (summary.Incomplete is not null)
            {
                skipped.Add($"{contract.Topic.Name} (${address:X4}): followed in part, as {summary.Incomplete}");
            }
            else
            {
                count++;
            }

            uint changedRegisters = _engine.Registers & ~summary.KeptRegisters & ~summary.UnknownRegisters;
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

    // What the image's statements say of its code: the bytes stores may change, which may be another instruction's
    // opcode or operand, and the code addresses a table or an operand names other than as a branch's, jump's
    // or call's target, which code may be entered at through a vector or a pushed address.
    private void Scan(AssemblyResult result)
    {
        foreach (ushort address in _instructions)
        {
            if (!_engine.TryDecode(address, out DisassembledInstruction instruction)) { continue; }
            _instructionSet.Add(address);
            if (instruction.DirectTarget is { } target)
            {
                _entered.Add(target);
                _targets.Add(target);
            }

            if (instruction.Flow is DisassemblyFlow.Jump or DisassemblyFlow.ConditionalBranch && instruction.DirectTarget is { } jumped)
            {
                if (!_jumpSites.TryGetValue(jumped, out List<ushort>? jumps)) { _jumpSites[jumped] = jumps = []; }
                jumps.Add(address);
            }

            if (instruction.Form.FieldCount != 0 && instruction.DirectTarget != instruction.Operand)
            {
                _numbers.Add(instruction.Operand);
                _numbers.Add((ushort)(instruction.Operand + 1));
            }

            if (instruction.Flow == DisassemblyFlow.Call && instruction.DirectTarget is { } called)
            {
                if (!_callSites.TryGetValue(called, out List<ushort>? sites)) { _callSites[called] = sites = []; }
                sites.Add(address);
            }

            // A store into RAM may patch code there: at a fixed address, the byte and the one after, as STA Patch+1
            // does; from an indexed one's base, every byte the index reaches, as STA Patch,Y does. Stores through a
            // pointer, a base register or the 6809's direct page are not seen.
            if (_set.EncodingAccess(instruction.EncodingId) is MemoryAccess.Read or MemoryAccess.Address) { continue; }
            (int first, int count, bool zeroPage) = _engine.StoredBytes(instruction);
            for (int offset = 0; offset < count; offset++)
            {
                ushort at = zeroPage ? (ushort)((first + offset) & 0xFF) : (ushort)(first + offset);
                if ((_map?[at] ?? MemoryKind.Ram) == MemoryKind.Ram) { _patched[at] = true; }
            }
        }

        // Every two bytes of one data statement, in the CPU's order, as the numbers it may hold.
        bool little = _set.Endianness == Endianness.Little;
        foreach (AssemblySourceMapEntry entry in result.SourceMap)
        {
            if (entry.Size < 2 || entry.InstructionSet?.GetMnemonic(entry.Operation) >= 0) { continue; }
            for (int offset = 0; offset + 1 < entry.Size; offset++)
            {
                byte first = _memory[(entry.Address + offset) & 0xFFFF];
                byte second = _memory[(entry.Address + offset + 1) & 0xFFFF];
                ushort word = little ? (ushort)(first | (second << 8)) : (ushort)((first << 8) | second);
                _numbers.Add(word);
                _numbers.Add((ushort)(word + 1));
                _vectors.Add(word);
                _vectors.Add((ushort)(word + 1));
            }
        }

        // A number is a guess, as a font's bytes may read as one: it is a way in only at an instruction's start, as
        // an RTS table's CATALOGUE-1 is at CATALOGUE.
        _entered.UnionWith(_numbers.Where(_instructionSet.Contains));

        // Each symbol by its name and by its last part, as Inner of Routine::Inner, with every address a part names
        // where scopes share it, as two routines' Loop labels.
        Dictionary<string, List<ushort>> symbols = [with(StringComparer.Ordinal)];
        foreach (AssemblySymbol defined in result.SymbolDefinitions)
        {
            // A label is a way in; an equate, as CR = $0D, is a number, and an exported label one outside code calls.
            if (!defined.IsConstant) { _entered.Add((ushort)defined.Value); }
            if (defined.IsExported && !defined.IsConstant) { _exported.Add((ushort)defined.Value); }
        }

        foreach ((string symbol, long value) in result.Symbols)
        {
            Add(symbol, (ushort)value);
            int scope = symbol.LastIndexOf("::", StringComparison.Ordinal);
            if (scope >= 0) { Add(symbol[(scope + 2)..], (ushort)value); }
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
                foreach (ushort address in symbols.TryGetValue(name.Value, out List<ushort>? named) ? named : [])
                {
                    if (address != target) { _referenced.Add(address); }
                }

            }
        }

        void Add(string name, ushort value)
        {
            if (!symbols.TryGetValue(name, out List<ushort>? list))
            {
                list = [];
                symbols[name] = list;
            }

            list.Add(value);
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
        new(contract.Topic.Name, contract.Address, item, kind, at, contract.Topic.Path, contract.Topic.Line)
        {
            Entry = contract.Entry
        };

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

    // The start of the straight run of code an instruction is in: back over instructions that fall into the next,
    // to a label, a jump's or branch's target, or code that does not fall through; null where bytes the source
    // assembles as data come just before it, which a skip, as .byte $2C, may run into the run from.
    private ushort? RunStart(ushort address)
    {
        ushort site = address;
        for (int steps = 0; steps < MaximumRunSteps && !_entered.Contains(address); steps++)
        {
            ushort? previous = null;
            for (int back = 1; back <= 5 && previous is null; back++)
            {
                ushort at = (ushort)(address - back);
                if (_instructionSet.Contains(at)
                    && _engine.TryDecode(at, out DisassembledInstruction instruction)
                    && instruction.Size == back
                    && instruction.Flow is DisassemblyFlow.Next or DisassemblyFlow.Call or DisassemblyFlow.Wait)
                {
                    previous = at;
                }
            }

            if (previous is not { } before) { break; }
            address = before;
        }

        // A skip is an instruction that starts in data code may run into, or a patched byte, just before the run and
        // ends inside it, so within one byte less than the longest instruction. (A patched byte in the run stops the
        // run's analysis at it, as the engine does with any.)
        for (int back = 1; back < MaximumInstruction; back++)
        {
            ushort at = (ushort)(address - back);
            if (_defined[at] && (_patched[at] || (_data[at] && DataReached(at)))) { return null; }
        }

        // A way in that is no instruction's start, as JMP Caller+3 into a CMP #$EA that runs as NOP, or as a BIT whose
        // operand hides an instruction, may come into the run in the middle of one: inside the run, or just before it
        // where what it decodes to runs on past the run's start.
        for (ushort at = (ushort)(address - (MaximumInstruction - 1)); at != site; at++)
        {
            if (!_entered.Contains(at) || _instructionSet.Contains(at)) { continue; }
            bool inside = (ushort)(at - address) < (ushort)(site - address);
            if (inside || (_engine.TryDecode(at, out DisassembledInstruction hidden) && (ushort)(address - at) < hidden.Size))
            {
                return null;
            }
        }

        return address;
    }

    // Whether code may run into a data byte: through a jump, branch or call to it or before it in its data, a number
    // data holds that points there, as a JMP (Vector) may go, or by falling into the data from the instruction before,
    // as into a .byte $2C written as a skip; a table or text after a return, which only a label or a load names, is
    // not.
    private bool DataReached(ushort at)
    {
        for (int steps = 0; steps < MaximumRunSteps; steps++)
        {
            if (_targets.Contains(at) || _vectors.Contains(at)) { return true; }
            ushort before = (ushort)(at - 1);
            if (!_defined[before] || !_data[before]) { return FallsInto(at) is not null; }
            at = before;
        }

        return true;
    }

    // The instruction before one that falls into it, or null.
    private ushort? FallsInto(ushort address)
    {
        for (int back = 1; back <= MaximumInstruction; back++)
        {
            ushort at = (ushort)(address - back);
            if (_instructionSet.Contains(at)
                && _engine.TryDecode(at, out DisassembledInstruction instruction)
                && instruction.Size == back
                && instruction.Flow is DisassemblyFlow.Next or DisassemblyFlow.Call or DisassemblyFlow.ConditionalBranch or DisassemblyFlow.Wait)
            {
                return at;
            }
        }

        return null;
    }

    // Whether the analysis saw a call, with few enough states there to check each.
    private bool Seen(ushort site) =>
        _callStates.TryGetValue(site, out List<AnalysisRoutineState>? states) && states.Count is > 0 and <= MaximumCallStates;

    // A call to an Entry: label: the state there, kept for checking the entry with the caller's values.
    private void ObserveCall(ushort pc, ushort target, AnalysisRoutineState state)
    {
        if (pc != _observing || !_contracts.TryGetValue(target, out AnalysisContract? contract) || contract.Address == target)
        {
            return;
        }

        if (!_callStates.TryGetValue(pc, out List<AnalysisRoutineState>? states)) { _callStates[pc] = states = []; }
        if (states.Count <= MaximumCallStates && !states.Any(state.SameAs)) { states.Add(state.Copy()); }
    }

    // The findings for an entry's Keeps: items. Where its own analysis, with nothing known, finds a sure change, as
    // the MOS's SET_STATUS_BITS falling through with A and CFS_STATUS both 0, it is checked again from each direct
    // call, with what the caller's registers and flags hold there: a sure change on any is a finding. Without every
    // call seen, as for an entry also reached through a table, the first finding stands.
    private int CheckEntry(ushort address, AnalysisContract contract, AnalysisRoutineSummary summary, List<AnalysisContractFinding> findings)
    {
        List<AnalysisContractFinding> found = [];
        int unverified = CheckKeeps(contract, summary, found);
        List<AnalysisRoutineState> callers = [];
        List<ushort> sites = _callSites.TryGetValue(address, out List<ushort>? calls) ? calls : [];

        // Each call is seen from the start of its straight run of code, with nothing known there, which holds for
        // every way into the run the code shows (see RunStart); a routine's analysis that passes the call may have
        // come in one way of several. A run that data or patched bytes just before it may run into, as a BIT opcode
        // written as .byte $2C to skip the next instruction, is not seen. Jumps and branches to the entry are no calls: the code that takes them is
        // followed through it, with its own values, and does not rely on the entry's promise.
        if (found.Count != 0)
        {
            foreach (ushort site in sites)
            {
                _callStates.Remove(site);
                if (RunStart(site) is not { } start) { continue; }
                _observing = site;
                _engine.Analyze(start);
                _observing = null;
            }
        }

        // An entry whose address the code takes as data, as in a table, or writes as a number, may be called through
        // it, and an exported one by programs outside the assembly; one other code jumps or branches or falls to may be called that way, after a return address pushed, as
        // a JSR would. Its own routine's jumps, branches and fall-through to it are its own code.
        IReadOnlySet<ushort> own = Analyzed(contract.Address)?.Visited ?? new HashSet<ushort>();
        bool onlyCalled = !_referenced.Contains(address)
            && !_numbers.Contains(address)
            && !_exported.Contains(address)
            && (!_jumpSites.TryGetValue(address, out List<ushort>? jumps) || jumps.All(own.Contains))
            && (FallsInto(address) is not { } before || own.Contains(before));

        if (found.Count != 0 && onlyCalled && sites.Count != 0 && sites.All(Seen))
        {
            foreach (ushort site in sites) { callers.AddRange(_callStates[site]); }
            found.Clear();
            unverified = 0;
            foreach (AnalysisRoutineState caller in callers)
            {
                AnalysisRoutineSummary entered = _engine.Analyze(address, contract.Own, caller);
                int notVerified = entered.Returns ? CheckKeeps(contract, entered, found) : contract.KeepItems.Count;
                unverified = Math.Max(unverified, notVerified);
            }
        }

        foreach (AnalysisContractFinding finding in found)
        {
            if (!findings.Contains(finding)) { findings.Add(finding); }
        }

        return unverified;
    }

    // The findings for a routine's Keeps: items, a sure change of each; returns the number not verified, unknown
    // at a return or not followed on every path.
    private int CheckKeeps(AnalysisContract contract, AnalysisRoutineSummary summary, List<AnalysisContractFinding> findings)
    {
        int unverified = 0;
        uint changedRegisters = _engine.Registers & ~summary.KeptRegisters & ~summary.UnknownRegisters;
        byte changedFlags = (byte)(_engine.Flags & ~summary.KeptFlags & ~summary.UnknownFlags);
        foreach ((string item, uint registers, byte flags) in contract.KeepItems)
        {
            uint changed = registers & changedRegisters;
            byte changedFlag = (byte)(flags & changedFlags);
            if (changed == 0 && changedFlag == 0)
            {
                bool unknown = ((registers & summary.UnknownRegisters) | (uint)(flags & summary.UnknownFlags)) != 0;
                if (unknown || summary.Incomplete is not null) { unverified++; }
                continue;
            }

            int slot = changed != 0 ? BitOperations.TrailingZeroCount(changed) : 32 + BitOperations.TrailingZeroCount(changedFlag);
            ushort? at = summary.ChangedAt.TryGetValue(slot, out ushort where) ? where : null;
            AnalysisContractFinding finding = Finding(contract, item, AnalysisContractProblem.NotKept, at);
            if (!findings.Contains(finding)) { findings.Add(finding); }
        }

        return unverified;
    }

    // A call takes the callee's contract where it has one, as its callers rely on it, or its code's analysis.
    private AnalysisRoutineSummary? Callee(ushort address) =>
        _contracts.TryGetValue(address, out AnalysisContract? contract) ? Documented(contract, address) : Analyzed(address);

    // A branch, jump or fall-through to a documented routine's start is a tail call into it.
    private AnalysisRoutineSummary? RoutineAt(ushort address) =>
        _contracts.TryGetValue(address, out AnalysisContract? contract) && contract.Address == address ? Documented(contract, address) : null;

    // What a routine promises, entered at its start or an Entry: label: Keeps:, and where there is a Uses:, every
    // register it and Out: do not list; without Uses:, what its code from there is found to keep as well.
    private AnalysisRoutineSummary Documented(AnalysisContract contract, ushort address)
    {
        uint kept = contract.Kept;
        byte keptFlags = contract.KeptFlags;
        uint unknown = 0;
        byte unknownFlags = (byte)(_engine.Flags & ~keptFlags & ~contract.OutFlags);
        if (contract.Listed is { } listed)
        {
            kept |= _engine.Registers & ~listed;
        }
        else if (Analyzed(address) is { Returns: true, Incomplete: null } code)
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
            ChangesCallerStack = Analyzed(address)?.ChangesCallerStack == true,
            StackAddresses = (Analyzed(address)?.StackAddresses ?? 0) & ~kept,
            WritesThroughPointers = Analyzed(address) is not { Incomplete: null, WritesThroughPointers: false }
        };
    }

    // A routine's contract, or null when it documents none.
    // An entry's own keeps, from its "; keeps ..." clause, stand in for Keeps: and Uses:, which promise for the
    // routine's start.
    private AnalysisContract? Read(
        DocumentationTopic topic,
        string model,
        Func<string, long?> symbol,
        HashSet<ushort> own,
        ushort address,
        IReadOnlyList<string>? keeps)
    {
        bool Applies(DocumentationSection section) => DocumentationResolver.Applies(section.Condition, model, symbol);
        IEnumerable<string> routineKeeps = topic.SectionsNamed("Keeps").Where(Applies).SelectMany(section => section.Items);
        IEnumerable<string> keptItems = keeps ?? routineKeeps.Select(WithoutNote);
        List<DocumentationSection> uses = keeps is null ? [.. topic.SectionsNamed("Uses").Where(Applies)] : [];
        bool documents = keeps is not null || uses.Count != 0 || topic.SectionsNamed("Keeps").Any(Applies);
        if (!documents) { return null; }

        List<(string Item, uint Registers, byte Flags)> items = [];
        uint kept = 0;
        byte keptFlags = 0;
        foreach (string item in keptItems)
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
