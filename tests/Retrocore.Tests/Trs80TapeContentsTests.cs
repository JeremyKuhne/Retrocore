// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using Retrocore.Basic;
using Retrocore.Debug;
using Retrocore.Machines.Devices;
using Retrocore.Machines.Trs80;
using Retrocore.Media.Trs80;

namespace Retrocore.Tests;

/// <summary>
///  A CAS tape says which Level's BASIC recorded it, and the cassette warns when its machine's ROM cannot read it;
///  Level I sizes the memory it is given.
/// </summary>
[TestClass]
public class Trs80TapeContentsTests
{
    private static readonly byte[] s_leader = new byte[128];

    /// <summary>
    ///  Level II's CSAVE header is three $D3 bytes after the sync byte.
    /// </summary>
    [TestMethod]
    public void ReadsALevelTwoBasicTape()
    {
        CassetteFormat.Detect(BasicTape.Write(Level2Program(), 'A')).Should().Be(CassetteContents.Level2Basic);
    }

    /// <summary>
    ///  A SYSTEM tape's $55 begins its name after the sync byte.
    /// </summary>
    [TestMethod]
    public void ReadsALevelTwoSystemTape()
    {
        byte[] tape = [.. s_leader, 0xA5, 0x55, .. "GAME  "u8, 0x3C, 0x01, 0x00, 0x70, 0xC9, 0xB9, 0x78, 0x00, 0x70];
        CassetteFormat.Detect(tape).Should().Be(CassetteContents.Level2System);
    }

    /// <summary>
    ///  Level I's block addresses follow its sync byte, high bytes first, with the bytes between after them.
    /// </summary>
    [TestMethod]
    public void ReadsALevelOneTape()
    {
        byte[] tape = [.. s_leader, 0xA5, 0x42, 0x00, 0x42, 0x04, 0x01, 0x02, 0x03, 0x04, 0xF6];
        CassetteFormat.Detect(tape).Should().Be(CassetteContents.Level1);
    }

    /// <summary>
    ///  A blank tape, a 1500 baud recording, one without a leader, and addresses with too few bytes after them are
    ///  none of the formats.
    /// </summary>
    [TestMethod]
    public void LeavesOtherTapesUnknown()
    {
        CassetteFormat.Detect([]).Should().Be(CassetteContents.Unknown);
        CassetteFormat.Detect(s_leader).Should().Be(CassetteContents.Unknown);
        CassetteFormat.Detect([.. Enumerable.Repeat((byte)0x55, 256), 0x7F, 0x55]).Should().Be(CassetteContents.Unknown);
        CassetteFormat.Detect([0xA5, 0xD3, 0xD3, 0xD3, 0x41]).Should().Be(CassetteContents.Unknown);
        CassetteFormat.Detect([.. s_leader, 0xA5, 0x42, 0x00, 0x43, 0x00, 0x01]).Should().Be(CassetteContents.Unknown);
        CassetteFormat.Detect([.. s_leader, 0xA5, 0x10, 0x00, 0x10, 0x02, 0x01, 0x02]).Should().Be(CassetteContents.Unknown);
    }

    /// <summary>
    ///  Level I's CSAVE, run on the SDK's Level I ROM, records a tape read as Level I's; a Model I with Level II
    ///  warns of it, naming the ROM to switch to, and a Level I one plays it without a warning.
    /// </summary>
    [TestMethod]
    public void LevelOneRecordingWarnsOnLevelTwo()
    {
        Trs80Machine machine = LevelOne(4);
        Type(machine, "10 PRINT 42\r");
        CassetteImage tape = new();
        machine.Bus.Cassette.Record(tape);
        Type(machine, "CSAVE\r");
        RunUntil(machine, () => machine.Bus.Cassette.MotorOn, seconds: 5);
        RunUntil(machine, () => !machine.Bus.Cassette.MotorOn, seconds: 60);
        machine.Bus.Cassette.Stop();
        CassetteFormat.Detect(tape.Bytes).Should().Be(CassetteContents.Level1);

        Trs80CassetteDrive level1 = LevelOneDrive();
        level1.Play(tape, "program.cas");
        level1.Contents.Should().Be(CassetteContents.Level1);
        Loaded(level1).Contents.Should().Be("Level I tape (250 baud)");
        Loaded(level1).Warning.Should().BeNull();

        Trs80CassetteDrive level2 = Trs80MachineTests.Create(new() { DiskController = false }).Cassette;
        level2.Play(tape, "program.cas");
        Loaded(level2).Warning.Should().Be(
            "This tape was recorded by Level I BASIC (250 baud); Level II can't read it. Switch the ROM to Level I.");
    }

