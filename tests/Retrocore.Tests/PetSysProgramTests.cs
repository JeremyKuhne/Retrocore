// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using Retrocore.Debug;
using Retrocore.Machines.Commodore;
using Retrocore.Media.Commodore;

namespace Retrocore.Tests;

/// <summary>
///  <see cref="PetSysProgram"/>'s program files, on PETs whose ROMs are built from the SDK's sources: the BASIC line
///  each BASIC stores for <c>SYS</c>, the file launched as a debug session loads it, and the file on a tape loaded
///  with <c>LOAD</c> and started with <c>RUN</c>.
/// </summary>
[TestClass]
public class PetSysProgramTests
{
    private const string Message = "SYS OK";

    private static string PetSources => Path.Join(BasicNames.Inputs, "Pet");

    /// <summary>
    ///  The code after the stub is at 1037, and the file is the line, the end of the program and the code.
    /// </summary>
    [TestMethod]
    public void CodeFollowsTheLine()
    {
        PetSysProgram.CodeAddress().Should().Be(0x040D);
        PetSysProgram.Build([0x60]).Should().Equal(
            0x01, 0x04,
            0x0B, 0x04, 0x0A, 0x00, 0x9E, (byte)'1', (byte)'0', (byte)'3', (byte)'7', 0x00,
            0x00, 0x00,
            0x60);
    }

    /// <summary>
    ///  Code at an address of its own is reached through zeros, and the line's digits are that address's.
    /// </summary>
    [TestMethod]
    public void CodeAtAnAddressIsPadded()
    {
        byte[] prg = PetSysProgram.Build([0xEA, 0x60], 0x1000, lineNumber: 63999);
        prg.Length.Should().Be(2 + 0x1002 - 0x0401);
        prg[4..12].Should().Equal(0xFF, 0xF9, 0x9E, (byte)'4', (byte)'0', (byte)'9', (byte)'6', 0x00);
        prg.AsSpan(14, 0x1000 - 0x040D).IndexOfAnyExcept((byte)0).Should().Be(-1);
        prg[^2..].Should().Equal(0xEA, 0x60);
        PetSysProgram.Stub(0x1000, 63999).Should().Equal(prg[..14]);
    }

    /// <summary>
    ///  Code that would overlap the line, or pass <c>$FFFF</c>, is refused, as are line numbers BASIC refuses.
    /// </summary>
    [TestMethod]
    public void OutOfRangeIsRefused()
    {
        FluentActions.Invoking(() => PetSysProgram.Build([0x60], 0x040C)).Should().ThrowExactly<ArgumentException>();
        FluentActions.Invoking(() => PetSysProgram.Build([0x60, 0x60], 0xFFFF)).Should().ThrowExactly<ArgumentException>();
        FluentActions.Invoking(() => PetSysProgram.Build([])).Should().ThrowExactly<ArgumentException>();
        FluentActions.Invoking(() => PetSysProgram.Build([0x60], lineNumber: 64000)).Should().Throw<ArgumentOutOfRangeException>();
        FluentActions.Invoking(() => PetSysProgram.Stub(0x10000)).Should().Throw<ArgumentOutOfRangeException>();
        PetSysProgram.Build([0x60], 0xFFFF).Length.Should().Be(2 + 0x10000 - 0x0401);
    }

    /// <summary>
    ///  Each BASIC stores the line typed in as the stub has it.
    /// </summary>
    /// <param name="model">The model.</param>
    /// <param name="line">The line typed.</param>
    /// <param name="address">The address it calls.</param>
    /// <param name="lineNumber">Its number.</param>
    [TestMethod]
    [DataRow(PetModel.Pet2001, "10 SYS1037", 1037, 10)]
    [DataRow(PetModel.Pet2001Basic2, "10 SYS1037", 1037, 10)]
    [DataRow(PetModel.Pet4032, "10 SYS1037", 1037, 10)]
    [DataRow(PetModel.Pet4032, "63999 SYS65535", 65535, 63999)]
    [DataRow(PetModel.Pet2001Basic2, "0 SYS8", 8, 0)]
    public void EachBasicStoresTheLine(PetModel model, string line, int address, int lineNumber)
    {
        PetMachine machine = new(PetSdkModules.BuildRoms(model, PetSources), model);
        PetMachineTests.RunToReady(machine);
        PetMachineTests.Type(machine, line + "\r");

        byte[] stub = PetSysProgram.Stub(address, lineNumber);
        machine.Bus.Ram.Slice(0x0401, stub.Length - 2).ToArray().Should().Equal(stub[2..], Screen(machine));
    }

