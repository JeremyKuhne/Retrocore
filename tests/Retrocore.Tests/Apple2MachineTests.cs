// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using Retrocore.Debug;
using Retrocore.Machines.Apple2;
using Retrocore.Media;

namespace Retrocore.Tests;

/// <summary>
///  Tests IIe banking priorities and read-sensitive device behavior independently of copyrighted ROMs.
/// </summary>
[TestClass]
public class Apple2MachineTests
{
    /// <summary>
    ///  Checks every combination of the six RAM-mapping controls at representative boundaries.
    /// </summary>
    [TestMethod]
    public void RamBankingCombinationsRespectDisplayAndZeroPageOverrides()
    {
        ushort[] addresses = [0x100,0x200,0x400,0x7FF,0x800,0x2000,0x3FFF,0x4000,0xBFFF];
        for (int mask = 0; mask < 64; mask++)
        {
            Apple2Bus bus = Bus();
            bus.Write((ushort)(0xC000 + (mask & 1)), value: 0);
            bus.Write((ushort)(0xC002 + ((mask >> 1) & 1)), value: 0);
            bus.Write((ushort)(0xC004 + ((mask >> 2) & 1)), value: 0);
            bus.Write((ushort)(0xC054 + ((mask >> 3) & 1)), value: 0);
            bus.Write((ushort)(0xC056 + ((mask >> 4) & 1)), value: 0);
            bus.Write((ushort)(0xC008 + ((mask >> 5) & 1)), value: 0);
            foreach (ushort address in addresses)
            {
                bus.SetRam(auxiliary: false, address, value: 0x11);
                bus.SetRam(auxiliary: true, address, value: 0x22);
                bool displayOverride = (mask & 1) != 0
                    && (address is >= 0x400 and < 0x800 || ((mask & 16) != 0 && address is >= 0x2000 and < 0x4000));

                bool readAux = address < 0x200 ? (mask & 32) != 0 : (mask & 2) != 0;
                bool writeAux = address < 0x200 ? (mask & 32) != 0 : (mask & 4) != 0;
                if (displayOverride) { readAux = writeAux = (mask & 8) != 0; }
                bus.Read(address).Should().Be(readAux ? (byte)0x22 : (byte)0x11);
                bus.Write(address, value: 0x33);
                bus.MainMemory[address].Should().Be(writeAux ? (byte)0x11 : (byte)0x33);
                bus.AuxiliaryMemory[address].Should().Be(writeAux ? (byte)0x33 : (byte)0x22);
            }
        }
    }

    /// <summary>
    ///  Checks all language-card aliases and the odd-read prewrite latch.
    /// </summary>
    [TestMethod]
    public void LanguageCardDoubleReadsEnableWritesAndWritesResetPrewrite()
    {
        for (int alias = 0; alias < 16; alias++)
        {
            Apple2Bus bus = Bus();
            ushort address = (ushort)(0xC080 + alias);
            bus.Read(address);
            bus.LanguageCardBank2.Should().Be((alias & 8) == 0);
            bus.LanguageCardRead.Should().Be((alias & 3) is 0 or 3);
            bus.LanguageCardWrite.Should().BeFalse();
            bus.Read(address);
            bus.LanguageCardWrite.Should().Be((alias & 1) != 0);
            bus.Write(0xC082, value: 0);
            bus.LanguageCardWrite.Should().BeFalse();
            bus.Read(0xC083);
            bus.Write(0xC083, value: 0);
            bus.Read(0xC083);
            bus.LanguageCardWrite.Should().BeFalse();
        }
    }