    /// <summary>
    ///  Level II tapes in a Level I machine warn, a recording and an unknown tape do not, and the Model 4, which has
    ///  no Level I, says where a Level I tape plays.
    /// </summary>
    [TestMethod]
    public void WarnsOfLevelTwoTapesOnLevelOne()
    {
        Trs80CassetteDrive drive = LevelOneDrive();
        drive.Play(new CassetteImage(BasicTape.Write(Level2Program(), 'A')), "basic.cas");
        Loaded(drive).Contents.Should().Be("Level II BASIC program (500 baud)");
        Loaded(drive).Warning.Should().Be(
            "This tape was recorded by Level II BASIC (500 baud); Level I can't read it. Switch the ROM to Level II.");

        drive.Play(new CassetteImage([.. s_leader, 0xA5, 0x55, .. "GAME  "u8]), "game.cas");
        Loaded(drive).Warning.Should().Be(
            "This is a Level II SYSTEM tape (500 baud); Level I can't read it. Switch the ROM to Level II.");

        drive.Play(new CassetteImage([1, 2, 3]), "other.cas");
        Loaded(drive).Contents.Should().BeNull();
        Loaded(drive).Warning.Should().BeNull();

        drive.Record(new CassetteImage(), "new.cas");
        Loaded(drive).Warning.Should().BeNull();
        drive.Eject();
        drive.Media.Should().BeNull();
    }

    /// <summary>
    ///  The Model III's cassette, at 250 baud with Level I, warns of the other Level's tapes as the Model I's does;
    ///  the Model 4's names the machines that play Level I tapes.
    /// </summary>
    [TestMethod]
    public void TheModelThreeFamilyWarnsToo()
    {
        byte[] level1Tape = [.. s_leader, 0xA5, 0x42, 0x00, 0x42, 0x01, 0x0D, 0xF3];
        Trs80CassetteDrive model3 = Model3(Trs80Model3Variant.Model3, Trs80Rom.Level2);
        model3.Play(new CassetteImage(level1Tape), "a.cas");
        Loaded(model3).Warning.Should().Be(
            "This tape was recorded by Level I BASIC (250 baud); the Model III ROM can't read it. Switch the ROM to Level I.");

        Trs80CassetteDrive level1 = Model3(Trs80Model3Variant.Model3, Trs80Rom.Level1);
        level1.Info.Description.Should().Be("Cassette recorder, 250 baud");
        level1.Play(new CassetteImage(level1Tape), "a.cas");
        Loaded(level1).Warning.Should().BeNull();

        Trs80CassetteDrive model4 = Model3(Trs80Model3Variant.Model4, Trs80Rom.Level2);
        model4.Play(new CassetteImage(level1Tape), "a.cas");
        Loaded(model4).Warning.Should().Be("This tape was recorded by Level I BASIC (250 baud); the Model 4's ROM can't read it. "
            + "Play it on a Model I or Model III with the ROM set to Level I.");
    }

