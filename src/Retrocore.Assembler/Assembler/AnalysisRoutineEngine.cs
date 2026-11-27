// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using Retrocore.Isa;
using Retrocore.Machines;

namespace Retrocore.Assembler;

/// <summary>
///  Follows one routine's code to find which of its caller's registers and flags it keeps, from the
///  instruction-set description's effects lines and the summaries of the routines it calls.
/// </summary>
/// <remarks>
///  <para>
///   Each register and flag holds, at each instruction, its value at entry, a value an instruction surely
///   changed, or an unknown one, as after a call the analysis could not follow. Pushes save values on a model of
///   the stack and pulls restore them; a store of a register to a fixed address and a load from it do the same.
///   So does a copy from one register to another, where the effects lines give one. A call takes the callee's
///   summary, and so does a branch, jump or fall-through to the start of a routine with a contract, a tail call,
///   which then returns.
///  </para>
///  <para>
///   A path the analysis cannot follow, such as an indirect jump, a return through pushed data, a change of the
///   stack pointer or bytes the source does not assemble, ends there, and the summary says it is incomplete.
///  </para>
/// </remarks>
internal sealed class AnalysisRoutineEngine
{
    // Slots: registers by bit, then flags at FlagSlot plus their bit.
    private const int FlagSlot = 32;
    private const int SlotCount = AnalysisRoutineState.SlotCount;

    // A slot's value: >= 0, the entry value of that slot; from -2 down to ChangedLimit, surely changed by the
    // instruction at -(value + 2), and ChangedSomewhere where paths changed it at different places; below
    // ChangedLimit, unknown since the instruction at -(value + 2 + UnknownOffset), as after a call.
    private const int ChangedSomewhere = -1;
    private const int ChangedLimit = -0x10001;
    private const int UnknownOffset = 0x10000;
    private const int UnknownSomewhere = int.MinValue;

    private const int MaximumSteps = 200_000;

    // The most unknown bits an instruction is run for every value of, and the most bytes of memory it may read.
    private const int MaximumUnknownBits = 12;
    private const int MaximumReads = 4;

    private readonly InstructionSet _set;
    private readonly byte[] _memory;
    private readonly bool[] _defined;
    private readonly Func<ushort, AnalysisRoutineSummary?> _callee;
    private readonly Func<ushort, AnalysisRoutineSummary?> _routineAt;
    private readonly uint _leaves;
    private readonly uint _stackRegisters;
    private readonly int _flagsRegister;
    private readonly int _programCounter;
    private readonly byte _allFlags;
    private readonly AnalysisEvaluator? _evaluator;
    private readonly int[] _registers;
    private readonly int[] _first;
    private readonly int[] _varying;
    private readonly int[] _widths;
    private readonly MemoryMap? _map;
    private readonly bool[]? _data;
    private readonly bool[]? _patched;
    private readonly bool[] _fixedForms;
    private readonly int[] _spans;
    private readonly int _directPage;
    private readonly Func<ushort, int> _knownByte;
    private AnalysisRoutineState? _evaluating;

    /// <summary>
    ///  Creates an engine over a 64 KiB image.
    /// </summary>
    /// <param name="set">The instruction set, whose description has effects.</param>
    /// <param name="memory">The image, 65,536 bytes.</param>
    /// <param name="defined">Which of its bytes the source assembles.</param>
    /// <param name="callee">
    ///  The summary of what a call to an address does, documented or analyzed, or null when it is not known, so
    ///  the call makes everything unknown.
    /// </param>
    /// <param name="routineAt">
    ///  The summary of the routine with a contract that starts at an address, or null; a branch, jump or
    ///  fall-through there is a tail call.
    /// </param>
    /// <param name="evaluator">
    ///  Runs an instruction whose inputs are known on the CPU's core, for the values it leaves; null to follow no
    ///  constants but those the effects lines give.
    /// </param>
    /// <param name="map">
    ///  What kind of memory each address is in the state the program runs in, or null when it is not known: then a
    ///  store and a load at a fixed address keep where a value came from, but no bits of it.
    /// </param>
    /// <param name="data">
    ///  Which bytes of the image the source assembles as data; only those of ROM read as constants. Null for none.
    /// </param>
    /// <param name="patched">
    ///  Which bytes of the image a store may change, as code that patches another's operand or opcode does; the
    ///  analysis does not follow code with such a byte. Null for none.
    /// </param>
    internal AnalysisRoutineEngine(
        InstructionSet set,
        byte[] memory,
        bool[] defined,
        Func<ushort, AnalysisRoutineSummary?> callee,
        Func<ushort, AnalysisRoutineSummary?> routineAt,
        AnalysisEvaluator? evaluator = null,
        MemoryMap? map = null,
        bool[]? data = null,
        bool[]? patched = null)
    {
        _data = data;
        _patched = patched;
        _fixedForms = FixedForms(set.Description);
        _spans = Spans(set.Description);
        _evaluator = evaluator;
        _map = map;
        _knownByte = KnownByte;
        _directPage = Bit(set.Description, "DP");
        _registers = new int[set.Description.EffectRegisters.Count];
        _first = new int[_registers.Length];
        _varying = new int[_registers.Length];

        // Each slot's bits: a register's width, 8 for a part the registers line lacks, and 1 for a flag.
        _widths = new int[SlotCount];
        for (int bit = 0; bit < set.Description.EffectRegisters.Count; bit++)
        {
            string name = set.Description.EffectRegisters[bit];
            IsaRegister? register = set.Description.Registers.FirstOrDefault(candidate => candidate.Name == name);
            _widths[bit] = (int)((1L << (register?.Bits ?? 8)) - 1);
        }

        for (int bit = 0; bit < 8; bit++) { _widths[FlagSlot + bit] = 1; }
        _set = set;
        _memory = memory;
        _defined = defined;
        _callee = callee;
        _routineAt = routineAt;
        IsaDescription description = set.Description;
        _flagsRegister = description.Flags.Count == 0 ? -1 : Bit(description, description.Flags[0].Register);
        _programCounter = Bit(description, "PC");
        foreach (IsaFlag flag in description.Flags) { _allFlags |= (byte)(1 << flag.Bit); }
        for (int bit = 0; bit < description.EffectRegisters.Count; bit++)
        {
            bool leaf = description.RegisterMask(description.EffectRegisters[bit]) == 1u << bit;
            if (leaf && bit != _flagsRegister && bit != _programCounter) { _leaves |= 1u << bit; }
        }

        _stackRegisters = StackRegisters(set);
    }