    /// <summary>
    ///  Verifies independent D000 banks and ALTZP high-memory selection.
    /// </summary>
    [TestMethod]
    public void LanguageCardBanksAndAuxiliaryHighMemoryAreIndependent()
    {
        Apple2Bus bus = Bus();
        bus.Read(0xC083);
        bus.Read(0xC083);
        bus.Write(0xD000, value: 0x11);
        bus.Write(0xE000, value: 0x33);
        bus.Read(0xC08B);
        bus.Read(0xC08B);
        bus.Write(0xD000, value: 0x22);
        bus.Read(0xD000).Should().Be(0x22);
        bus.Read(0xE000).Should().Be(0x33);
        bus.Read(0xC083);
        bus.Read(0xD000).Should().Be(0x11);
        bus.Write(0xC009, value: 0);
        bus.Read(0xD000).Should().Be(0);
        bus.Write(0xD000, value: 0x44);
        bus.Write(0xC008, value: 0);
        bus.Read(0xD000).Should().Be(0x11);
    }

    /// <summary>
    ///  Verifies debugger peeks do not clear keyboard strobe or latch C800 firmware.
    /// </summary>
    [TestMethod]
    public void PeeksDoNotChangeKeyboardOrFirmwareLatches()
    {
        Apple2Bus bus = Bus();
        bus.QueueKey(character: 0x41);
        bus.QueueKey(character: 0x42);
        bus.Read(0xC000).Should().Be(0xC1);
        bus.Peek(0xC010);
        bus.Read(0xC000).Should().Be(0xC1);
        bus.Read(0xC010);
        bus.Read(0xC000).Should().Be(0xC2);
        bus.Peek(0xC300);
        bus.Read(0xC800).Should().Be(0xFF);
        bus.Read(0xC300);
        bus.Read(0xC800).Should().Be(0xAA);
        bus.Write(0xCFFF, value: 0);
        bus.Read(0xC800).Should().Be(0xFF);
    }

    /// <summary>
    ///  Verifies status ports retain keyboard data in their low bits and writes acknowledge strobe.
    /// </summary>
    [TestMethod]
    public void StatusPortsExposeKeyboardDataWithoutReadSideEffects()
    {
        Apple2Bus bus = Bus();
        bus.QueueKey(character: 0x41);
        bus.Read(0xC01A).Should().Be(0xC1);
        bus.Read(0xC010).Should().Be(0x41);
        bus.QueueKey(character: 0x42);
        bus.Read(0xC011);
        bus.Read(0xC000).Should().Be(0xC2);
        bus.Write(0xC011, value: 0);
        bus.Read(0xC000).Should().Be(0x42);
    }

    /// <summary>
    ///  Verifies physical RAM export includes both D000 banks without changing language-card selection.
    /// </summary>
    [TestMethod]
    public void PhysicalRamExportPreservesBothLanguageCardBanks()
    {
        Apple2Bus bus = Bus();
        bus.Read(0xC083);
        bus.Read(0xC083);
        bus.Write(0xD000, value: 0x22);
        bus.Read(0xC08B);
        bus.Read(0xC08B);
        bus.Write(0xD000, value: 0x11);
        byte[] ram = new byte[65536];
        bus.CopyPhysicalRam(auxiliary: false, ram);
        ram[0xC000].Should().Be(0x11);
        ram[0xD000].Should().Be(0x22);
        bus.LanguageCardBank2.Should().BeFalse();
        bus.LanguageCardWrite.Should().BeTrue();
    }

    /// <summary>
    ///  Verifies character-ROM bit order, inverse text, and eighty-column bitmap dimensions.
    /// </summary>
    [TestMethod]
    public void TextBitmapUsesSuppliedCharacterRomAndInverseGlyphs()
    {
        byte[] characters = new byte[4096];
        Array.Fill(characters, (byte)0xFF);
        characters[0xC1 * 8] = 0xF7;
        characters[1 * 8] = 0x08;
        Apple2Bus bus = new(new Apple2Roms(new byte[16384], characters));
        bus.SetRam(auxiliary: false, address: 0x400, value: 0xC1);
        byte[] pixels = bus.RenderTextBitmap();
        pixels.Length.Should().Be(280 * 192);
        pixels[0].Should().Be(0);
        pixels[3].Should().Be(1);
        bus.SetRam(auxiliary: false, address: 0x400, value: 1);
        pixels = bus.RenderTextBitmap();
        pixels[0].Should().Be(1);
        pixels[3].Should().Be(0);
        bus.Write(0xC00D, value: 0);
        bus.RenderTextBitmap().Length.Should().Be(560 * 192);
    }

