// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Debug;

/// <summary>
///  Tracks a 6809's calls on the S stack: <c>JSR</c>, <c>BSR</c>, <c>LBSR</c>, the three <c>SWI</c>s and interrupts.
/// </summary>
/// <remarks>
///  <para>
///   A call is an instruction that lowers S by two and leaves its return address there, big-endian. An interrupt or
///   <c>SWI</c> stacks the whole register set, twelve bytes with PC on top of the rest, or FIRQ three bytes, CC and
///   PC. A call is dropped once S rises past it or its return address is overwritten; <c>LDS</c> starts a new stack.
///  </para>
/// </remarks>
internal sealed class M6809CallStack : IDebugCallStack
{
    private const int MaximumCalls = 256;

    // The frame's S and PC entries, in the instruction set's register order A B D X Y U S DP CC PC.
    private const int RegisterS = 6;

    private readonly IDebugMemory _memory;
    private readonly List<(DebugFrame Caller, ushort Return, int Stack, bool Interrupt)> _calls = [];
    private int _stack = -1;

    /// <summary>
    ///  Creates the stack over a machine's memory.
    /// </summary>
    /// <param name="memory">The memory.</param>
    internal M6809CallStack(IDebugMemory memory) => _memory = memory;

    /// <inheritdoc/>
    public void Reset()
    {
        _calls.Clear();
        _stack = -1;
    }

    /// <summary>
    ///  Records what an instruction, or an interrupt's entry, did to the stack.
    /// </summary>
    /// <param name="before">The registers before.</param>
    /// <param name="after">The registers after.</param>
    internal void Complete(in DebugFrame before, in DebugFrame after)
    {
        _stack = after.StackPointer;
        ushort pc = before.ProgramCounter;
        byte opcode = _memory.Peek(pc);
        byte next = _memory.Peek((ushort)(pc + 1));

        // LDS in any mode moves to another stack.
        if (opcode == 0x10 && next is 0xCE or 0xDE or 0xEE or 0xFE)
        {
            Reset();
            _stack = after.StackPointer;
            return;
        }

        int lowered = (before.StackPointer - after.StackPointer) & 0xFFFF;
        switch (lowered)
        {
            case 2 when CallLength(pc) is int length && length != 0:
                ushort stored = Word(after.StackPointer);
                if (stored == (ushort)(pc + length)) { Push(before, stored, after.StackPointer, interrupt: false); }
                break;
            case 12:
                // PC sits above CC, A, B, DP, X, Y and U.
                ushort entire = Word(after.StackPointer + 10);
                bool software = CallLength(pc) is int swi && swi != 0 && entire == (ushort)(pc + swi);
                if (software || entire == pc) { Push(before, entire, after.StackPointer + 10, interrupt: !software); }
                break;
            case 3:
                ushort fast = Word(after.StackPointer + 1);
                if (fast == pc) { Push(before, fast, after.StackPointer + 1, interrupt: true); }
                break;
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
    ///  Gets a call instruction's length and target.
    /// </summary>
    /// <param name="memory">The memory.</param>
    /// <param name="address">The instruction's address.</param>
    /// <param name="directPage">DP, for <c>JSR</c> direct.</param>
    /// <returns>
    ///  The target and length, the target 0 for <c>JSR</c> indexed, whose target depends on the registers, and the
    ///  vector's address for an <c>SWI</c>; or null when the instruction is not a call.
    /// </returns>
    internal static (ushort Target, int Length)? CallAt(IDebugMemory memory, ushort address, byte directPage)
    {
        byte opcode = memory.Peek(address);
        byte first = memory.Peek((ushort)(address + 1));
        byte second = memory.Peek((ushort)(address + 2));
        return opcode switch
        {
            0xBD => ((ushort)((first << 8) | second), 3),
            0x9D => ((ushort)((directPage << 8) | first), 2),
            0xAD => (0, 1 + IndexedSize(first)),
            0x8D => ((ushort)(address + 2 + (sbyte)first), 2),
            0x17 => ((ushort)(address + 3 + (short)((first << 8) | second)), 3),
            0x3F => (0xFFFA, 1),
            0x10 when first == 0x3F => (0xFFF4, 2),
            0x11 when first == 0x3F => (0xFFF2, 2),
            _ => null
        };
    }

    // The bytes an indexed postbyte and its offset take.
    private static int IndexedSize(byte postbyte)
    {
        if ((postbyte & 0x80) == 0) { return 1; }
        return (postbyte & 0x0F) switch
        {
            8 or 12 => 2,
            9 or 13 => 3,
            15 => 3,
            _ => 1
        };
    }

    private int? CallLength(ushort pc) => CallAt(_memory, pc, directPage: 0)?.Length;

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

    // The 6809 stores words high byte first.
    private ushort Word(int address) =>
        (ushort)((_memory.Peek((ushort)address) << 8) | _memory.Peek((ushort)(address + 1)));
}