    /// <summary>
    ///  Gets the registers the engine follows, as bits: those without parts, but PC and the flags register, whose
    ///  flags it follows one by one.
    /// </summary>
    internal uint Registers => _leaves;

    /// <summary>
    ///  Gets the flags the engine follows, as bits of the flags register.
    /// </summary>
    internal byte Flags => _allFlags;

    /// <summary>
    ///  Gets the stack pointers calls and returns use, as bits.
    /// </summary>
    /// <param name="set">The instruction set.</param>
    /// <returns>The registers.</returns>
    internal static uint StackRegisters(InstructionSet set)
    {
        uint stacks = 0;
        for (int encoding = 0; encoding < set.Encodings.Count; encoding++)
        {
            if (set.Effects(encoding).StackRegister is int stack and >= 0
                && set.Flow(encoding) is InstructionFlow.Return or InstructionFlow.Call)
            {
                stacks |= 1u << stack;
            }
        }

        return stacks;
    }

    /// <summary>
    ///  Analyzes the routine that starts at an address.
    /// </summary>
    /// <param name="entry">The routine's start.</param>
    /// <param name="own">
    ///  Other addresses of the same routine, its <c>Entry:</c> labels, which are no tail calls.
    /// </param>
    /// <returns>The summary.</returns>
    internal AnalysisRoutineSummary Analyze(ushort entry, IReadOnlySet<ushort>? own = null)
    {
        Dictionary<ushort, AnalysisRoutineState> states = [];
        Queue<ushort> work = new();
        AnalysisRoutineState start = new();
        for (int slot = 0; slot < SlotCount; slot++) { start.Slots[slot] = AnalysisValue.Of(slot); }
        states[entry] = start;
        work.Enqueue(entry);
        AnalysisRoutineState? exit = null;
        string? incomplete = null;
        ushort incompleteAt = 0;
        bool changesCallerStack = false;
        int steps = 0;

        // Each conditional instruction's outcomes over every visit: bit 0 not taken, bit 1 taken.
        Dictionary<ushort, int> outcomes = [];

        while (work.TryDequeue(out ushort pc))
        {
            if (++steps > MaximumSteps)
            {
                Stop("the routine is too long to follow", pc);
                break;
            }

            AnalysisRoutineState state = states[pc].Copy();
            if (!TryDecode(pc, out DisassembledInstruction instruction))
            {
                Stop("it runs into bytes the source does not assemble", pc);
                continue;
            }

            // Code a store changes is not the code assembled: neither its effects nor where it goes are known.
            if (Patched(pc, instruction.Size))
            {
                Stop("it runs code that a store changes", pc);
                continue;
            }

            Step(state, instruction, pc);
        }

        return Summarize(exit, incomplete, incompleteAt, changesCallerStack) with
        {
            Conditions = outcomes,
            Visited = new HashSet<ushort>(states.Keys)
        };

        void Step(AnalysisRoutineState state, DisassembledInstruction instruction, ushort pc)
        {
            InstructionEffects effects = instruction.Effects;
            ushort next = (ushort)(pc + instruction.Size);
            DisassemblyFlow flow = instruction.Flow;
            switch (flow)
            {
                case DisassemblyFlow.Call:
                    Call(state, instruction, pc, next);
                    return;
                case DisassemblyFlow.Return:
                    if (state.StackLost) { Stop("it changes the stack pointer", pc, stack: true); }
                    else if (HasFrames(state)) { Stop("it returns through data it pushed", pc, stack: true); }
                    else { Return(state); }
                    return;
                case DisassemblyFlow.Jump or DisassemblyFlow.ConditionalBranch:
                    if (instruction.DirectTarget is not { } target)
                    {
                        Stop("it jumps where the analysis cannot see", pc);
                        return;
                    }

                    if (flow == DisassemblyFlow.Jump)
                    {
                        Follow(target, state, pc);
                        return;
                    }

                    // A branch whose flags are known goes one way; each way taken tells of the flags.
                    bool? taken = Decide(state, effects, pc);
                    if (taken != false) { Follow(target, Refined(state.Copy(), effects, taken: true), pc); }
                    if (taken != true) { Follow(next, Refined(state, effects, taken: false), pc); }
                    return;
                case DisassemblyFlow.IndirectJump:
                    Stop("it jumps indirectly", pc);
                    return;
                case DisassemblyFlow.Break or DisassemblyFlow.Stop:
                    // A break or stop ends the path without returning.
                    return;
            }

            // A conditional return returns, and falls through when not taken.
            if (effects.MayPull != 0 && effects.Pulled == 0 && effects.MayPush == 0)
            {
                bool? returns = Decide(state, effects, pc);
                if (returns != false && (state.StackLost || HasFrames(state)))
                {
                    Stop("it returns through data it pushed", pc, stack: true);
                }
                else if (returns != false)
                {
                    Return(Refined(state.Copy(), effects, taken: true));
                }

                if (returns == true) { return; }
                state = Refined(state, effects, taken: false);
                Follow(next, state, pc);
                return;
            }

            switch (Effects(state, instruction, effects, pc))
            {
                case AnalysisRoutineOutcome.Next:
                    Follow(next, state, pc);
                    break;
                case AnalysisRoutineOutcome.Returned:
                    Return(state);
                    break;
                case AnalysisRoutineOutcome.PulledReturnAddress:
                    Stop("it pulls data its caller pushed, as its return address", pc, stack: true);
                    break;
                case AnalysisRoutineOutcome.Lost:
                    Stop("it changes the stack pointer", pc, stack: true);
                    break;
                case AnalysisRoutineOutcome.PulledOtherBytes:
                    Stop("it pulls other bytes than it pushed", pc, stack: true);
                    break;
                case AnalysisRoutineOutcome.WroteStack:
                    Stop("it writes into the stack under its return address", pc, stack: true);
                    break;
                default:
                    Stop("it returns through data it pushed", pc, stack: true);
                    break;
            }
        }

        void Call(AnalysisRoutineState state, DisassembledInstruction instruction, ushort pc, ushort next)
        {
            // A conditional call not taken goes on; one that may be taken joins both ways at the next instruction.
            InstructionEffects effects = instruction.Effects;
            if (effects.ConditionFlags != 0)
            {
                bool? taken = Decide(state, effects, pc);
                if (taken != true) { Follow(next, Refined(state.Copy(), effects, taken: false), pc); }
                if (taken == false) { return; }
                state = Refined(state, effects, taken: true);
            }

            ushort? target = instruction.DirectTarget;
            AnalysisRoutineSummary? callee = target is { } address ? _callee(address) : null;
            // A callee that changes the stack under its return address changes this routine's frame: with data
            // pushed there, as SAVE_X_Y pushes A, X and Y before calling such a helper, the change reaches the
            // stack this routine's own caller sees.
            if (callee is { ChangesCallerStack: true })
            {
                bool pushed = state.StackLost || HasFrames(state);
                Stop($"it calls ${target:X4}, which changes the stack under its return address", pc, pushed);
                return;
            }

            // A callee followed only in part keeps nothing for certain; a documented one keeps what it says.
            if (callee is null || callee is { Incomplete: not null, Documented: false }) { Unknown(state, pc); }
            else { Apply(state, callee, pc); }
            if (callee is null || callee.Returns || callee.Incomplete is not null) { Follow(next, state, pc); }
        }

        // Whether a conditional instruction is taken, from the flags known, noted for the summary.
        bool? Decide(AnalysisRoutineState state, InstructionEffects effects, ushort pc)
        {
            KnownFlags(state, out byte known, out byte values);
            bool? taken = effects.Taken(known, values);
            int outcome = taken switch
            {
                true => 2,
                false => 1,
                _ => 3
            };

            outcomes[pc] = (outcomes.TryGetValue(pc, out int seen) ? seen : 0) | outcome;
            return taken;
        }

        // Anything about the stack the analysis cannot follow is a stack the callers cannot trust.
        void Stop(string reason, ushort at, bool stack = false)
        {
            changesCallerStack |= stack;
            if (incomplete is null)
            {
                incomplete = reason;
                incompleteAt = at;
            }
        }

        void Return(AnalysisRoutineState state) => exit = exit is null ? state.Copy() : Join(exit, state);

        void Follow(ushort target, AnalysisRoutineState state, ushort from)
        {
            // A loop may wait for an interrupt to change memory, so values in memory do not go round one.
            if (target <= from) { StripMemory(state); }

            // Reaching the start of another routine with a contract is a tail call: its contract applies, then it
            // returns. With data on the stack the contract cannot stand for the code, which is followed instead.
            bool clear = !state.StackLost && !HasFrames(state);
            if (target != entry && own?.Contains(target) != true && clear && _routineAt(target) is { } tail)
            {
                if (tail.ChangesCallerStack)
                {
                    Stop($"it goes on into ${target:X4}, which changes the stack under its return address", from, stack: true);
                    return;
                }

                Apply(state, tail, from);
                if (tail.Returns || tail.Incomplete is not null) { Return(state); }
                return;
            }

            if (!states.TryGetValue(target, out AnalysisRoutineState? known))
            {
                states[target] = state;
                work.Enqueue(target);
                return;
            }

            AnalysisRoutineState joined = Join(known, state);
            if (!joined.SameAs(known))
            {
                states[target] = joined;
                work.Enqueue(target);
            }
        }
    }

