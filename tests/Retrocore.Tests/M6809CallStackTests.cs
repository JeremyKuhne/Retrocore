// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using Retrocore.Debug;

namespace Retrocore.Tests;

/// <summary>
///  The debugger's 6809 call stack: calls, interrupts and their returns on the S stack, big-endian.
/// </summary>
[TestClass]
public class M6809CallStackTests
{
    /// <summary>
    ///  <c>JSR</c> pushes a frame returning after it, and <c>RTS</c> pops it.
    /// </summary>
    [TestMethod]
    public void JsrAndRtsPushAndPopAFrame()
    {
        DebugTestMemory memory = new();
        memory.Set(0x1000, 0xBD, 0x20, 0x00);
        memory.Set(0x2000, 0x39);
        M6809CallStack calls = new(memory);

        memory.Set(0x7EFE, 0x10, 0x03);
        calls.Complete(Frame(0x1000, 0x7F00), Frame(0x2000, 0x7EFE));
        calls.Depth().Should().Be(1);
        calls.ReturnTarget().Should().Be(((ushort)0x1003, 0x7F00));

        calls.Complete(Frame(0x2000, 0x7EFE), Frame(0x1003, 0x7F00));
        calls.Depth().Should().Be(0);
    }

    /// <summary>
    ///  An IRQ stacks all twelve bytes, PC on top of the rest, and returns to the interrupted instruction.
    /// </summary>
    [TestMethod]
    public void InterruptsStackTheWholeFrame()
    {
        DebugTestMemory memory = new();
        memory.Set(0x1234, 0x12);
        M6809CallStack calls = new(memory);

        memory.Set(0x7EF4 + 10, 0x12, 0x34);
        calls.Complete(Frame(0x1234, 0x7F00), Frame(0x3000, 0x7EF4));
        calls.Depth().Should().Be(1);
        calls.ReturnTarget().Should().Be(((ushort)0x1234, 0x7F00));

        // RTI pulls the frame.
        memory.Set(0x3000, 0x3B);
        calls.Complete(Frame(0x3000, 0x7EF4), Frame(0x1234, 0x7F00));
        calls.Depth().Should().Be(0);
    }

    /// <summary>
    ///  <c>LDS</c> starts another stack, forgetting the calls on the old one.
    /// </summary>
    [TestMethod]
    public void LdsStartsANewStack()
    {
        DebugTestMemory memory = new();
        memory.Set(0x1000, 0xBD, 0x20, 0x00);
        memory.Set(0x2000, 0x10, 0xCE, 0x60, 0x00);
        memory.Set(0x7EFE, 0x10, 0x03);
        M6809CallStack calls = new(memory);
        calls.Complete(Frame(0x1000, 0x7F00), Frame(0x2000, 0x7EFE));
        calls.Complete(Frame(0x2000, 0x7EFE), Frame(0x2004, 0x6000));
        calls.Depth().Should().Be(0);
    }

    /// <summary>
    ///  Calls report their target and length, so step over runs to the instruction after them.
    /// </summary>
    /// <param name="bytes">The instruction.</param>
    /// <param name="target">Its target, 0 when the registers decide it.</param>
    /// <param name="length">Its length.</param>
    [TestMethod]
    [DataRow(new byte[] { 0xBD, 0x20, 0x00 }, 0x2000, 3)]          // JSR extended
    [DataRow(new byte[] { 0x9D, 0x40 }, 0x2040, 2)]                // JSR direct, DP $20
    [DataRow(new byte[] { 0xAD, 0x84 }, 0, 2)]                     // JSR ,X
    [DataRow(new byte[] { 0xAD, 0x89, 0x01, 0x00 }, 0, 4)]         // JSR $100,X
    [DataRow(new byte[] { 0xAD, 0x9F, 0xA0, 0x02 }, 0, 4)]         // JSR [$A002]
    [DataRow(new byte[] { 0x8D, 0xFE }, 0x1000, 2)]                // BSR to itself
    [DataRow(new byte[] { 0x17, 0x00, 0x10 }, 0x1013, 3)]          // LBSR
    [DataRow(new byte[] { 0x3F }, 0xFFFA, 1)]                      // SWI
    [DataRow(new byte[] { 0x10, 0x3F }, 0xFFF4, 2)]                // SWI2
    public void CallsKnowTheirLength(byte[] bytes, int target, int length)
    {
        DebugTestMemory memory = new();
        memory.Set(0x1000, bytes);
        M6809CallStack.CallAt(memory, 0x1000, directPage: 0x20).Should().Be(((ushort)target, length));
    }

    /// <summary>
    ///  Other instructions are not calls.
    /// </summary>
    [TestMethod]
    public void OtherInstructionsAreNotCalls()
    {
        DebugTestMemory memory = new();
        memory.Set(0x1000, 0x7E, 0x20, 0x00);
        M6809CallStack.CallAt(memory, 0x1000, directPage: 0).Should().BeNull();
    }

    private static DebugFrame Frame(ushort pc, int stack) => new() { ProgramCounter = pc, StackPointer = stack };
}