    /// <summary>
    ///  The file, launched as a debug session launches a <c>.prg</c>, runs its code.
    /// </summary>
    /// <param name="model">The model, by its launch name.</param>
    /// <param name="address">The code's address, or 0 for right after the line.</param>
    [TestMethod]
    [DataRow("pet2001-basic2", 0)]
    [DataRow("pet2001-basic2", 0x1000)]
    [DataRow("pet4032", 0)]
    [DataRow("pet4032", 0x1000)]
    [DataRow("pet2001", 0)]
    public void LaunchedFileRuns(string model, int address)
    {
        // Built here rather than by Launch, which takes RETROCORE_PET_ROMS's dumps when it is set.
        PetModel pet = model switch
        {
            "pet4032" => PetModel.Pet4032,
            "pet2001" => PetModel.Pet2001,
            _ => PetModel.Pet2001Basic2
        };

        PetMachine machine = new(PetSdkModules.BuildRoms(pet, PetSources), pet, pet == PetModel.Pet4032 ? 32 : 8);
        PetDebugTarget target = new(machine);
        target.SetBasicSymbols(PetSdkModules.AssembleBasic(PetSources, pet).SymbolsWithHistoricalNames);
        machine.Run(7);
        target.Boot(3);
        target.LoadPrg(Program(address), run: true, entry: null);
        PetTapeTests.WaitForReady(target.Machine);

        target.Machine.ReadTextScreen().Should().Contain(line => line.TrimEnd() == Message, Screen(target.Machine));
    }

    /// <summary>
    ///  The file on a TAP tape loads with <c>LOAD</c> and runs its code with <c>RUN</c>.
    /// </summary>
    /// <param name="model">The model.</param>
    [TestMethod]
    [DataRow(PetModel.Pet2001Basic2)]
    [DataRow(PetModel.Pet4032)]
    [DataRow(PetModel.Pet2001)]
    public void TapeLoadsAndRuns(PetModel model)
    {
        byte[] image = PetSysProgram.ToTap("sysok", Program(0));
        CommodoreTape tape = TapFormat.Read(image);
        tape.Pulses.Should().Equal(PetSysProgram.ToTape("sysok", Program(0)).Pulses);

        PetMachine machine = new(PetSdkModules.BuildRoms(model, PetSources), model);
        PetMachineTests.RunToReady(machine);
        machine.Bus.Cassette1.Insert(tape, "sysok.tap", "TAP");
        machine.Bus.Cassette1.Play();
        PetMachineTests.Type(machine, "LOAD\r");
        PetTapeTests.WaitForReady(machine);
        machine.ReadTextScreen().Should().Contain(line => line.TrimEnd() == "FOUND SYSOK", Screen(machine));

        PetMachineTests.Type(machine, "RUN\r");
        PetTapeTests.WaitForReady(machine);
        machine.ReadTextScreen().Should().Contain(line => line.TrimEnd() == Message, Screen(machine));
    }