    // Whether some store may change one of an instruction's bytes.
    private bool Patched(ushort pc, int size)
    {
        for (int offset = 0; _patched is not null && offset < size; offset++)
        {
            if (_patched[(ushort)(pc + offset)]) { return true; }
        }

        return false;
    }

    /// <summary>
    ///  Gets the bytes a store may write, from its operand alone: a fixed address and the byte after, as STA Patch+1
    ///  may patch an operand's two bytes, or every byte an index can reach from a base, as STA Patch,Y, within the
    ///  zero page for a zero-page form. Empty where the operand does not say, as for a pointer, a base register,
    ///  as the Z80's [IX+d], or the 6809's direct page, which DP decides.
    /// </summary>
    /// <param name="instruction">The instruction.</param>
    /// <returns>The first address, how many bytes, and whether they wrap within the zero page.</returns>
    internal (int First, int Count, bool ZeroPage) StoredBytes(DisassembledInstruction instruction)
    {
        int span = _spans[instruction.Form.Id];
        if (span == 0 || (_directPage >= 0 && instruction.Effects.Reads(_directPage))) { return (0, 0, false); }
        return (instruction.Operand, span, instruction.Form.Size == 1 && span > 2);
    }

    // How many bytes each memory form's store may write from its operand: 2 for a fixed address (the byte and the
    // one after), one more than an index register reaches for {},X, and 0 where a register forms the base.
    private static int[] Spans(IsaDescription description)
    {
        int[] spans = new int[description.Forms.Count];
        foreach (OperandForm form in description.Forms)
        {
            if (form.Role != OperandRole.Memory || form.FieldCount < 1 || form.HasPostbyte || form.Patterns.Count == 0)
            {
                continue;
            }

            string pattern = form.Patterns[0];
            int open = pattern.IndexOf('[', StringComparison.Ordinal);
            int close = pattern.IndexOf(']', StringComparison.Ordinal);
            string address = (open >= 0 && close > open ? pattern[(open + 1)..close] : pattern).Trim();
            if (address == "{}")
            {
                spans[form.Id] = 2;
                continue;
            }

            string index = address.StartsWith("{},", StringComparison.Ordinal) ? address[3..].Trim() : "";
            IsaRegister? register = description.Registers.FirstOrDefault(candidate => candidate.Name == index);
            if (register is not null) { spans[form.Id] = Math.Min((1 << register.Bits) + 1, 0x10000); }
        }

        return spans;
    }

