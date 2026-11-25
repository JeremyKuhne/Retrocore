// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using Retrocore.Assembler;
using Retrocore.Debug;
using Retrocore.Machines.Apple2;

namespace Retrocore.Tests;

/// <summary>
///  Pins behavior of the Integer BASIC ROM that its source documents as a bug, so the bytes are never "fixed"
///  (docs/conversions/IntegerBasic.md). The ROMs are the SDK's, so no dumps are needed.
/// </summary>
[TestClass]
public class IntegerBasicQuirkTests
{
    private static readonly string s_inputs = Path.Join(AppContext.BaseDirectory, "Inputs");

    /// <summary>
    ///  <c>INPUT</c> of a number leaves the run flag set whatever it was, so in a line typed without a number (reached
    ///  through <c>IF ... THEN</c>) the run loop takes the typed line for a program line: the program in memory does
    ///  not run, and BASIC stops answering the keyboard (Statements::InputNumber in Messages.asm).
    /// </summary>
    [TestMethod]
    public void ImmediateInputOfANumberLeavesBasicInTheRunLoop()
    {
        AssemblyResult basic = SdkModules.AssembleIntegerBasic(SdkModules.IntegerBasicPath(s_inputs));
        ushort running = (ushort)basic.SymbolsWithHistoricalNames["RUNFLAG"];
        Apple2Machine machine = new(Apple2Model.II, SdkModules.BuildRoms(Apple2Model.II, s_inputs, autostart: true));
        machine.Run(cycles: 2_000_000);
        Screen(machine).Should().Contain(">");

        Type(machine, "10 PRINT 111*3\r");
        machine.Bus.Peek(running).Should().Be(0, "BASIC is at its prompt, not running a program");
        Type(machine, "PRINT 6*7\r");
        Screen(machine).Should().Contain("42", "BASIC answers a typed line before the INPUT");
        Type(machine, "IF 1 THEN INPUT A\r");
        Type(machine, "5\r");
        machine.Bus.Peek(running).Should().Be(0xFF, "INPUT leaves the run flag set");

        Type(machine, "PRINT 5*9\r");
        Screen(machine).Should().NotContain("333", "the program does not run").And.NotContain("PRINT 5*9", "keys go unanswered");
    }

    private static void Type(Apple2Machine machine, string keys)
    {
        foreach (char key in keys)
        {
            machine.Bus.QueueKey((byte)key);
            machine.Run(cycles: 50_000);
        }

        machine.Run(cycles: 500_000);
    }

    private static string Screen(Apple2Machine machine) => string.Join(
        "\n",
        Enumerable.Range(0, 24).Select(row => new string([.. Enumerable.Range(0, 40)
            .Select(column => (char)(machine.Bus.TextByte(row, column) & 0x7F))])));
}