    /// <summary>
    ///  Verifies interleaved eighty-column text and page-selection behavior.
    /// </summary>
    [TestMethod]
    public void TextUsesAuxiliaryEvenAndMainOddColumns()
    {
        Apple2Bus bus = Bus();
        bus.SetRam(auxiliary: true, address: 0x400, value: 0xC1);
        bus.SetRam(auxiliary: false, address: 0x400, value: 0xC2);
        bus.TextByte(row: 0, column: 0).Should().Be(0xC2);
        bus.Write(0xC00D, value: 0);
        bus.TextByte(row: 0, column: 0).Should().Be(0xC1);
        bus.TextByte(row: 0, column: 1).Should().Be(0xC2);
        bus.Write(0xC055, value: 0);
        bus.TextByte(row: 0, column: 0).Should().Be(0);
        bus.Write(0xC001, value: 0);
        bus.TextByte(row: 0, column: 0).Should().Be(0xC1);
    }

    /// <summary>
    ///  The debugger's current text surface honors display mapping, not CPU read and write bank selection.
    /// </summary>
    [TestMethod]
    public void TextSurfaceDistinguishesMixedModeAndDisplayBanks()
    {
        Apple2Roms roms = Roms();
        byte[] characters = roms.Characters.ToArray();
        characters[0x40 * 8] ^= 0x01;
        Apple2Machine machine = new(Apple2Model.IIeEnhanced, new Apple2Roms(roms.System, characters));
        using Apple2DebugTarget target = new(machine, Apple2Model.IIeEnhanced);
        Apple2Bus bus = machine.Bus;
        // Row 20 starts at $0650; each video page has distinct aux/main contents.
        bus.SetRam(auxiliary: true, address: 0x0650, value: 0xC1);
        bus.SetRam(auxiliary: false, address: 0x0650, value: 0xC2);
        bus.SetRam(auxiliary: true, address: 0x0A50, value: 0xC3);
        bus.SetRam(auxiliary: false, address: 0x0A50, value: 0xC4);
        bus.SetRam(auxiliary: true, address: 0x0651, value: 0x40);
        bus.Write(0xC00D, value: 0);
        bus.Write(0xC050, value: 0);
        bus.Write(0xC053, value: 0);
        bus.Write(0xC003, value: 0);
        bus.Write(0xC004, value: 0);
        DebugTextSurface mixed = TextSurface(target);
        mixed.Mode.Should().Be("mixed");
        mixed.Columns.Should().Be(80);
        mixed.FirstRow.Should().Be(20);
        mixed.Rows.Should().HaveCount(4);
        mixed.Rows[0].Should().StartWith("AB");
        bus.Write(0xC00F, value: 0);
        TextSurface(target).Rows[0].Should().StartWith("AB\uFFFD");
        bus.Write(0xC055, value: 0);
        TextSurface(target).Rows[0].Should().StartWith("CD");
        bus.Write(0xC001, value: 0);
        TextSurface(target).Rows[0].Should().StartWith("AB");
        bus.Write(0xC052, value: 0);
        TextSurface(target).Rows.Should().BeEmpty();
        TextSurface(target, "textMemory").Rows[20].Should().StartWith("AB");
    }