    /// <summary>
    ///  Gets the fixed address an instruction's operand names, whatever the registers hold: -1 for an indexed or
    ///  pointer form, and for one on the 6809's direct page, which DP decides.
    /// </summary>
    /// <param name="instruction">The instruction.</param>
    /// <returns>The address, or -1.</returns>
    internal int StaticAddress(DisassembledInstruction instruction) =>
        _fixedForms[instruction.Form.Id] && (_directPage < 0 || !instruction.Effects.Reads(_directPage)) ? instruction.Operand : -1;

    // Whether an instruction addresses memory through a stack pointer, or a register holding one's value, as the
    // 6809's STB ,S, the Z80's EX [SP],HL, or the 6502's STA $0101,X after TSX.
    private bool StackRelative(AnalysisRoutineState state, InstructionEffects effects)
    {
        uint stacks = _stackRegisters;
        foreach ((int pointer, _) in state.Stacks) { stacks |= 1u << pointer; }
        if ((effects.RegistersRead & stacks) != 0) { return true; }
        for (int bit = 0; bit < 32; bit++)
        {
            if ((effects.RegistersRead & _leaves & (1u << bit)) == 0) { continue; }
            for (int pointer = 0; pointer < 32; pointer++)
            {
                // Only a stack pointer's own entry value, as TSX copies it, says the register holds it.
                int origin = state.Slots[pointer].Origin;
                bool holds = origin >= 0 && state.Slots[bit].Origin == origin;
                if ((stacks & (1u << pointer)) != 0 && holds) { return true; }
            }
        }

        return false;
    }

    // What was pushed may have been written over: every stacked value is unknown.
    private static void ForgetFrames(AnalysisRoutineState state, ushort at)
    {
        foreach (List<AnalysisRoutineFrame> frames in state.Stacks.Values)
        {
            for (int index = 0; index < frames.Count; index++)
            {
                List<AnalysisRoutineUnit> units = [];
                foreach (AnalysisRoutineUnit unit in frames[index].Units)
                {
                    AnalysisValue[] values = new AnalysisValue[unit.Values.Length];
                    Array.Fill(values, AnalysisValue.Of(Unknown(at)));
                    units.Add(unit with { Values = values });
                }

                frames[index] = frames[index] with { Units = units };
            }
        }
    }

    // The address an instruction reads or writes with no index or pointer: its operand, or on the 6809 a direct
    // page offset with DP known; -1 for any other.
    private int FixedAddress(AnalysisRoutineState state, DisassembledInstruction instruction, InstructionEffects effects)
    {
        if (!_fixedForms[instruction.Form.Id]) { return -1; }
        if (_directPage < 0 || !effects.Reads(_directPage)) { return instruction.Operand; }
        AnalysisValue page = state.Slots[_directPage];
        return page.IsConstant(0xFF) ? ((page.Bits & 0xFF) << 8) | (instruction.Operand & 0xFF) : -1;
    }

    // The forms whose memory operand is a fixed address: a memory form whose address is the operand alone, as the
    // 6502's {} or the Z80's [{}],A, not one formed with a register, as {},X or [IX{}].
    private static bool[] FixedForms(IsaDescription description)
    {
        bool[] forms = new bool[description.Forms.Count];
        foreach (OperandForm form in description.Forms)
        {
            if (form.Role != OperandRole.Memory || form.FieldCount < 1 || form.HasPostbyte || form.Patterns.Count == 0)
            {
                continue;
            }

            string pattern = form.Patterns[0];
            int open = pattern.IndexOf('[', StringComparison.Ordinal);
            int close = pattern.IndexOf(']', StringComparison.Ordinal);
            string address = open >= 0 && close > open ? pattern[(open + 1)..close] : pattern;
            forms[form.Id] = address.Trim() == "{}";
        }

        return forms;
    }

    private static void StripMemory(AnalysisRoutineState state)
    {
        foreach (int address in state.Memory.Keys.ToArray())
        {
            AnalysisValue value = state.Memory[address];
            if (value.Known != 0) { state.Memory[address] = value.WithoutBits; }
        }
    }

    // A byte of memory the analysis knows, for the core: a ROM's byte the source assembles as data, or a RAM byte a
    // store left whole; -1 for any other.
    private int KnownByte(ushort address)
    {
        MemoryKind kind = _map?[address] ?? MemoryKind.None;
        if (kind == MemoryKind.Rom) { return _defined[address] && _data?[address] == true ? _memory[address] : -1; }
        if (kind != MemoryKind.Ram || _evaluating is null) { return -1; }
        return _evaluating.Memory.TryGetValue(address, out AnalysisValue cell) && cell.IsConstant(0xFF) ? cell.Bits & 0xFF : -1;
    }

    // The flags whose values are known, and those values, as bits of the flags register.
    private static void KnownFlags(AnalysisRoutineState state, out byte known, out byte values)
    {
        known = 0;
        values = 0;
        for (int bit = 0; bit < 8; bit++)
        {
            AnalysisValue flag = state.Slots[FlagSlot + bit];
            if ((flag.Known & 1) == 0) { continue; }
            known |= (byte)(1 << bit);
            if ((flag.Bits & 1) != 0) { values |= (byte)(1 << bit); }
        }
    }

    // A state with what an outcome tells of the condition's flags: BEQ taken means zero is set. The flags keep
    // where their values came from.
    private static AnalysisRoutineState Refined(AnalysisRoutineState state, InstructionEffects effects, bool taken)
    {
        if (effects.ConditionFlags == 0) { return state; }
        KnownFlags(state, out byte known, out byte values);
        effects.Implied(taken, known, values, out byte implied, out byte impliedValues);
        for (int bit = 0; bit < 8; bit++)
        {
            if ((implied & (1 << bit)) == 0) { continue; }
            int slot = FlagSlot + bit;
            state.Slots[slot] = state.Slots[slot].WithBits(1, (impliedValues >> bit) & 1);
        }

        return state;
    }

