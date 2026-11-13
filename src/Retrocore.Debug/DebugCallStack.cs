// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using Retrocore.Machines.Apple2;

namespace Retrocore.Debug;

/// <summary>
///  Tracks observed subroutine and interrupt entry on a 6502, rather than guessing callers from arbitrary stack bytes.
/// </summary>
/// <remarks>
///  <para>
///   A machine can have more than one stack page, as the IIe's auxiliary zero page or the Apple III's movable stack.
///   The machine names the stack in use when a call is made, and reads that stack's bytes when the call is checked.
///  </para>
/// </remarks>
internal sealed class DebugCallStack : IDebugCallStack
{
    private readonly Func<int> _currentStack;
    private readonly Func<int, byte, byte> _readStack;
    private readonly List<(ProcessorRegisters Caller, ushort Return, byte Stack, int Depth, bool Interrupt, int Page)> _calls = [];
    private ProcessorRegisters _beforeInstruction;
    private ProcessorRegisters? _beforeInterrupt;
    private byte _opcode;
    private bool _instruction;
    private int _page;
    private int _interruptWrites;
    private int _depth;

    /// <summary>
    ///  Creates the tracker for an Apple II: the stack is main or auxiliary page one.
    /// </summary>
    /// <param name="bus">The machine's memory, whose stack page holds the return addresses.</param>
    internal DebugCallStack(Apple2Bus bus)
        : this(
            () => (bus.Switches & Apple2Switches.AltZeroPage) != 0 ? 1 : 0,
            (page, offset) => (page == 1 ? bus.AuxiliaryMemory : bus.MainMemory)[0x100 | offset])
    {
    }

    /// <summary>
    ///  Creates the tracker for a machine whose stack page is plain RAM.
    /// </summary>
    /// <param name="peek">Reads memory without side effects.</param>
    internal DebugCallStack(Func<ushort, byte> peek)
        : this(() => 0, (_, offset) => peek((ushort)(0x100 | offset)))
    {
    }

    /// <summary>
    ///  Creates the tracker for a machine that says which stack is in use and reads it.
    /// </summary>
    /// <param name="currentStack">Names the stack in use, as the machine numbers its stacks.</param>
    /// <param name="readStack">Reads a byte of a stack: the stack's number, then the byte's offset in the page.</param>
    internal DebugCallStack(Func<int> currentStack, Func<int, byte, byte> readStack)
    {
        _currentStack = currentStack;
        _readStack = readStack;
    }

    /// <inheritdoc/>
    public void Reset()
    {
        _calls.Clear();
        _instruction = false;
        _beforeInterrupt = null;
        _interruptWrites = 0;
        _depth = 0;
    }

    /// <summary>
    ///  Observes a completed CPU cycle and the register state on either side of it.
    /// </summary>
    /// <param name="cycle">The completed cycle.</param>
    /// <param name="before">Registers before the cycle.</param>
    /// <param name="after">Registers after the cycle.</param>
    /// <param name="wasBoundary">Whether the CPU was at an instruction boundary before the cycle.</param>
    /// <param name="isBoundary">Whether the CPU completed a sequence during this cycle.</param>
    internal void Observe(
        ProcessorCycle cycle,
        ProcessorRegisters before,
        ProcessorRegisters after,
        bool wasBoundary,
        bool isBoundary)
    {
        if (cycle.IsStalled) { return; }
        if (cycle.IsOpcodeFetch)
        {
            _beforeInstruction = before;
            _opcode = cycle.Value;
            _instruction = true;
            _page = _currentStack();
        }
        else if (!_instruction && wasBoundary && cycle.Operation == BusOperation.Read)
        {
            _beforeInterrupt = before;
            _interruptWrites = 0;
            _page = _currentStack();
        }

        if (!_instruction
            && _beforeInterrupt is not null
            && cycle.Operation == BusOperation.Write
            && cycle.Address is >= 0x100 and <= 0x1FF)
        {
            _interruptWrites++;
        }

        if (!isBoundary) { return; }
        if (_instruction)
        {
            CompleteInstruction(after);
            _instruction = false;
        }
        else if (_beforeInterrupt is { } interrupted
            && _interruptWrites == 3
            && after.StackPointer == (byte)(interrupted.StackPointer - 3))
        {
            Push(interrupted, after.StackPointer, interrupted.ProgramCounter, interrupt: true);
        }
        else
        {
            Reset();
        }

        _beforeInterrupt = null;
        Prune();
    }

    /// <inheritdoc/>
    public DebugFrame[] Frames(in DebugFrame current)
    {
        Prune();
        DebugFrame[] frames = new DebugFrame[_calls.Count + 1];
        frames[0] = current;
        for (int i = 0; i < _calls.Count; i++)
        {
            frames[i + 1] = M6502Frames.Of(_calls[_calls.Count - i - 1].Caller);
        }

        return frames;
    }

    /// <inheritdoc/>
    public int Depth()
    {
        Prune();
        return _calls.Count;
    }

    /// <inheritdoc/>
    public (ushort Address, int StackPointer)? ReturnTarget()
    {
        Prune();
        return _calls.Count == 0 ? null : (_calls[^1].Return, _calls[^1].Caller.StackPointer);
    }

    private void CompleteInstruction(ProcessorRegisters after)
    {
        switch (_opcode)
        {
            case 0x20:
                if (after.StackPointer == (byte)(_beforeInstruction.StackPointer - 2))
                {
                    Push(
                        _beforeInstruction,
                        after.StackPointer,
                        (ushort)(_beforeInstruction.ProgramCounter + 3),
                        interrupt: false);
                }

                break;
            case 0x00:
                Push(
                    _beforeInstruction,
                    after.StackPointer,
                    (ushort)(_beforeInstruction.ProgramCounter + 2),
                    interrupt: true);

                break;
            case 0x48:
            case 0x08:
            case 0xDA when after.StackPointer == (byte)(_beforeInstruction.StackPointer - 1):
            case 0x5A when after.StackPointer == (byte)(_beforeInstruction.StackPointer - 1):
                _depth++;
                break;
            case 0x68:
            case 0x28:
            case 0xFA when after.StackPointer == (byte)(_beforeInstruction.StackPointer + 1):
            case 0x7A when after.StackPointer == (byte)(_beforeInstruction.StackPointer + 1):
                _depth = Math.Max(_depth - 1, 0);
                break;
            case 0x60: _depth = Math.Max(_depth - 2, 0);
                break;
            case 0x40: _depth = Math.Max(_depth - 3, 0);
                break;
            case 0x9A when after.StackPointer != _beforeInstruction.StackPointer: Reset();
                break;
        }
    }

    private void Push(ProcessorRegisters caller, byte stack, ushort returnAddress, bool interrupt)
    {
        _depth += interrupt ? 3 : 2;
        _calls.Add((caller, returnAddress, stack, _depth, interrupt, _page));
    }

    private void Prune()
    {
        for (int i = _calls.Count - 1; i >= 0; i--)
        {
            var call = _calls[i];
            int offset = call.Interrupt ? 2 : 1;
            ushort stored = (ushort)(_readStack(call.Page, (byte)(call.Stack + offset))
                    | (_readStack(call.Page, (byte)(call.Stack + offset + 1)) << 8));

            ushort expected = call.Interrupt ? call.Return : (ushort)(call.Return - 1);
            if (call.Depth > _depth || _depth - call.Depth >= 256 || stored != expected)
            {
                _calls.RemoveAt(i);
            }
        }
    }
}
