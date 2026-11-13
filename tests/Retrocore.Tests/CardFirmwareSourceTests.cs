// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using Retrocore.Debug;
using Retrocore.Machines.Apple2;

namespace Retrocore.Tests;

/// <summary>
///  Verifies that the mouse and ProFile cards' firmware, which works in any slot, debugs at its source in whatever slot
///  the card is in.
/// </summary>
[TestClass]
public sealed class CardFirmwareSourceTests
{
    private static readonly string s_inputs = Path.Join(AppContext.BaseDirectory, "Inputs");

    /// <summary>
    ///  Each card's page maps to its own source at its own lines, its routines' names resolve to the slot it is in, and
    ///  once it is out the page has no source.
    /// </summary>
    /// <param name="mouseSlot">The mouse card's slot.</param>
    /// <param name="proFileSlot">The ProFile card's slot.</param>
    [TestMethod]
    [DataRow(4, 5)]
    [DataRow(2, 7)]
    [DataRow(7, 1)]
    public void FirmwareDebugsInItsSlot(int mouseSlot, int proFileSlot)
    {
        Apple2Machine machine = new(Apple2Model.IIeEnhanced, SdkModules.BuildRoms(Apple2Model.IIeEnhanced, s_inputs));
        machine.Bus.InstallMouse(mouseSlot);
        machine.Bus.InstallProFile(proFileSlot);
        DebugInfo debug = new();
        SdkModules.AddTo(debug, Apple2Model.IIeEnhanced, s_inputs);
        Apple2TestMemory memory = new(machine.Bus);

        ushort setMouse = (ushort)debug.Resolve("SETMOUSE", memory);
        (setMouse >> 8).Should().Be(0xC0 | mouseSlot);
        (setMouse & 0xFF).Should().Be(MouseRom.SETMOUSE & 0xFF);
        AtLabel(debug, memory, setMouse, "Mouse.rom.asm", "SETMOUSE");

        ushort driver = (ushort)debug.Resolve("Driver", memory);
        (driver >> 8).Should().Be(0xC0 | proFileSlot);
        (driver & 0xFF).Should().Be(ProFileRom.Driver & 0xFF);
        AtLabel(debug, memory, driver, "ProFile.rom.asm", "Driver");
        debug.Label(memory, (ushort)(driver + 2)).Should().Be("Driver");

        machine.Bus.RemoveMouse();
        machine.Bus.RemoveProFile(proFileSlot);
        debug.Position(memory, setMouse).Should().BeNull("the mouse card is out");
        debug.Position(memory, driver).Should().BeNull("the ProFile card is out");
    }

    /// <summary>
    ///  A line in the firmware has an entry in every slot, so a breakpoint there stops wherever the card is.
    /// </summary>
    [TestMethod]
    public void LineHasAnEntryInEverySlot()
    {
        DebugInfo debug = new();
        SdkModules.AddTo(debug, Apple2Model.IIeEnhanced, s_inputs);
        string source = Path.GetFullPath(Path.Join(s_inputs, "ProFile.rom.asm"));
        int line = Array.IndexOf(File.ReadAllLines(source), "Driver:") + 2;
        List<ushort> entries = [.. debug.Modules.SelectMany(module => module.Entries(source, line))];
        entries.Order().Should().Equal(Enumerable.Range(1, 7).Select(slot => (ushort)((0xC0 | slot) << 8 | (ProFileRom.Driver & 0xFF))));
    }

    // The outermost line, the invocation where a routine is a macro call, follows the routine's label.
    private static void AtLabel(DebugInfo debug, Apple2TestMemory memory, ushort address, string file, string label)
    {
        SourceLine line = debug.Position(memory, address)?.Chain[^1] ?? throw new AssertFailedException("No source.");
        Path.GetFileName(line.Path).Should().Be(file);
        File.ReadAllLines(line.Path)[line.Line - 2].Should().Be($"{label}:");
    }
}
