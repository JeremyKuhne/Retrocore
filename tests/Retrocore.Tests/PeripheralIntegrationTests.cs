// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using Retrocore.Machines.Apple2;

namespace Retrocore.Tests;

/// <summary>
///  Checks actual CPU bus access, peripheral clocking, slot mapping and IRQ routing.
/// </summary>
[TestClass]
public class PeripheralIntegrationTests
{
    /// <summary>
    ///  Checks slot-four peeks retain flags and internal ROM selection hides card registers.
    /// </summary>
    [TestMethod]
    public void MockingboardMappingAndPeeksRespectInternalRom()
    {
        Apple2Bus bus = new(new Apple2Roms(new byte[16384], new byte[4096]));
        bus.InstallMockingboard();
        bus.Write(0xC40E, value: 0xC0);
        bus.Write(0xC404, value: 1);
        bus.Write(0xC405, value: 0);
        for (int clock = 0; clock < 8; clock++) { bus.Tick(); }
        (bus.Peek(0xC40D) & 0xC0).Should().Be(0xC0);
        bus.Peek(0xC404);
        (bus.Peek(0xC40D) & 0x40).Should().Be(0x40);
        bus.Read(0xC404);
        (bus.Peek(0xC40D) & 0x40).Should().Be(0);
        bus.Write(0xC007, value: 0);
        bus.Read(0xC40E).Should().Be(0);
    }

    /// <summary>
    ///  The Mockingboard is out of slot 4 until it is put in: its space floats, and taking it out again drops its
    ///  interrupt.
    /// </summary>
    [TestMethod]
    public void MockingboardIsACardPutInAndTakenOut()
    {
        Apple2Bus bus = new(new Apple2Roms(new byte[16384], new byte[4096]));
        bus.MockingboardInstalled.Should().BeFalse();
        bus.Write(0xC40E, value: 0xC0);
        bus.Peek(0xC40E).Should().Be(0xFF, "nothing answers in slot 4");

        bus.InstallMockingboard();
        bus.IsSlotFree(4).Should().BeFalse();
        bus.Write(0xC40E, value: 0xC0);
        bus.Write(0xC404, value: 1);
        bus.Write(0xC405, value: 0);
        for (int clock = 0; clock < 8; clock++) { bus.Tick(); }
        bus.Mockingboard.InterruptRequested.Should().BeTrue();

        bus.RemoveMockingboard();
        bus.Mockingboard.InterruptRequested.Should().BeFalse();
        bus.IsSlotFree(4).Should().BeTrue();
        Action twice = bus.RemoveMockingboard;
        twice.Should().Throw<InvalidOperationException>();
    }

    /// <summary>
    ///  Checks the IRQ level from a VIA timer actually takes the CPU through its IRQ vector.
    /// </summary>
    [TestMethod]
    public void ViaTimerInterruptReachesTheCpu()
    {
        byte[] rom = new byte[16384];
        rom[0x3FFC] = 0;
        rom[0x3FFD] = 0x60;
        rom[0x3FFE] = 0;
        rom[0x3FFF] = 0x61;
        Apple2Machine machine = new(Apple2Model.IIe, new Apple2Roms(rom, new byte[4096]));
        machine.Bus.InstallMockingboard();
        byte[] main = [0x58,0xEA,0x4C,0x01,0x60];
        byte[] handler = [0xAD,0x04,0xC4,0x40];
        for (int index = 0; index < main.Length; index++)
        {
            machine.Bus.SetRam(auxiliary: false, (ushort)(0x6000 + index), main[index]);
        }

        for (int index = 0; index < handler.Length; index++)
        {
            machine.Bus.SetRam(auxiliary: false, (ushort)(0x6100 + index), handler[index]);
        }

        machine.Run(cycles: 7);
        machine.Bus.Write(0xC40E, value: 0xC0);
        machine.Bus.Write(0xC404, value: 1);
        machine.Bus.Write(0xC405, value: 0);
        bool entered = false;
        for (int clock = 0; clock < 100; clock++)
        {
            machine.StepCycle();
            entered |= machine.Processor.Registers.ProgramCounter == 0x6100;
        }

        entered.Should().BeTrue();
        machine.Bus.Mockingboard.InterruptRequested.Should().BeFalse();
    }

    /// <summary>
    ///  Checks speaker aliases toggle only on real accesses, never debugger peeks.
    /// </summary>
    [TestMethod]
    public void SpeakerAliasesAndDeviceResetAreExplicit()
    {
        Apple2Bus bus = new(new Apple2Roms(new byte[16384], new byte[4096]));
        bus.Read(0xC03F);
        bus.Speaker.Should().BeTrue();
        bus.Peek(0xC030);
        bus.Speaker.Should().BeTrue();
        bus.Write(0xC031, value: 0);
        bus.Speaker.Should().BeFalse();
        bus.Read(0xC030);
        bus.ResetDevices();
        bus.Speaker.Should().BeFalse();
    }
}