    private static bool HasFrames(AnalysisRoutineState state) => state.Stacks.Values.Any(frames => frames.Count != 0);

    /// <summary>
    ///  Decodes the instruction the image holds at an address.
    /// </summary>
    /// <param name="pc">The address.</param>
    /// <param name="instruction">Receives the instruction.</param>
    /// <returns>Whether the bytes there are an instruction the source assembles.</returns>
    internal bool TryDecode(ushort pc, out DisassembledInstruction instruction)
    {
        Span<byte> bytes = stackalloc byte[8];
        int count = 0;
        for (; count < bytes.Length && _defined[(ushort)(pc + count)]; count++)
        {
            bytes[count] = _memory[(ushort)(pc + count)];
        }

        return Disassembler.TryDecode(bytes[..count], pc, _set, out instruction);
    }

    // An instruction that does not call, return or jump: its pushes and pulls, stores and loads at fixed addresses,
    // copies, and other writes.
    private AnalysisRoutineOutcome Effects(
        AnalysisRoutineState state,
        DisassembledInstruction instruction,
        InstructionEffects effects,
        ushort pc)
    {
        int stack = effects.StackRegister;
        uint stackBit = stack >= 0 ? 1u << stack : 0;
        uint written = (effects.RegistersWritten | effects.RegistersMayWrite) & _leaves;
        byte writtenFlags = (byte)(effects.FlagsWritten | effects.FlagsMayWrite);
        AnalysisRoutineOutcome outcome = AnalysisRoutineOutcome.Next;

        // The bits the core leaves known, from the bits of what the instruction reads that are known.
        bool evaluated = Evaluate(state, instruction, effects, pc, out int flagsKnown, out int flagsBits);

        // The values the instruction leaves in registers it writes, where they are known: copies, loads and pulls.
        Dictionary<int, AnalysisValue> results = [];
        for (int index = 0; index < effects.CopyCount; index++)
        {
            effects.GetCopy(index, out int destination, out int source);
            if ((_leaves & (1u << destination)) != 0 && (_leaves & (1u << source)) != 0)
            {
                results[destination] = state.Slots[source];
            }
        }

        MemoryAccess access = _set.EncodingAccess(instruction.EncodingId);
        OperandForm form = instruction.Form;
        int address = FixedAddress(state, instruction, effects);
        bool direct = address >= 0;
        uint readLeaves = effects.RegistersRead & _leaves & ~(_directPage >= 0 ? 1u << _directPage : 0);
        if (access == MemoryAccess.Read
            && direct
            && readLeaves == 0
            && OneBit(written & ~stackBit) is int loaded and >= 0
            && _widths[loaded] == 0xFF)
        {
            // A load from a fixed address gets what a store left there, where it is RAM or the map is not known;
            // anything else there is a new value.
            bool kept = _map is null || _map[(ushort)address] == MemoryKind.Ram;
            results[loaded] = kept && state.Memory.TryGetValue(address, out AnalysisValue value)
                ? value
                : AnalysisValue.Of(Changed(pc));
        }

        if (effects.Pushed != 0)
        {
            List<AnalysisRoutineUnit> units = Units(state, effects.RegistersRead & ~stackBit, effects.FlagsRead);
            Frames(state, stack).Add(new AnalysisRoutineFrame(effects.Pushed, units));
        }

        if (effects.Pulled != 0)
        {
            outcome = Pull(state, effects, stack, results, ref writtenFlags);
            if (outcome is not (AnalysisRoutineOutcome.Next or AnalysisRoutineOutcome.Returned)) { return outcome; }
        }

        // A write to memory: a store of one byte-wide register to a fixed address keeps its value there; another
        // write there is a new value in each byte it writes; a write through a pointer or an index may land on any,
        // whose values become unknown, and one through the stack pointer changes what was pushed.
        if (access != MemoryAccess.Read)
        {
            if (!direct && StackRelative(state, effects))
            {
                if (!HasFrames(state)) { return AnalysisRoutineOutcome.WroteStack; }
                ForgetFrames(state, pc);
            }

            int width = 0;
            for (int bit = 0; bit < 32; bit++)
            {
                if ((readLeaves & (1u << bit)) != 0) { width += _widths[bit] == 0xFF ? 1 : 2; }
            }

            for (int offset = 0; direct && offset < Math.Max(width, 1); offset++)
            {
                int at = (address + offset) & 0xFFFF;
                MemoryKind kind = _map?[(ushort)at] ?? MemoryKind.Ram;
                if (kind != MemoryKind.Ram)
                {
                    // ROM keeps its bytes, and a device or nothing may not give back what was written.
                    state.Memory.Remove(at);
                }
                else if (width == 1 && access == MemoryAccess.Write && OneBit(readLeaves) is int stored and >= 0)
                {
                    // Without the machine's memory map a fixed address may be I/O, as the BBC's keyboard scan writes
                    // a VIA register and tests it, so memory then keeps where the value came from but no bits of it.
                    AnalysisValue value = state.Slots[stored];
                    state.Memory[at] = _map is null ? value.WithoutBits : value.WithBits(value.Known & 0xFF, value.Bits);
                }
                else
                {
                    state.Memory[at] = AnalysisValue.Of(Changed(pc));
                }
            }

            if (!direct) { Forget(state, pc); }
        }

        // A stack pointer changed other than by a push or pull, as by TXS, loses the stack.
        if ((effects.Pushed | effects.Pulled) != 0) { written &= ~stackBit; }
        if ((written & _stackRegisters) != 0) { state.StackLost = true; }
        foreach ((int pointer, List<AnalysisRoutineFrame> frames) in state.Stacks)
        {
            if (frames.Count != 0 && (written & (1u << pointer)) != 0) { state.StackLost = true; }
        }

        for (int bit = 0; bit < 32; bit++)
        {
            if ((written & (1u << bit)) == 0) { continue; }
            AnalysisValue value = results.TryGetValue(bit, out AnalysisValue result) ? result : AnalysisValue.Of(Changed(pc));
            int width = _widths[bit];
            int known = value.Known & width, bits = value.Bits;
            if (evaluated)
            {
                // What the core leaves known adds to what a copy or a pull carried.
                int found = width & ~_varying[bit];
                bits = (bits & known) | (_first[bit] & found & ~known);
                known |= found;
            }

            state.Slots[bit] = value.WithBits(known, bits);
        }

        // A flag the instruction sets or clears, or the core leaves known, is a constant.
        for (int bit = 0; bit < 8; bit++)
        {
            byte mask = (byte)(1 << bit);
            if ((writtenFlags & mask) == 0) { continue; }
            AnalysisValue flag = AnalysisValue.Of(Changed(pc));
            if (evaluated && (flagsKnown & mask) != 0) { flag = flag.WithBits(1, (flagsBits >> bit) & 1); }
            else if ((effects.FlagsSet & mask) != 0) { flag = flag.WithBits(1, 1); }
            else if ((effects.FlagsCleared & mask) != 0) { flag = flag.WithBits(1, 0); }
            state.Slots[FlagSlot + bit] = flag;
        }

        return outcome == AnalysisRoutineOutcome.Returned && state.StackLost ? AnalysisRoutineOutcome.Lost : outcome;
    }

