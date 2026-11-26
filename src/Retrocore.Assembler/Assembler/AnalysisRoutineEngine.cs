// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using Retrocore.Isa;

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
    internal AnalysisRoutineEngine(
        InstructionSet set,
        byte[] memory,
        bool[] defined,
        Func<ushort, AnalysisRoutineSummary?> callee,
        Func<ushort, AnalysisRoutineSummary?> routineAt,
        AnalysisEvaluator? evaluator = null)
    {
        _evaluator = evaluator;
        _registers = new int[set.Description.EffectRegisters.Count];
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

            Step(state, instruction, pc);
        }

        return Summarize(exit, incomplete, incompleteAt, changesCallerStack) with { Conditions = outcomes };

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

            if (callee is null) { Unknown(state, pc); }
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

    // The flags whose values are known, and those values, as bits of the flags register.
    private static void KnownFlags(AnalysisRoutineState state, out byte known, out byte values)
    {
        known = 0;
        values = 0;
        for (int bit = 0; bit < 8; bit++)
        {
            AnalysisValue flag = state.Slots[FlagSlot + bit];
            if (!flag.IsConstant) { continue; }
            known |= (byte)(1 << bit);
            if (flag.Constant != 0) { values |= (byte)(1 << bit); }
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
            state.Slots[slot] = state.Slots[slot] with { Constant = (impliedValues >> bit) & 1 };
        }

        return state;
    }

    private static bool HasFrames(AnalysisRoutineState state) => state.Stacks.Values.Any(frames => frames.Count != 0);

    private bool TryDecode(ushort pc, out DisassembledInstruction instruction)
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

        // What the core leaves when every register and flag the instruction reads is a known constant.
        bool evaluated = Evaluate(state, instruction, effects, pc, out int evaluatedFlags);

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
        bool direct = form.Role == OperandRole.Memory && form.FieldCount >= 1 && !form.HasPostbyte;
        uint readLeaves = effects.RegistersRead & _leaves;
        if (access == MemoryAccess.Read && direct && readLeaves == 0 && OneBit(written & ~stackBit) is int loaded and >= 0)
        {
            // A load from a fixed address gets what a store left there; anything else there is a new value.
            results[loaded] = state.Memory.TryGetValue(instruction.Operand, out AnalysisValue value) ? value : AnalysisValue.Of(Changed(pc));
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

        // A write to memory: a store of one register to a fixed address keeps its value there; another write there
        // is a new value; a write through a pointer or an index may land on any, whose values become unknown.
        if (access != MemoryAccess.Read)
        {
            if (direct && access == MemoryAccess.Write && OneBit(readLeaves) is int stored and >= 0)
            {
                // Memory keeps where the value came from but not a constant: without the machine's memory map, a
                // fixed address may be I/O, as the BBC's keyboard scan writes a VIA register and tests it.
                state.Memory[instruction.Operand] = state.Slots[stored] with { Constant = -1 };
            }
            else if (direct)
            {
                state.Memory[instruction.Operand] = AnalysisValue.Of(Changed(pc));
            }
            else
            {
                Forget(state, pc);
            }
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
            state.Slots[bit] = evaluated ? value with { Constant = _registers[bit] } : value;
        }

        // A flag the instruction sets or clears, or the core computed, is a constant.
        for (int bit = 0; bit < 8; bit++)
        {
            byte mask = (byte)(1 << bit);
            if ((writtenFlags & mask) == 0) { continue; }
            int constant = -1;
            if (evaluated) { constant = (evaluatedFlags >> bit) & 1; }
            else if ((effects.FlagsSet & mask) != 0) { constant = 1; }
            else if ((effects.FlagsCleared & mask) != 0) { constant = 0; }
            state.Slots[FlagSlot + bit] = new AnalysisValue(Changed(pc), constant);
        }

        return outcome == AnalysisRoutineOutcome.Returned && state.StackLost ? AnalysisRoutineOutcome.Lost : outcome;
    }

    // Runs an instruction on the core when every register and flag it reads is known, and nothing it does is a
    // jump, a stack access or a write the analysis must see itself; the registers it leaves are in _registers.
    private bool Evaluate(
        AnalysisRoutineState state,
        DisassembledInstruction instruction,
        InstructionEffects effects,
        ushort pc,
        out int flags)
    {
        flags = 0;
        if (_evaluator is null || (effects.Pushed | effects.Pulled | effects.MayPush | effects.MayPull) != 0)
        {
            return false;
        }

        uint read = effects.RegistersRead;
        for (int bit = 0; bit < _registers.Length; bit++)
        {
            AnalysisValue value = state.Slots[bit];
            bool needed = (read & (1u << bit)) != 0;
            if (needed && (!value.IsConstant || (_leaves & (1u << bit)) == 0)) { return false; }
            _registers[bit] = value.IsConstant ? value.Constant : 0;
        }

        for (int bit = 0; bit < 8; bit++)
        {
            AnalysisValue flag = state.Slots[FlagSlot + bit];
            if ((effects.FlagsRead & (1 << bit)) != 0 && !flag.IsConstant) { return false; }
            if (flag.IsConstant && flag.Constant != 0) { flags |= 1 << bit; }
        }

        // The instruction's bytes and the code after them, which a core may read ahead, as the 6502 reads the byte
        // after a one-byte instruction.
        Span<byte> bytes = stackalloc byte[8];
        int count = 0;
        for (; count < bytes.Length && (count < instruction.Size || _defined[(ushort)(pc + count)]); count++)
        {
            bytes[count] = _memory[(ushort)(pc + count)];
        }

        bytes = bytes[..count];
        return _evaluator.TryRun(pc, bytes, _registers, ref flags, static _ => -1, out _);
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
        frames.RemoveAt(frames.Count - 1);
        bool matches = top.Bytes == bytes && top.Units.Count == targets.Count;
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
        new(JoinOrigin(first.Origin, second.Origin), first.Constant == second.Constant ? first.Constant : -1);

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
