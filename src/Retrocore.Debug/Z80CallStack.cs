// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Debug;

/// <summary>
///  Follows a Z80's calls and interrupts from the registers on either side of each instruction.
/// </summary>
/// <remarks>
///  <para>
///   A <c>CALL</c>, a taken conditional call or an <c>RST</c> pushes its return address; an interrupt or NMI
///   pushes the address of the instruction it interrupted. A call stays in progress while the stack has not
///   unwound past it and its return address is still where the call put it, so a <c>RET</c>, a routine that
///   drops its return address, or one that returns elsewhere (as BASIC's <c>RST $08</c> skips its inline byte)
///   ends it. Loading SP starts over.
///  </para>
/// </remarks>
internal sealed class Z80CallStack : IDebugCallStack
{
    private const int MaximumCalls = 256;

    private readonly IDebugMemory _memory;
    private readonly List<(DebugFrame Caller, ushort Return, int Stack, bool Interrupt)> _calls = [];
    private int _stack = -1;

    /// <summary>
    ///  Creates the tracker.
    /// </summary>
    /// <param name="memory">The machine's memory, which holds the stack.</param>
    internal Z80CallStack(IDebugMemory memory) => _memory = memory;

    /// <inheritdoc/>
    public void Reset()
    {
        _calls.Clear();
        _stack = -1;
    }

    /// <summary>
    ///  Observes a completed instruction, or an interrupt's response.
    /// </summary>
    /// <param name="before">The registers before it.</param>
    /// <param name="after">The registers after it.</param>
    internal void Complete(in DebugFrame before, in DebugFrame after)
    {
        _stack = after.StackPointer;
        ushort pc = before.ProgramCounter;
        byte opcode = _memory.Peek(pc);
        byte next = _memory.Peek((ushort)(pc + 1));

        // LD SP,nn / LD SP,HL / LD SP,IX / LD SP,IY move to another stack.
        if (opcode is 0x31 or 0xF9 || (opcode is 0xDD or 0xFD && next == 0xF9))
        {
            Reset();
            _stack = after.StackPointer;
            return;
        }

        if (((before.StackPointer - after.StackPointer) & 0xFFFF) == 2)
        {
            ushort stored = Word(after.StackPointer);
            int length = CallLength(opcode);
            if (length != 0 && stored == (ushort)(pc + length))
            {
                Push(before, stored, after.StackPointer, interrupt: false);
            }
            else if (stored == pc && !Pushes(opcode, next))
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
    ///  Gets the length of a call instruction.
    /// </summary>
    /// <param name="opcode">The opcode.</param>
    /// <returns>3 for <c>CALL</c>, 1 for <c>RST</c>, or 0 when it is not a call.</returns>
    internal static int CallLength(byte opcode) => opcode switch
    {
        0xCD or 0xC4 or 0xCC or 0xD4 or 0xDC or 0xE4 or 0xEC or 0xF4 or 0xFC => 3,
        _ when (opcode & 0xC7) == 0xC7 => 1,
        _ => 0
    };

    // PUSH rr, PUSH IX and PUSH IY, which also lower SP by two.
    private static bool Pushes(byte opcode, byte next) =>
        (opcode & 0xCF) == 0xC5 || (opcode is 0xDD or 0xFD && next == 0xE5);

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
