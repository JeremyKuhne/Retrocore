// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using Retrocore.Cpu.I8080;
using Retrocore.Debug;

namespace Retrocore.Tests;

/// <summary>
///  The 8080's and 8085's call tracking, and their registers and flags in <c>Keeps:</c> contracts.
/// </summary>
[TestClass]
public class I8080CallStackTests
{
    private static readonly DebugRegisters s_registers = new(I8080Isa.Description);

    /// <summary>
    ///  CALL, a conditional call and RST push frames; PUSH does not; RET pops them.
    /// </summary>
    [TestMethod]
    public void CallsAndRestartsPushFramesThatReturnsPop()
    {
        DebugTestMemory memory = new();
        I8080CallStack stack = new(memory, is8085: false);

        // $1000: CALL $1100.
        memory.Set(0x1000, 0xCD, 0x00, 0x11);
        Step(stack, memory, Frame(0x1000, 0x8000), Frame(0x1100, 0x7FFE), push: 0x1003);
        stack.Depth().Should().Be(1);
        stack.ReturnTarget().Should().Be(((ushort)0x1003, 0x8000));

        // $1100: PUSH B, then CNZ $1200 taken, then RST 1.
        memory.Set(0x1100, 0xC5, 0xC4, 0x00, 0x12);
        Step(stack, memory, Frame(0x1100, 0x7FFE), Frame(0x1101, 0x7FFC), push: 0x1234);
        stack.Depth().Should().Be(1, "PUSH is not a call");
        Step(stack, memory, Frame(0x1101, 0x7FFC), Frame(0x1200, 0x7FFA), push: 0x1104);
        memory.Set(0x1200, 0xCF);
        Step(stack, memory, Frame(0x1200, 0x7FFA), Frame(0x0008, 0x7FF8), push: 0x1201);
        stack.Frames(Frame(0x0008, 0x7FF8)).Select(frame => frame.ProgramCounter)
            .Should().Equal((ushort)0x0008, (ushort)0x1200, (ushort)0x1101, (ushort)0x1000);

        // RET from the restart.
        memory.Set(0x0008, 0xC9);
        Step(stack, memory, Frame(0x0008, 0x7FF8), Frame(0x1201, 0x7FFA), push: null);
        stack.Depth().Should().Be(2);
    }

    /// <summary>
    ///  The 8080's undocumented $DD is a CALL; on the 8085 it is JNK and $CB is RSTV, a one-byte call.
    /// </summary>
    [TestMethod]
    public void UndocumentedCallsDependOnTheCpu()
    {
        I8080CallStack.CallLength(0xDD, is8085: false).Should().Be(3);
        I8080CallStack.CallLength(0xDD, is8085: true).Should().Be(0);
        I8080CallStack.CallLength(0xCB, is8085: false).Should().Be(0, "on the 8080 $CB is a JMP");
        I8080CallStack.CallLength(0xCB, is8085: true).Should().Be(1);

        DebugTestMemory memory = new();
        I8080CallStack stack = new(memory, is8085: true);
        memory.Set(0x1000, 0xCB);
        Step(stack, memory, Frame(0x1000, 0x8000), Frame(0x0040, 0x7FFE), push: 0x1001);
        stack.Depth().Should().Be(1, "RSTV calls $40");
    }

    /// <summary>
    ///  An interrupt pushes the address of the instruction it comes before, and LXI SP forgets the calls.
    /// </summary>
    [TestMethod]
    public void InterruptsPushFramesAndLoadingStackPointerResets()
    {
        DebugTestMemory memory = new();
        I8080CallStack stack = new(memory, is8085: false);
        memory.Set(0x1000, 0x00);
        Step(stack, memory, Frame(0x1000, 0x8000), Frame(0x0038, 0x7FFE), push: 0x1000);
        stack.Depth().Should().Be(1);

        memory.Set(0x0038, 0x31, 0x00, 0x60);
        Step(stack, memory, Frame(0x0038, 0x7FFE), Frame(0x003B, 0x6000), push: null);
        stack.Depth().Should().Be(0);
    }

    /// <summary>
    ///  Contracts name the 8080's registers and pairs, and its flags by the shared words.
    /// </summary>
    [TestMethod]
    public void ContractsCheckRegistersAndFlags()
    {
        s_registers.Knows("carry").Should().BeTrue();
        s_registers.Knows("parity").Should().BeTrue();
        s_registers.Knows("half-carry").Should().BeTrue();
        s_registers.Knows("PSW").Should().BeTrue();
        s_registers.Knows("C").Should().BeTrue("C is the register");

        DebugContract contract = new("ROUTINE", ["HL", "C", "carry"], [], Changes: null);
        DebugContracts contracts = new(address => address == 0x1100 ? contract : null, checkChanges: false, s_registers, ["A", "B"]);
        DebugTestMemory memory = new();
        DebugFrame entry = Frame(0x1000, 0x8000);
        entry[s_registers.IndexOf("HL")] = 0x4000;
        entry[s_registers.IndexOf("C")] = 0x05;
        entry[s_registers.IndexOf("F")] = 0x03;
        contracts.Observe(entry, (0x1100, 3), memory.Peek).Should().BeEmpty();

        DebugFrame exit = Frame(0x1003, 0x8000);
        exit[s_registers.IndexOf("HL")] = 0x4000;
        exit[s_registers.IndexOf("C")] = 0x05;
        exit[s_registers.IndexOf("F")] = 0x02;
        List<string> broken = contracts.Observe(exit, call: null, memory.Peek);
        broken.Should().ContainSingle().Which.Should().Contain("carry changed");
    }

    private static DebugFrame Frame(ushort pc, int sp) => new() { ProgramCounter = pc, StackPointer = sp };

    // One instruction: what it pushes lands at the new stack pointer.
    private static void Step(I8080CallStack stack, DebugTestMemory memory, DebugFrame before, DebugFrame after, ushort? push)
    {
        if (push is { } value) { memory.Set((ushort)after.StackPointer, (byte)value, (byte)(value >> 8)); }
        stack.Complete(before, after);
    }
}