    /// <summary>
    ///  Both IIe ROMs accept real keyboard reads before and after the ROM itself switches to the slot-3 console.
    /// </summary>
    /// <param name="model">The launch's model name.</param>
    /// <param name="profile">The matching firmware profile prefix.</param>
    [TestMethod]
    [DataRow("iie", "apple2eOriginal")]
    [DataRow("iie-enhanced", "apple2eEnhanced")]
    public void GuestDemandFollowsTheActualIIeInputHook(string model, string profile)
    {
        using Apple2DebugTarget target = Apple2DebugTarget.Launch(new System.Text.Json.Nodes.JsonObject
        {
            ["model"] = model, ["sound"] = "off", ["controllers"] = false
        });

        target.AddSdkModules(new(), directory: null);
        foreach (char key in "PR#3\r")
        {
            GuestInputPath path = WaitForDemand(target);
            path.Profile.Should().Be(profile + "40");
            Deliver(target, path, key);
        }

        GuestInputPath eighty = WaitForDemand(target);
        eighty.Profile.Should().Be(profile + "80");
        TextSurface(target).Columns.Should().Be(80);
        Deliver(target, eighty, 'X');
        WaitForDemand(target).Profile.Should().Be(profile + "80");
        target.Poke(0x0038, 0x00);
        target.WaitingForInput().Should().BeNull("a different input hook cannot prove the normal 80-column route");
    }

    /// <summary>
    ///  Runs the SDK-built Pascal 1.1 console on the language card and observes both strobe clear and ring admission.
    /// </summary>
    [TestMethod]
    public void PascalConsoleAdmitsThroughItsRingRatherThanAtTheStrobe()
    {
        Apple2Machine machine = new(Apple2Model.IIPlus, Roms());
        using Apple2DebugTarget target = new(machine, Apple2Model.IIPlus);
        Apple2Bus bus = machine.Bus;
        Retrocore.Assembler.AssemblyResult assembly = PascalInterpreterSourceTests.Assemble();
        ReadOnlySpan<byte> image = SourceBuild.OutputBytes(assembly).Span;
        machine.Run(7);
        bus.InstallLanguageCard();
        bus.Read(0xC083);
        bus.Read(0xC083);
        for (int offset = 0; offset < 0x3000; offset++) { bus.Write((ushort)(0xD000 + offset), image[offset]); }

        ushort read = (ushort)assembly.Symbols["ConsoleRead"];
        ushort slot = (ushort)(assembly.Symbols["SlotTypes"] + assembly.Symbols["CONSOLE_SLOT"] - 1);
        // The guest calls the real routine. Slot 3 initially redirects it to a serial card.
        target.Load(0x300, [0x20, (byte)read, (byte)(read >> 8), 0x85, 0x90, 0x4C, 0x05, 0x03]);
        target.ProgramCounter = 0x300;
        bus.Write(slot, value: 3);
        ushort wait = (ushort)assembly.Symbols["ConsoleRead::FromTypeAhead"];
        StepTo(target, wait);
        target.WaitingForInput().Should().BeNull("a serial console is not keyboard demand");
        bus.Write(slot, value: 0);
        GuestInputPath path = target.WaitingForInput() ?? throw new AssertFailedException("No verified Pascal console demand.");
        path.Profile.Should().Be("applePascal11Console");
        Deliver(target, path, 'A', requireIntermediateAck: true);
        StepTo(target, 0x0305);
        char.IsAsciiLetter((char)bus.Peek(0x90)).Should().BeTrue("the firmware actually returned a letter to its caller");
    }

    private static GuestInputPath WaitForDemand(Apple2DebugTarget target)
    {
        ulong deadline = target.CycleCount + 4_000_000;
        while (target.CycleCount < deadline)
        {
            if (target.IsInstructionBoundary && target.WaitingForInput() is { } path) { return path; }
            target.StepCycle();
        }

        throw new AssertFailedException(
            $"No guest demand at ${target.ProgramCounter:X4}, keyboard hook ${InputFirmware.Word(target, 0x0038):X4}.");
    }