    /// <summary>
    ///  Level I probes for the top of its RAM, so PRINT MEM gives what 4K and 16K leave above the program's start
    ///  at $4200: 3583 and 15871 bytes.
    /// </summary>
    /// <param name="kilobytes">The machine's RAM.</param>
    /// <param name="free">What PRINT MEM prints.</param>
    [TestMethod]
    [DataRow(4, 3583)]
    [DataRow(16, 15871)]
    public void LevelOneSizesItsMemory(int kilobytes, int free)
    {
        Trs80Machine machine = LevelOne(kilobytes);
        Type(machine, "PRINT MEM\r");
        Run(machine, seconds: 0.5);
        Screen(machine).Should().Contain($" {free}");
    }

    // A Level I Model I's cassette, whose ROM is never run.
    private static Trs80CassetteDrive LevelOneDrive()
    {
        Trs80Configuration configuration = new()
        {
            Rom = Trs80Rom.Level1,
            RamKilobytes = 4,
            ExpansionInterface = false
        };

        return Trs80MachineTests.Create(configuration, new byte[0x1000]).Cassette;
    }

    private static MediaState Loaded(Trs80CassetteDrive drive) =>
        drive.Media ?? throw new AssertFailedException("The cassette is empty.");

    private static BasicProgram Level2Program() =>
        BasicProgram.Parse("10 PRINT \"HI\"\n", BasicDialect.Level2).Program ?? throw new AssertFailedException("The program did not parse.");

    // A Model I running the SDK's Level I ROM, booted to READY.
    private static Trs80Machine LevelOne(int kilobytes)
    {
        string roms = Path.Join(AppContext.BaseDirectory, "Inputs", "Trs80");
        byte[] system = Trs80SdkModules.AssembleLevel1(Path.Join(roms, "Level1.asm")).Sections[0].Bytes.ToArray();
        byte[] characters = Trs80SdkModules.AssembleCharacterGenerator(Path.Join(roms, "CharacterGenerator.asm"))
            .Sections[0].Bytes.ToArray();

        Trs80Machine machine = new(
            new Trs80Configuration { Rom = Trs80Rom.Level1, RamKilobytes = kilobytes, ExpansionInterface = false },
            new Trs80Roms(system, characters));

        Run(machine, seconds: 2);
        Screen(machine).Should().Contain("READY");
        return machine;
    }

    private static Trs80CassetteDrive Model3(Trs80Model3Variant variant, Trs80Rom rom)
    {
        bool level1 = rom == Trs80Rom.Level1;
        int size = level1 || variant == Trs80Model3Variant.Model4P ? Trs80Model3Roms.BootSize : Trs80Model3Roms.SystemSize;
        Trs80Model3Machine machine = new(
            new Trs80Model3Configuration
            {
                Variant = variant,
                Rom = rom,
                RamKilobytes = Trs80Model3Configuration.DefaultRam(variant),
                DiskController = false
            },
            new Trs80Model3Roms(new byte[size], new byte[Trs80Model3Roms.CharacterGeneratorSize]));

        return machine.Cassette ?? throw new AssertFailedException("The machine has no cassette.");
    }

    private static void Run(Trs80Machine machine, double seconds) => machine.Run((ulong)(seconds * Trs80Timing.ClockHertz));

    private static void RunUntil(Trs80Machine machine, Func<bool> condition, double seconds)
    {
        for (int step = 0; step < seconds * 100 && !condition(); step++) { machine.Run(Trs80Timing.ClockHertz / 100); }
        condition().Should().BeTrue($"within {seconds} seconds");
    }

    // Types each character, running until the keyboard has pressed and released it.
    private static void Type(Trs80Machine machine, string text)
    {
        foreach (char character in text) { machine.Bus.Keyboard.Type((byte)character); }
        while (machine.Bus.Keyboard.IsTyping) { machine.Run(1000); }
    }

    private static string Screen(Trs80Machine machine)
    {
        char[] screen = new char[Trs80Video.Columns * Trs80Video.Rows];
        for (int index = 0; index < screen.Length; index++)
        {
            byte code = machine.Bus.Video.Read(index);
            screen[index] = code is >= 0x20 and < 0x80 ? (char)code : ' ';
        }

        return new(screen);
    }
}