    // Runs an instruction on the core for every value of the bits it reads that are not known, its reads of
    // memory among them, at most MaximumUnknownBits in all; a bit it writes that comes out the same every time is
    // known. _first and _varying receive the registers' values from the first run and the bits that varied; the
    // flags' come out as known and bits. Instructions that push or pull are not run, and nothing is learned when
    // every bit written varies, which the first few runs usually show.
    private bool Evaluate(
        AnalysisRoutineState state,
        DisassembledInstruction instruction,
        InstructionEffects effects,
        ushort pc,
        out int flagsKnown,
        out int flagsBits)
    {
        flagsKnown = 0;
        flagsBits = 0;
        if (_evaluator is null || (effects.Pushed | effects.Pulled | effects.MayPush | effects.MayPull) != 0)
        {
            return false;
        }

        // The unknown bits read: (slot, bit) pairs, registers by bit and flags at FlagSlot.
        Span<(int Slot, int Bit)> unknown = stackalloc (int, int)[MaximumUnknownBits];
        int unknownCount = 0;
        uint read = effects.RegistersRead;
        int baseFlags = 0;
        for (int slot = 0; slot < SlotCount; slot++)
        {
            bool register = slot < FlagSlot;
            if (register && slot >= _registers.Length) { continue; }
            AnalysisValue value = state.Slots[slot];
            int width = _widths[slot];
            bool needed = register ? (read & (1u << slot)) != 0 : (effects.FlagsRead & (1 << (slot - FlagSlot))) != 0;
            if (register) { _registers[slot] = value.Bits & width; }
            else if ((value.Bits & 1) != 0) { baseFlags |= 1 << (slot - FlagSlot); }
            if (!needed) { continue; }
            if (register && (_leaves & (1u << slot)) == 0) { return false; }
            int missing = width & ~value.Known;
            for (int bit = 0; missing != 0; bit++, missing >>= 1)
            {
                if ((missing & 1) == 0) { continue; }
                if (unknownCount == MaximumUnknownBits) { return false; }
                unknown[unknownCount++] = (slot, bit);
            }
        }

        // The instruction's bytes and the one after them, which the 6502 reads ahead after a one-byte instruction;
        // a byte a store may change is not as assembled, and the code that holds one is not followed at all.
        Span<byte> bytes = stackalloc byte[8];
        int count = 0;
        for (; count < instruction.Size; count++)
        {
            if (_patched?[(ushort)(pc + count)] == true) { return false; }
            bytes[count] = _memory[(ushort)(pc + count)];
        }

        ushort after = (ushort)(pc + count);
        if (_defined[after] && _patched?[after] != true) { bytes[count++] = _memory[after]; }
        bytes = bytes[..count];

        // The first run, with every unknown bit and memory byte 0, says how many bytes of memory it reads.
        Span<byte> reads = stackalloc byte[MaximumReads];
        reads.Clear();
        _registers.CopyTo(_first, 0);
        int firstFlags = baseFlags;
        uint writtenRegisters = (effects.RegistersWritten | effects.RegistersMayWrite) & _leaves;
        _evaluating = state;
        // An instruction that goes back to itself, as the Z80's LDIR until BC is 0, is more than the one step run.
        bool first = _evaluator.TryRun(
            pc,
            bytes,
            _first,
            ref firstFlags,
            reads,
            out int readCount,
            out ushort next,
            read,
            writtenRegisters,
            _knownByte);

        if (!first || next != (ushort)(pc + instruction.Size))
        {
            return false;
        }

        int total = unknownCount + (readCount * 8);
        if (total > MaximumUnknownBits) { return false; }
        int writtenFlags = effects.FlagsWritten | effects.FlagsMayWrite;

        // Flags the effects lines set or clear are known without running; the runs stop once the others all vary.
        int sought = writtenFlags & ~(effects.FlagsSet | effects.FlagsCleared | effects.FlagsHidden);
        Array.Clear(_varying);
        int varyingFlags = 0;
        int combinations = 1 << total;
        Span<int> registers = stackalloc int[_registers.Length];

        // All ones and two alternations first, as they show most bits varying, then every combination.
        for (int run = 0; run < combinations + 3; run++)
        {
            if (total == 0) { break; }
            int assignment = run switch
            {
                0 => combinations - 1,
                1 => 0x5555 & (combinations - 1),
                2 => 0xAAAA & (combinations - 1),
                _ => run - 3
            };

            _registers.CopyTo(registers);
            int flags = baseFlags;
            for (int index = 0; index < unknownCount; index++)
            {
                if ((assignment & (1 << index)) == 0) { continue; }
                (int slot, int bit) = unknown[index];
                if (slot < FlagSlot) { registers[slot] |= 1 << bit; }
                else { flags |= 1 << (slot - FlagSlot); }
            }

            for (int index = 0; index < readCount; index++)
            {
                reads[index] = (byte)(assignment >> (unknownCount + (index * 8)));
            }

            bool ran = _evaluator.TryRun(
                pc,
                bytes,
                registers,
                ref flags,
                reads[..readCount],
                out int again,
                out ushort onward,
                read,
                writtenRegisters,
                _knownByte);

            if (!ran || again != readCount || onward != (ushort)(pc + instruction.Size)) { return false; }

            bool all = true;
            for (int bit = 0; bit < registers.Length; bit++)
            {
                if ((writtenRegisters & (1u << bit)) == 0) { continue; }
                _varying[bit] |= (registers[bit] ^ _first[bit]) & _widths[bit];
                all &= _varying[bit] == _widths[bit];
            }

            varyingFlags |= (flags ^ firstFlags) & writtenFlags;
            all &= (varyingFlags | (~sought & 0xFF)) == 0xFF;
            if (all) { return false; }
        }

        // What is written from hidden state took the core's value of that state, not the program's.
        for (int bit = 0; bit < registers.Length; bit++)
        {
            if ((effects.RegistersHidden & (1u << bit)) != 0) { _varying[bit] = _widths[bit]; }
        }

        flagsKnown = writtenFlags & ~varyingFlags & ~effects.FlagsHidden;
        flagsBits = firstFlags & flagsKnown;
        return true;
    }

