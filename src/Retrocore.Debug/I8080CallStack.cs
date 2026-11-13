// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Debug;

/// <summary>
///  The 8080's and 8085's calls and interrupts, found by watching the stack fall by two as each instruction ends, and
///  pruned when their return address leaves the stack.
/// </summary>
/// <remarks>
///  <para>
///   A call is <c>CALL</c>, a conditional call, <c>RST</c>, the 8080's undocumented <c>CALL</c> aliases or the 8085's
///   <c>RSTV</c>, when the word pushed is the address after it. An interrupt pushes the address of the instruction it
///   comes before. <c>PUSH</c> also lowers SP by two and is neither. <c>LXI SP</c> and <c>SPHL</c> move to another
///   stack, which forgets the calls.
///  </para>
/// </remarks>
internal sealed class I8080CallStack : IDebugCallStack
{
    private const int MaximumCalls = 256;

    private readonly IDebugMemory _memory;
    private readonly bool _is8085;
    private readonly List<(DebugFrame Caller, ushort Return, int Stack, bool Interrupt)> _calls = [];
    private int _stack = -1;

    /// <summary>
    ///  Tracks the calls of a CPU.
    /// </summary>
    /// <param name="memory">The memory the stack is in.</param>
    /// <param name="is8085">Whether the CPU is the 8085, whose undocumented opcodes differ from the 8080's.</param>
    internal I8080CallStack(IDebugMemory memory, bool is8085)
    {
        _memory = memory;
        _is8085 = is8085;
    }

    /// <inheritdoc/>
    public void Reset()
    {
        _calls.Clear();
        _stack = -1;
    }

    /// <summary>
    ///  Records what an instruction did to the stack, given the frames before and after it.
    /// </summary>
    /// <param name="before">The registers as the instruction started.</param>
    /// <param name="after">The registers as it ended.</param>
    internal void Complete(in DebugFrame before, in DebugFrame after)
    {
        _stack = after.StackPointer;
        ushort pc = before.ProgramCounter;
        byte opcode = _memory.Peek(pc);

        // LXI SP,nn and SPHL move to another stack.
        if (opcode is 0x31 or 0xF9)
        {
            Reset();
            _stack = after.StackPointer;
            return;
        }

        if (((before.StackPointer - after.StackPointer) & 0xFFFF) == 2)
        {
            ushort stored = Word(after.StackPointer);
            int length = CallLength(opcode, _is8085);
            if (length != 0 && stored == (ushort)(pc + length))
            {
                Push(before, stored, after.StackPointer, interrupt: false);
            }
            else if (stored == pc && (opcode & 0xCF) != 0xC5)
            {
                Push(before, stored, after.StackPointer, interrupt: true);
            }
        }

        Prune();
    }

    /// <inheritdoc/>
    public DebugFrame[] Frames(in DebugFrame current)
    {
        Prune();
        DebugFrame[] frames = new DebugFrame[_calls.Count + 1];
        frames[0] = current;
        for (int i = 0; i < _calls.Count; i++) { frames[i + 1] = _calls[_calls.Count - i - 1].Caller; }
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

    /// <summary>
    ///  Gets the length of a call instruction, or 0 for another: 3 for <c>CALL</c>, the conditional calls and the
    ///  8080's undocumented <c>CALL</c>s at $DD, $ED and $FD; 1 for <c>RST</c> and the 8085's <c>RSTV</c>.
    /// </summary>
    /// <param name="opcode">The opcode.</param>
    /// <param name="is8085">Whether the CPU is the 8085, where $DD, $ED and $FD are not calls and $CB is RSTV.</param>
    /// <returns>The length.</returns>
    internal static int CallLength(byte opcode, bool is8085) => opcode switch
    {
        0xCD or 0xC4 or 0xCC or 0xD4 or 0xDC or 0xE4 or 0xEC or 0xF4 or 0xFC => 3,
        0xDD or 0xED or 0xFD => is8085 ? 0 : 3,
        0xCB => is8085 ? 1 : 0,
        _ when (opcode & 0xC7) == 0xC7 => 1,
        _ => 0
    };

    private void Push(in DebugFrame caller, ushort returnAddress, int stack, bool interrupt)
    {
        if (_calls.Count == MaximumCalls) { _calls.RemoveAt(0); }
        _calls.Add((caller, returnAddress, stack, interrupt));
    }

    private void Prune()
    {
        for (int i = _calls.Count - 1; i >= 0; i--)
        {
            (_, ushort returnAddress, int stack, _) = _calls[i];

            // A stack pointer above the call's slot has unwound past it; one far below is another stack.
            bool unwound = _stack >= 0 && ((stack - _stack) & 0xFFFF) > 0x8000;
            if (unwound || Word(stack) != returnAddress) { _calls.RemoveAt(i); }
        }
    }

    private ushort Word(int address) => (ushort)(_memory.Peek((ushort)address) | (_memory.Peek((ushort)(address + 1)) << 8));
}
