// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using Retrocore.Machines.Apple2;

namespace Retrocore.Tests;

/// <summary>
///  Verifies the IIe's special keys: CONTROL-C, the Apple keys and CONTROL-RESET.
/// </summary>
[TestClass]
public sealed class Apple2KeyboardTests
{
    /// <summary>
    ///  CONTROL-C stops a running program even with an unread key latched, which BASIC never takes while it runs.
    /// </summary>
    [TestMethod]
    public void ControlCBreaksPastAnUnreadKey()
    {
        Apple2Machine machine = BasicMachines.BootIIe(Apple2Model.IIeEnhanced);
        BasicMachines.TypeLine(machine, "10 GOTO 10");
        BasicMachines.TypeLine(machine, "RUN");
        machine.Bus.QueueKey((byte)'X');
        machine.Run(BasicMachines.IIeClock / 4);

        machine.Bus.QueueKey(3);
        machine.Run(BasicMachines.IIeClock / 2);
        Screen(machine).Should().Contain("BREAK IN 10");
    }

    /// <summary>
    ///  The Apple keys read in bit 7 of $C061 and $C062 while they are down.
    /// </summary>
    [TestMethod]
    public void AppleKeysReadAsButtons()
    {
        Apple2Machine machine = BasicMachines.BootIIe(Apple2Model.IIeEnhanced);
        (machine.Bus.Peek(0xC061) & 128).Should().Be(0);
        machine.Bus.SetButton(0, pressed: true);
        (machine.Bus.Peek(0xC061) & 128).Should().Be(128, "Open Apple is down");
        (machine.Bus.Peek(0xC062) & 128).Should().Be(0, "Closed Apple is up");
        machine.Bus.SetButton(1, pressed: true);
        machine.Bus.SetButton(0, pressed: false);
        (machine.Bus.Peek(0xC061) & 128).Should().Be(0);
        (machine.Bus.Peek(0xC062) & 128).Should().Be(128, "Closed Apple is down");
    }

    /// <summary>
    ///  CONTROL-RESET stops a program and returns to BASIC's prompt, keeping the program.
    /// </summary>
    [TestMethod]
    public void ControlResetReturnsToThePrompt()
    {
        Apple2Machine machine = BasicMachines.BootIIe(Apple2Model.IIeEnhanced);
        BasicMachines.TypeLine(machine, "10 GOTO 10");
        BasicMachines.TypeLine(machine, "RUN");
        machine.Run(BasicMachines.IIeClock / 4);

        machine.Reset();
        machine.Run(BasicMachines.IIeClock);
        BasicMachines.TypeLine(machine, "LIST");
        Screen(machine).Should().Contain("10  GOTO 10");
    }

    private static string Screen(Apple2Machine machine)
    {
        char[] text = new char[24 * 41];
        for (int row = 0; row < 24; row++)
        {
            for (int column = 0; column < 40; column++)
            {
                text[row * 41 + column] = (char)(machine.Bus.TextByte(row, column) & 127);
            }

            text[row * 41 + 40] = '\n';
        }

        return new string(text);
    }
}
