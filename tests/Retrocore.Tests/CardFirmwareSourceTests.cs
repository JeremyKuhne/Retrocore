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

        ushort setMouse = (ushort)debug.Resolve("SetMouse", memory);
        debug.Resolve("SETMOUSE", memory).Should().Be(setMouse, "the historical name resolves too");
        (setMouse >> 8).Should().Be(0xC0 | mouseSlot);
        (setMouse & 0xFF).Should().Be(MouseRom.SetMouse & 0xFF);
        AtLabel(debug, memory, setMouse, "Mouse.rom.asm", ".proc SetMouse");

        ushort driver = (ushort)debug.Resolve("Driver", memory);
        (driver >> 8).Should().Be(0xC0 | proFileSlot);
        (driver & 0xFF).Should().Be(ProFileRom.Driver & 0xFF);
        AtLabel(debug, memory, driver, "ProFile.rom.asm", ".proc Driver");
        debug.Label(memory, (ushort)(driver + 2)).Should().Be("Driver");

        machine.Bus.RemoveMouse();
        machine.Bus.RemoveProFile(proFileSlot);
        debug.Position(memory, setMouse).Should().BeNull("the mouse card is out");
        debug.Position(memory, driver).Should().BeNull("the ProFile card is out");
    }

    /// <summary>
    ///  A Disk II's boot ROM starts with the ProFile firmware's LDX #$20, but debugs at its own source: a card's
    ///  firmware maps only where its whole ROM is installed.
    /// </summary>
    [TestMethod]
    public void OtherCardsRomsAreNotTheFirmware()
    {
        Apple2Machine machine = new(Apple2Model.IIeEnhanced, SdkModules.BuildRoms(Apple2Model.IIeEnhanced, s_inputs));
        machine.Bus.InstallDiskII(6, SdkModules.BuildDiskII(sectors: 16, s_inputs));
        DebugInfo debug = new();
        SdkModules.AddTo(debug, Apple2Model.IIeEnhanced, s_inputs);
        Apple2TestMemory memory = new(machine.Bus);

        machine.Bus.Peek(0xC600).Should().Be(ProFileRom.Bytes[0], "both start with LDX #$20");
        machine.Bus.Peek(0xC601).Should().Be(ProFileRom.Bytes[1]);
        string path = debug.Position(memory, 0xC600)?.Chain[^1].Path ?? throw new AssertFailedException("No source.");
        Path.GetFileName(path).Should().NotBe("ProFile.rom.asm");
        List<string> files = [];
        foreach (SourceMapModule module in debug.Modules.OfType<SourceMapModule>())
        {
            if (module.Area is Apple2MemoryArea.Slot6Rom && module.Position(memory, 0xC600) is { } position)
            {
                files.Add(Path.GetFileName(position.Chain[^1].Path));
            }
        }

        files.Should().NotBeEmpty().And.NotContain(["ProFile.rom.asm", "Mouse.rom.asm"]);
    }

    /// <summary>
    ///  A slot's module documents its routines at that slot's addresses, so their contracts are checked there.
    /// </summary>
    [TestMethod]
    public void DocumentationMovesWithTheSlot()
    {
        DebugInfo debug = new();
        SdkModules.AddTo(debug, Apple2Model.IIeEnhanced, s_inputs);
        SourceMapModule slot2 = debug.Modules.OfType<SourceMapModule>().First(MouseInSlotTwo);
        slot2.Documentation.Symbols["SetMouse"].Should().Be(0xC200 | (MouseRom.SetMouse & 0xFF));
        slot2.Documentation.Symbols["CommandPort"].Should().Be(0xC080, "constants stay");
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
        string[] lines = File.ReadAllLines(source);
        int line = Array.FindIndex(lines, Array.IndexOf(lines, ".proc Driver") + 1, IsCode) + 1;
        List<ushort> entries = [.. debug.Modules.SelectMany(module => module.Entries(source, line))];
        entries.Order().Should().Equal(Enumerable.Range(1, 7).Select(slot => (ushort)((0xC0 | slot) << 8 | (ProFileRom.Driver & 0xFF))));
    }

    private static bool MouseInSlotTwo(SourceMapModule module) =>
        module.Area is Apple2MemoryArea.Slot2Rom && module.TryResolve("SetMouse", out long _);

    // The outermost line, the invocation where a routine is a macro call, is the routine's first code after its
    // defining line (a label or a .proc line), past any comments.
    private static void AtLabel(DebugInfo debug, Apple2TestMemory memory, ushort address, string file, string label)
    {
        SourceLine line = debug.Position(memory, address)?.Chain[^1] ?? throw new AssertFailedException("No source.");
        Path.GetFileName(line.Path).Should().Be(file);
        string[] lines = File.ReadAllLines(line.Path);
        IsCode(lines[line.Line - 1]).Should().BeTrue();
        int before = Array.FindLastIndex(lines, line.Line - 2, IsCode);
        lines[before].Should().Be(label);
    }

    // Whether a line holds code or a label, not only a comment or nothing.
    private static bool IsCode(string line) => line.Trim() is { Length: > 0 } code && !code.StartsWith(';');
}