    // A pull restores the values a push saved when it takes back exactly that push's bytes into as many registers;
    // anything else is changed. A pull that loads PC from the return address, as PULS A,PC does, returns.
    private AnalysisRoutineOutcome Pull(
        AnalysisRoutineState state,
        InstructionEffects effects,
        int stack,
        Dictionary<int, AnalysisValue> results,
        ref byte writtenFlags)
    {
        if (state.StackLost) { return AnalysisRoutineOutcome.Lost; }
        List<AnalysisRoutineFrame> frames = Frames(state, stack);
        bool loadsPc = _programCounter >= 0 && (effects.RegistersWritten & (1u << _programCounter)) != 0;
        int bytes = effects.Pulled - (loadsPc ? 2 : 0);
        AnalysisRoutineOutcome outcome = loadsPc ? AnalysisRoutineOutcome.Returned : AnalysisRoutineOutcome.Next;
        if (bytes == 0)
        {
            return outcome == AnalysisRoutineOutcome.Returned && frames.Count != 0 ? AnalysisRoutineOutcome.ReturnedThroughData : outcome;
        }

        if (frames.Count == 0) { return AnalysisRoutineOutcome.PulledReturnAddress; }
        uint written = effects.RegistersWritten & _leaves & ~(1u << stack);
        List<AnalysisRoutineUnit> targets = Units(state, written, effects.FlagsWritten);
        AnalysisRoutineFrame top = frames[^1];

        // A pull of other bytes than the last push saved leaves the stack where the model cannot follow it.
        if (top.Bytes != bytes) { return AnalysisRoutineOutcome.PulledOtherBytes; }
        frames.RemoveAt(frames.Count - 1);
        bool matches = top.Units.Count == targets.Count;
        for (int index = 0; index < targets.Count; index++)
        {
            AnalysisRoutineUnit target = targets[index];
            AnalysisRoutineUnit? source = matches ? top.Units[index] : null;
            if (target.Flags)
            {
                if (source is not { Flags: true } savedFlags) { continue; }
                for (int bit = 0; bit < 8; bit++) { state.Slots[FlagSlot + bit] = savedFlags.Values[bit]; }
                writtenFlags = 0;
            }
            else if (source is { Flags: false } saved)
            {
                results[target.Slot] = saved.Values[0];
            }
        }

        return outcome == AnalysisRoutineOutcome.Returned && frames.Count != 0 ? AnalysisRoutineOutcome.ReturnedThroughData : outcome;
    }

    // The values of some registers, in bit order, and of the flags as one, when the flags register is among them.
    private List<AnalysisRoutineUnit> Units(AnalysisRoutineState state, uint registers, byte flags)
    {
        List<AnalysisRoutineUnit> units = [];
        for (int bit = 0; bit < 32; bit++)
        {
            // The flags register is saved as its flags, which are what a pull of it restores.
            if (bit == _flagsRegister && flags == _allFlags)
            {
                units.Add(new AnalysisRoutineUnit(Flags: true, bit, state.Slots[FlagSlot..SlotCount]));
            }
            else if ((registers & (1u << bit)) != 0)
            {
                units.Add(new AnalysisRoutineUnit(Flags: false, bit, [state.Slots[bit]]));
            }
        }

        return units;
    }

    private static List<AnalysisRoutineFrame> Frames(AnalysisRoutineState state, int stack)
    {
        if (!state.Stacks.TryGetValue(stack, out List<AnalysisRoutineFrame>? frames))
        {
            frames = [];
            state.Stacks[stack] = frames;
        }

        return frames;
    }

    // A callee's summary: what it keeps keeps its value, what it surely changes is changed at the call, the rest is
    // unknown; what was stored in memory may have been overwritten.
    private void Apply(AnalysisRoutineState state, AnalysisRoutineSummary summary, ushort at)
    {
        for (int bit = 0; bit < 32; bit++)
        {
            uint mask = 1u << bit;
            if ((_leaves & mask) == 0 || (summary.KeptRegisters & mask) != 0) { continue; }
            state.Slots[bit] = AnalysisValue.Of((summary.UnknownRegisters & mask) != 0 ? Unknown(at) : Changed(at));
        }

        for (int bit = 0; bit < 8; bit++)
        {
            byte mask = (byte)(1 << bit);
            if ((summary.KeptFlags & mask) != 0) { continue; }
            state.Slots[FlagSlot + bit] = AnalysisValue.Of((summary.UnknownFlags & mask) != 0 ? Unknown(at) : Changed(at));
        }

        Forget(state, at);
    }

