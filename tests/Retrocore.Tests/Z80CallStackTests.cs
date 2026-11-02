// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using Retrocore.Cpu.Z80;
using Retrocore.Debug;

namespace Retrocore.Tests;

/// <summary>
///  The Z80 call tracker and the Z80's <c>Keeps:</c> checks, from scripted instructions.
/// </summary>
[TestClass]
public class Z80CallStackTests
{
    private static readonly DebugRegisters s_registers = new(Z80Isa.Description);

    /// <summary>
    ///  CALL and RST push frames that a RET pops; PUSH is not a call.
    /// </summary>
    [TestMethod]
    public void CallsAndRestartsPushFramesThatReturnsPop()
    {
        DebugTestMemory memory = new();
        Z80CallStack stack = new(memory);

        // $7000: CALL $7100.
        memory.Set(0x7000, 0xCD, 0x00, 0x71);
        Step(stack, memory, Frame(0x7000, 0x8000), Frame(0x7100, 0x7FFE), push: 0x7003);
        stack.Depth().Should().Be(1);
        stack.ReturnTarget().Should().Be(((ushort)0x7003, 0x8000));

        // $7100: PUSH HL, then RST $08.
        memory.Set(0x7100, 0xE5, 0xCF);
        Step(stack, memory, Frame(0x7100, 0x7FFE), Frame(0x7101, 0x7FFC), push: 0x1234);
        stack.Depth().Should().Be(1);
        Step(stack, memory, Frame(0x7101, 0x7FFC), Frame(0x0008, 0x7FFA), push: 0x7102);
        stack.Frames(Frame(0x0008, 0x7FFA)).Select(frame => frame.ProgramCounter)
            .Should().Equal((ushort)0x0008, (ushort)0x7101, (ushort)0x7000);

        // RST $08's routine returns past an inline byte, which ends its frame all the same.
        memory.Set(0x0008, 0xC9);
        Step(stack, memory, Frame(0x0008, 0x7FFA), Frame(0x7103, 0x7FFC), push: null);
        stack.Depth().Should().Be(1);
    }

    /// <summary>
    ///  An interrupt pushes the address of the instruction it interrupted, and loading SP starts over.
    /// </summary>
    [TestMethod]
    public void InterruptsPushFramesAndLoadingStackPointerResets()
    {
        DebugTestMemory memory = new();
        Z80CallStack stack = new(memory);
        memory.Set(0x7000, 0x00);
        Step(stack, memory, Frame(0x7000, 0x8000), Frame(0x0038, 0x7FFE), push: 0x7000);
        stack.Depth().Should().Be(1);

        memory.Set(0x0038, 0x31, 0x00, 0x60);
        Step(stack, memory, Frame(0x0038, 0x7FFE), Frame(0x003B, 0x6000), push: null);
        stack.Depth().Should().Be(0);
    }

    /// <summary>
    ///  A Z80 Keeps: section names registers by their letters and flags by their words, so C is the register and
    ///  carry the flag.
    /// </summary>
    [TestMethod]
    public void ContractsCheckZ80RegistersAndFlags()
    {
        DebugContract contract = new("ROUTINE", ["HL", "C", "carry"], [], Changes: null);
        DebugContracts contracts = new(address => address == 0x7100 ? contract : null, checkChanges: false, s_registers, ["A", "B"]);
        DebugTestMemory memory = new();

        DebugFrame entry = Frame(0x7000, 0x8000);
        entry[s_registers.IndexOf("HL")] = 0x4000;
        entry[s_registers.IndexOf("C")] = 0x05;
        entry[s_registers.IndexOf("F")] = 0x01;
        contracts.Observe(entry, (0x7100, 3), memory.Peek).Should().BeEmpty();

        // HL and the carry change; register C keeps its value.
        DebugFrame exit = Frame(0x7003, 0x8000);
        exit[s_registers.IndexOf("HL")] = 0x4001;
        exit[s_registers.IndexOf("C")] = 0x05;
        exit[s_registers.IndexOf("F")] = 0x00;
        List<string> broken = contracts.Observe(exit, call: null, memory.Peek);
        broken.Should().HaveCount(2);
        broken.Should().Contain(message => message.Contains("HL changed", StringComparison.Ordinal));
        broken.Should().Contain(message => message.Contains("carry changed", StringComparison.Ordinal));
    }

    /// <summary>
    ///  Contracts built from documentation read a Z80 Out: entry's flag word as the flag, never register C.
    /// </summary>
    [TestMethod]
    public void RegistersNameFlagsByWord()
    {
        s_registers.Knows("carry").Should().BeTrue();
        s_registers.Knows("parity").Should().BeTrue();
        s_registers.Knows("overflow").Should().BeTrue();
        s_registers.Knows("C").Should().BeTrue("C is the register");
        s_registers.Knows("NZ").Should().BeFalse();

        DebugFrame frame = Frame(0, 0);
        frame[s_registers.IndexOf("C")] = 0x00;
        frame[s_registers.IndexOf("F")] = 0x05;
        s_registers.Kept(frame, "C").Should().Be(0, "C reads the register, not the carry");
        s_registers.Kept(frame, "carry").Should().Be(1);
        s_registers.Kept(frame, "parity").Should().Be(4);
    }

    private static DebugFrame Frame(ushort pc, int sp) => new() { ProgramCounter = pc, StackPointer = sp };

    // One instruction: what it pushes lands at the new stack pointer.
    private static void Step(Z80CallStack stack, DebugTestMemory memory, DebugFrame before, DebugFrame after, ushort? push)
    {
        if (push is { } value) { memory.Set((ushort)after.StackPointer, (byte)value, (byte)(value >> 8)); }
        stack.Complete(before, after);
    }
}