    /// <summary>
    ///  The guarded transfer returns through the ROM and runs the same program while omitting its tape time.
    /// </summary>
    /// <param name="padding">The extra payload following the program.</param>
    [TestMethod]
    [DataRow(0)]
    [DataRow(257)]
    public void ProjectTapeSkipMatchesRomLoad(int padding)
    {
        byte[] prg = Program(0);
        int size = prg.Length;
        Array.Resize(ref prg, size + padding);
        for (int index = size; index < prg.Length; index++) { prg[index] = (byte)(index * 3); }
        var (normal, normalCycles, normalPosition) = Load(skip: false);
        var (fast, fastCycles, fastPosition) = Load(skip: true);
        fastPosition.Should().Be(normalPosition);
        fastCycles.Should().BeLessThan(normalCycles);
        fast.Should().Equal(normal);

        (string[] Screen, ulong Cycles, int Position) Load(bool skip)
        {
            PetMachine machine = new(PetSdkModules.BuildRoms(PetModel.Pet4032, PetSources), PetModel.Pet4032, 32);
            PetDebugTarget target = new(machine);
            target.SetFastIo(enabled: true);
            machine.Run(7);
            CommodoreTape tape = PetSysProgram.ToTape("SYSOK", prg);
            machine.Bus.Cassette1.Insert(tape, "test", "TAP");
            machine.Bus.Cassette1.Play();
            PetTapeSkip? transfer = skip ? PetTapeSkip.Prepare(target, "SYSOK", prg) : null;
            while (!target.ShowsReady)
            {
                machine.Processor.CycleCount.Should().BeLessThan(3_000_000);
                machine.Run(4096);
            }

            foreach (char key in "LOAD\r") { target.Key(key).Should().BeTrue(); }
            bool completed = false;
            while (!machine.Processor.IsInstructionBoundary || machine.Processor.Registers.ProgramCounter != 0xF418)
            {
                if (transfer is not null && machine.Processor.Registers.ProgramCounter == PetTapeSkip.Boundary)
                {
                    completed |= transfer.TryComplete();
                }

                machine.StepCycle();
                if (machine.Processor.CycleCount >= 30_000_000) { Assert.Fail(Screen(machine)); }
            }

            completed.Should().Be(skip, "a fallback is not a Skip pass");
            int position = machine.Bus.Cassette1.Position;
            ulong cycles = machine.Processor.CycleCount;
            if (!skip) { cycles.Should().BeGreaterThanOrEqualTo((ulong)tape.Pulses.Take(position).Sum()); }
            machine.Bus.Cassette1.Motor.Should().BeFalse();
            machine.Bus.Cassette1.Read.Should().BeTrue();
            machine.Bus.Ram[0x96].Should().Be(0);
            machine.Bus.Ram.Slice(0x90, 2).ToArray().Should().Equal(0x55, 0xE4);
            machine.Bus.Ram.Slice(0xC7, 2).ToArray().Should().Equal(machine.Bus.Ram.Slice(0xC9, 2).ToArray());
            machine.Bus.Ram.Slice(0x401, prg.Length - 2).ToArray().Should().Equal(prg.AsSpan(2).ToArray());
            PetTapeTests.WaitForReady(machine);
            PetMachineTests.Type(machine, "RUN\r");
            PetTapeTests.WaitForReady(machine);
            machine.ReadTextScreen().Should().Contain(line => line.TrimEnd() == Message, Screen(machine));
            return (machine.ReadTextScreen(), cycles, position);
        }
    }

    /// <summary>
    ///  A TAP with changed pulse data cannot enter the shortcut even when it is marked saved.
    /// </summary>
    [TestMethod]
    public void DamagedProjectTapeFallsBackBeforeChangingState()
    {
        byte[] prg = Program(0);
        PetMachine machine = new(PetSdkModules.BuildRoms(PetModel.Pet4032, PetSources), PetModel.Pet4032, 32);
        PetDebugTarget target = new(machine);
        int[] pulses = PetSysProgram.ToTape("SYSOK", prg).Pulses.ToArray();
        pulses[^100]++;
        CommodoreTape damaged = new(pulses);
        machine.Bus.Cassette1.Insert(damaged, "test", "TAP");
        machine.Bus.Cassette1.Play();

        PetTapeSkip.Prepare(target, "SYSOK", prg).Should().BeNull();
        machine.Bus.Cassette1.Position.Should().Be(0);
        machine.Processor.CycleCount.Should().Be(0);
    }

    // Code that prints the message through the kernal's CHROUT and returns to BASIC.
    private static byte[] Program(int address)
    {
        List<byte> code = [];
        foreach (char c in Message) { code.AddRange([0xA9, (byte)c, 0x20, 0xD2, 0xFF]); }
        code.Add(0x60);
        return PetSysProgram.Build([.. code], address == 0 ? null : address);
    }

    private static string Screen(PetMachine machine) => string.Join('\n', machine.ReadTextScreen());
}