    private static void Deliver(Apple2DebugTarget target, GuestInputPath path, char key, bool requireIntermediateAck = false)
    {
        path.Send(key).Should().Be(InputReceipt.Pending);
        Func<int, InputReceipt> observe = path.Observe ?? throw new AssertFailedException("No keyboard receipt observer.");
        bool ack = false;
        ulong deadline = target.CycleCount + 100_000;
        while (target.CycleCount < deadline)
        {
            target.StepCycle();
            if (!target.IsInstructionBoundary) { continue; }
            switch (observe(key))
            {
                case InputReceipt.Acknowledged:
                    ack = true;
                    break;
                case InputReceipt.Accepted:
                    if (requireIntermediateAck) { ack.Should().BeTrue("the card acknowledges before the ring store"); }
                    return;
                case InputReceipt.Unconfirmed:
                    throw new AssertFailedException($"The key was not admitted at ${target.ProgramCounter:X4}.");
            }
        }

        throw new AssertFailedException("The guest did not admit its pending key.");
    }

    private static DebugTextSurface TextSurface(Apple2DebugTarget target, string surface = "visibleText") =>
        target.ReadTextSurface(surface) ?? throw new AssertFailedException($"No {surface} surface.");

    private static void StepTo(Apple2DebugTarget target, ushort address)
    {
        ulong deadline = target.CycleCount + 100_000;
        while (target.CycleCount < deadline)
        {
            if (target.IsInstructionBoundary && target.ProgramCounter == address) { return; }
            target.StepCycle();
        }

        throw new AssertFailedException($"Expected ${address:X4}, running at ${target.ProgramCounter:X4}.");
    }

    /// <summary>
    ///  Verifies block reads fill memory and a read-only disk returns the ProDOS write-protection status.
    /// </summary>
    [TestMethod]
    public void SlotSevenReadsBlocksAndReportsWriteProtection()
    {
        byte[] image = new byte[1024];
        Array.Fill(image, (byte)0x5A, startIndex: 512, count: 512);
        Apple2Bus bus = new(Roms(), new MemoryBlockDevice(image));
        bus.SetRam(auxiliary: false, address: 0x42, value: 1);
        bus.SetRam(auxiliary: false, address: 0x45, value: 8);
        bus.SetRam(auxiliary: false, address: 0x46, value: 1);
        bus.Read(0xC0F0).Should().Be(0);
        bus.MainMemory.Slice(start: 0x800, length: 512).ToArray().Should().OnlyContain(value => value == 0x5A);
        bus.SetRam(auxiliary: false, address: 0x42, value: 2);
        bus.Read(0xC0F0).Should().Be(0x2B);
        bus.Peek(0xC701).Should().Be(0x20);
        bus.Peek(0xC703).Should().Be(0);
        bus.Peek(0xC705).Should().Be(3);
        bus.Peek(0xC707).Should().Be(0x3C);
    }

    /// <summary>
    ///  Verifies both model selections and cycle-synchronized reset-vector acquisition.
    /// </summary>
    /// <param name="model">The machine model.</param>
    [TestMethod]
    [DataRow(Apple2Model.IIe)]
    [DataRow(Apple2Model.IIeEnhanced)]
    public void MachineClocksDevicesWithCpu(Apple2Model model)
    {
        Apple2Machine machine = new(model, Roms());
        machine.Run(cycles: 7);
        machine.Processor.Registers.ProgramCounter.Should().Be(0xAAAA);
        machine.Bus.CycleCount.Should().Be(machine.Processor.CycleCount);
        machine.Processor.Variant.Should().Be(model == Apple2Model.IIe ? ProcessorVariant.Mos6502 : ProcessorVariant.Rockwell65C02);
    }

    private static Apple2Bus Bus() => new(Roms());
    private static Apple2Roms Roms()
    {
        byte[] system = new byte[16384];
        Array.Fill(system, (byte)0xAA);
        return new(system, new byte[4096]);
    }
}