    // A call the analysis cannot see makes every register, flag and stored value unknown.
    private void Unknown(AnalysisRoutineState state, ushort at) =>
        Apply(state, new AnalysisRoutineSummary { UnknownRegisters = uint.MaxValue, UnknownFlags = 0xFF }, at);

    private static void Forget(AnalysisRoutineState state, ushort at)
    {
        foreach (int address in state.Memory.Keys.ToArray())
        {
            state.Memory[address] = JoinValue(state.Memory[address], AnalysisValue.Of(Unknown(at)));
        }
    }

    private AnalysisRoutineSummary Summarize(
        AnalysisRoutineState? exit,
        string? incomplete,
        ushort incompleteAt,
        bool changesCallerStack)
    {
        uint kept = 0, unknown = 0;
        byte keptFlags = 0, unknownFlags = 0;
        Dictionary<int, ushort> changedAt = [];
        for (int slot = 0; slot < SlotCount; slot++)
        {
            bool register = slot < FlagSlot;
            bool followed = register ? (_leaves & (1u << slot)) != 0 : (_allFlags & (1 << (slot - FlagSlot))) != 0;
            if (!followed) { continue; }

            // With no return followed, nothing is known; a stack pointer is back where it was at every return.
            int value = exit is null ? UnknownSomewhere : exit.Slots[slot].Origin;
            if (register && exit is not null && (_stackRegisters & (1u << slot)) != 0) { value = slot; }
            if (value == slot)
            {
                if (register) { kept |= 1u << slot; }
                else { keptFlags |= (byte)(1 << (slot - FlagSlot)); }
            }
            else if (value < ChangedLimit)
            {
                if (register) { unknown |= 1u << slot; }
                else { unknownFlags |= (byte)(1 << (slot - FlagSlot)); }
            }
            else if (value <= -2)
            {
                changedAt[slot] = (ushort)(-(value + 2));
            }
        }

        return new()
        {
            KeptRegisters = kept,
            KeptFlags = keptFlags,
            UnknownRegisters = unknown,
            UnknownFlags = unknownFlags,
            ChangedAt = changedAt,
            Returns = exit is not null,
            Incomplete = incomplete,
            IncompleteAt = incompleteAt,
            ChangesCallerStack = changesCallerStack
        };
    }

    private static int Changed(ushort at) => -(at + 2);

    private static int Unknown(ushort at) => -(at + 2) - UnknownOffset;

    private static int OneBit(uint mask) =>
        mask != 0 && (mask & (mask - 1)) == 0 ? System.Numerics.BitOperations.TrailingZeroCount(mask) : -1;

    private static int Bit(IsaDescription description, string name) => OneBit(description.RegisterMask(name));

    // Two paths' values of one slot: the same value; else surely changed if either path changed it, keeping where;
    // else unknown if either is; else, two different entry values, changed.
    private static AnalysisValue JoinValue(AnalysisValue first, AnalysisValue second) =>
        first.Join(second, JoinOrigin(first.Origin, second.Origin));

    private static int JoinOrigin(int first, int second)
    {
        if (first == second) { return first; }
        bool changedFirst = first is <= ChangedSomewhere and >= ChangedLimit;
        bool changedSecond = second is <= ChangedSomewhere and >= ChangedLimit;
        if (changedFirst && changedSecond) { return first == ChangedSomewhere ? second : first; }
        if (changedFirst) { return first; }
        if (changedSecond) { return second; }
        if (first >= 0 && second >= 0) { return ChangedSomewhere; }
        if (first < ChangedLimit && second < ChangedLimit) { return Math.Max(first, second); }
        return first < ChangedLimit ? first : second;
    }

    private static AnalysisRoutineState Join(AnalysisRoutineState first, AnalysisRoutineState second)
    {
        AnalysisRoutineState joined = first.Copy();
        for (int slot = 0; slot < SlotCount; slot++)
        {
            joined.Slots[slot] = JoinValue(first.Slots[slot], second.Slots[slot]);
        }

        // A value stored on one path only is a new value on the other.
        foreach (int address in first.Memory.Keys)
        {
            joined.Memory[address] = second.Memory.TryGetValue(address, out AnalysisValue theirs)
                ? JoinValue(first.Memory[address], theirs)
                : JoinValue(first.Memory[address], AnalysisValue.Of(ChangedSomewhere));
        }

        foreach ((int address, AnalysisValue value) in second.Memory)
        {
            if (!first.Memory.ContainsKey(address))
            {
                joined.Memory[address] = JoinValue(value, AnalysisValue.Of(ChangedSomewhere));
            }
        }

        joined.StackLost |= second.StackLost;

        // A stack with frames on one path only differs too, whichever path arrived first.
        foreach ((int stack, List<AnalysisRoutineFrame> frames) in first.Stacks)
        {
            if (frames.Count != 0 && !second.Stacks.ContainsKey(stack)) { joined.StackLost = true; }
        }

        foreach ((int stack, List<AnalysisRoutineFrame> frames) in second.Stacks)
        {
            List<AnalysisRoutineFrame> mine = Frames(joined, stack);
            if (mine.Count != frames.Count)
            {
                joined.StackLost = true;
                continue;
            }

            for (int index = 0; index < frames.Count; index++)
            {
                if (mine[index].Bytes != frames[index].Bytes || mine[index].Units.Count != frames[index].Units.Count)
                {
                    joined.StackLost = true;
                    continue;
                }

                List<AnalysisRoutineUnit> units = [];
                for (int unit = 0; unit < frames[index].Units.Count; unit++)
                {
                    AnalysisRoutineUnit left = mine[index].Units[unit];
                    AnalysisRoutineUnit right = frames[index].Units[unit];
                    AnalysisValue[] values = new AnalysisValue[left.Values.Length];
                    for (int value = 0; value < values.Length; value++)
                    {
                        AnalysisValue theirs = value < right.Values.Length ? right.Values[value] : AnalysisValue.Of(ChangedSomewhere);
                        values[value] = JoinValue(left.Values[value], theirs);
                    }

                    units.Add(left with { Values = values });
                }

                mine[index] = mine[index] with { Units = units };
            }
        }

        return joined;
    }
}
