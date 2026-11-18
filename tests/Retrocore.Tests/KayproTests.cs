// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using System.Security.Cryptography;
using Retrocore.Assembler;
using Retrocore.Debug;
using Retrocore.Machines.Kaypro;
using Retrocore.Media;
using Retrocore.Media.Floppy;
using Retrocore.Media.Trs80;

namespace Retrocore.Tests;

/// <summary>
///  The Kaypro II from the SDK's ROM sources: they assemble byte-identically to the chips, the ROM asks for a disk,
///  and CP/M runs from its disk.
/// </summary>
/// <remarks>
///  <para>
///   The chip dumps and disks are in <c>RETROCORE_KAYPRO</c> or <c>%USERPROFILE%\Retrocore\kaypro</c>:
///   <c>81-149c.rom</c>, <c>81-146a.bin</c> and <c>cpm22-rom149.img</c> (Kaypro II CP/M 2.2). The tests that need them
///   are inconclusive without them.
///  </para>
/// </remarks>
[TestClass]
public sealed class KayproTests
{
    private const string MonitorHash = "5231E5DD0F6FB64A8EC50951269C248E00875906E391D044918E212D14B08F55";
    private const string CharacterGeneratorHash = "CDE431C9E506EDF11261F7E7D52FD60B1A43FE2D9EA0D3E06F271D4CAB4884FA";

    private static string Inputs => Path.Join(AppContext.BaseDirectory, "Inputs", "Kaypro");

    /// <summary>
    ///  Gets the folder of Kaypro dumps and disks.
    /// </summary>
    internal static string External => Environment.GetEnvironmentVariable("RETROCORE_KAYPRO")
        ?? Path.Join(ExternalTestData.Root, "kaypro");

    /// <summary>
    ///  The monitor ROM's and character generator's sources assemble to the chips' bytes.
    /// </summary>
    [TestMethod]
    public void SourcesMatchTheRoms()
    {
        Hash(KayproSdkModules.AssembleMonitor(Path.Join(Inputs, KayproSdkModules.MonitorSource))).Should().Be(MonitorHash);
        Hash(KayproSdkModules.AssembleCharacterGenerator(Path.Join(Inputs, KayproSdkModules.CharacterGeneratorSource)))
            .Should().Be(CharacterGeneratorHash);
    }

    /// <summary>
    ///  With the dumps present, each source is byte for byte its chip.
    /// </summary>
    /// <param name="source">The source's file name.</param>
    /// <param name="dump">The chip dump's file name.</param>
    [TestMethod]
    [DataRow(KayproSdkModules.MonitorSource, "81-149c.rom")]
    [DataRow(KayproSdkModules.CharacterGeneratorSource, "81-146a.bin")]
    public void SourcesMatchTheDumps(string source, string dump)
    {
        string path = Path.Join(External, dump);
        if (!File.Exists(path)) { Assert.Inconclusive($"Set RETROCORE_KAYPRO to the Kaypro dumps ({dump})."); }
        AssemblyResult result = source == KayproSdkModules.MonitorSource
            ? KayproSdkModules.AssembleMonitor(Path.Join(Inputs, source))
            : KayproSdkModules.AssembleCharacterGenerator(Path.Join(Inputs, source));

        byte[] chip = File.ReadAllBytes(path);
        ReadOnlySpan<byte> built = result.Sections[0].Bytes.Span;
        built.CommonPrefixLength(chip).Should().Be(chip.Length, "the source should assemble to the chip");
        built.Length.Should().Be(chip.Length);
    }

    /// <summary>
    ///  With no disk, the ROM signs on and asks for one.
    /// </summary>
    [TestMethod]
    public void AsksForADiskette()
    {
        KayproMachine machine = Create();
        machine.Reset();
        RunUntil(machine, "Please place your diskette into Drive A", seconds: 3);
        Screen(machine).Should().Contain("*    KAYPRO II    *");
    }

    /// <summary>
    ///  A reset after CP/M has banked the ROM out starts the ROM again: the system PIO resets, so the latch CP/M left
    ///  doesn't drive the port while the ROM sets the PIO up.
    /// </summary>
    [TestMethod]
    public void ResetAfterCpmBanksTheRomIn()
    {
        KayproMachine machine = Create();
        machine.Reset();

        // As CP/M has the system port: bit control mode, bits 2 and 3 inputs, and the ROM out with drive A selected.
        machine.Bus.Out(0x1D, 0xCF);
        machine.Bus.Out(0x1D, 0x0C);
        machine.Bus.Out(0x1C, 0x01);
        machine.Bus.RomBanked.Should().BeFalse();

        machine.Reset();
        machine.Bus.RomBanked.Should().BeTrue();
        RunUntil(machine, "Please place your diskette into Drive A", seconds: 3);
    }

    /// <summary>
    ///  A Ctrl+C drops the keys still queued, such as the rest of a paste, and the one the SIO holds unread, and is
    ///  the next key the program reads.
    /// </summary>
    [TestMethod]
    public void CtrlCDropsQueuedKeys()
    {
        KayproMachine machine = Create();
        Type(machine, "DIR A:");

        // The first key reaches the SIO, unread; Ctrl+C takes its place too.
        machine.Bus.Tick();
        machine.Bus.Keyboard.Type(0x03);
        machine.Bus.Keyboard.IsTyping.Should().BeTrue();

        // The ROM isn't reading the keyboard yet, so take the codes from the SIO as a program would.
        List<byte> read = [];
        for (int tick = 0; tick < 100_000 && machine.Bus.Keyboard.IsTyping; tick++)
        {
            machine.Bus.Tick();
            if ((machine.Bus.In(0x07) & 1) != 0) { read.Add(machine.Bus.In(0x05)); }
        }

        read.Should().Equal([0x03]);
    }

    /// <summary>
    ///  The ROM's console handles its cursor addressing, clearing and scrolling as CP/M's programs use them.
    /// </summary>
    [TestMethod]
    public void VideoOutScrollsAndAddressesTheCursor()
    {
        KayproMachine machine = Create();
        machine.Reset();

        // CALL VIDEO_OUT for each character, from a little program in RAM above the ROM's bank.
        // Clear the screen, show 30 lines so it scrolls, then move to line 5, column 16 and show AT.
        string text = "\x1A" + string.Concat(Enumerable.Range(0, 30).Select(line => $"LINE {line}\r\n")) + "\u001B=%0AT";
        Print(machine, text);
        string screen = Screen(machine);
        screen.Should().Contain("LINE 29");
        screen.Should().NotContain("LINE 5\n");
        Row(machine, 5).Should().Be("LINE 12         AT_", "the cursor, a blinking underline, follows");
    }

    /// <summary>
    ///  CP/M boots from its Kaypro II system disk, and DIR lists it.
    /// </summary>
    [TestMethod]
    public void BootsCpm()
    {
        KayproMachine machine = Boot("cpm22-rom149.img");
        RunUntil(machine, "A>", seconds: 10);
        Screen(machine).Should().Contain("KAYPRO II 64k CP/M vers 2.2");
        Type(machine, "DIR\r");
        RunUntil(machine, "PIP", seconds: 10);
    }

    /// <summary>
    ///  A raw image reads as forty tracks of ten 512-byte sectors and writes back the same.
    /// </summary>
    [TestMethod]
    public void RawImagesRoundTrip()
    {
        byte[] image = new byte[KayproFormat.SingleSidedLength];
        Random.Shared.NextBytes(image);
        (FloppyDisk disk, string format) = Trs80DiskImage.ReadKaypro(image, ".img");
        format.Should().Be("IMG");
        disk.Track(39, 0).Should().HaveCount(10);
        disk.Track(0, 0)[0].Sector.Should().Be(0);
        EncodedImage encoded = KayproFormat.Encode(disk);
        encoded.Losses.Should().BeEmpty();
        encoded.Bytes.Should().Equal(image);
    }

    /// <summary>
    ///  Creates a Kaypro II with the SDK's ROMs.
    /// </summary>
    /// <returns>The machine, not yet reset.</returns>
    internal static KayproMachine Create()
    {
        AssemblyResult monitor = KayproSdkModules.AssembleMonitor(Path.Join(Inputs, KayproSdkModules.MonitorSource));
        AssemblyResult characters = KayproSdkModules.AssembleCharacterGenerator(
            Path.Join(Inputs, KayproSdkModules.CharacterGeneratorSource));

        return new(new KayproRoms(monitor.Sections[0].Bytes.Span, characters.Sections[0].Bytes.Span));
    }

    /// <summary>
    ///  Creates a Kaypro II with disks in its drives and resets it.
    /// </summary>
    /// <param name="disks">The disks' file names in <see cref="External"/>, drive A first.</param>
    /// <returns>The machine.</returns>
    internal static KayproMachine Boot(params string[] disks)
    {
        KayproMachine machine = Create();
        for (int drive = 0; drive < disks.Length; drive++)
        {
            string path = Path.Join(External, disks[drive]);
            if (!File.Exists(path))
            {
                Assert.Inconclusive($"Set RETROCORE_KAYPRO to the Kaypro disks ({disks[drive]}).");
            }

            (FloppyDisk disk, string format) = Trs80DiskImage.ReadKaypro(File.ReadAllBytes(path), ".img");
            machine.Drives[drive].Insert(disk, disks[drive], format);
        }

        machine.Reset();
        return machine;
    }

    /// <summary>
    ///  Runs until the screen shows some text.
    /// </summary>
    /// <param name="machine">The machine.</param>
    /// <param name="text">The text.</param>
    /// <param name="seconds">The most seconds of machine time to run.</param>
    internal static void RunUntil(KayproMachine machine, string text, int seconds)
    {
        for (int tenth = 0; tenth < seconds * 10; tenth++)
        {
            if (Screen(machine).Contains(text, StringComparison.Ordinal)) { return; }
            machine.Run(KayproTiming.ClockHertz / 10);
        }

        Assert.Fail($"No \"{text}\" after {seconds} seconds. The screen:\n{Screen(machine)}");
    }

    /// <summary>
    ///  Types text on the keyboard.
    /// </summary>
    /// <param name="machine">The machine.</param>
    /// <param name="text">The text, ASCII.</param>
    internal static void Type(KayproMachine machine, string text)
    {
        foreach (char key in text) { machine.Bus.Keyboard.Type((byte)key); }
    }

    /// <summary>
    ///  Gets the screen's text, each line ending in a line feed.
    /// </summary>
    /// <param name="machine">The machine.</param>
    /// <returns>The text.</returns>
    internal static string Screen(KayproMachine machine) =>
        string.Concat(Enumerable.Range(0, KayproVideo.Rows).Select(row => Row(machine, row) + "\n"));

    /// <summary>
    ///  Gets a line of the screen's text, without trailing spaces.
    /// </summary>
    /// <param name="machine">The machine.</param>
    /// <param name="row">The line, 0-23.</param>
    /// <returns>The text.</returns>
    internal static string Row(KayproMachine machine, int row) =>
        new string([.. Enumerable.Range(0, KayproVideo.Columns)
            .Select(column => machine.Bus.Video.Character(machine.Bus.Video.Displayed(row, column)))
            .Select(character => character == '\0' ? ' ' : character)]).TrimEnd();

    // Shows text through the ROM's VIDEO_OUT from a fresh screen, calling it from RAM at $8000.
    private static void Print(KayproMachine machine, string text)
    {
        const ushort Code = 0x8000;
        byte[] program = new byte[(text.Length * 5) + 5];
        int at = 0;
        program[at++] = 0xCD;               // CALL VIDEO_RESET_ENTRY
        program[at++] = 0x06;
        program[at++] = 0x00;
        foreach (char character in text)
        {
            program[at++] = 0x0E;           // LD C,character
            program[at++] = (byte)character;
            program[at++] = 0xCD;           // CALL VIDEO_OUT_ENTRY
            program[at++] = 0x45;
            program[at++] = 0x00;
        }

        program[at++] = 0x18;               // JR *
        program[at] = 0xFE;
        for (int index = 0; index < program.Length; index++)
        {
            machine.Bus.PokeRam((ushort)(Code + index), program[index]);
        }

        while (!machine.Processor.IsInstructionBoundary) { machine.StepCycle(); }
        machine.Processor.Registers = machine.Processor.Registers with { PC = Code, SP = 0xF000 };
        for (int step = 0; step < 2_000_000 && machine.Processor.Registers.PC != Code + program.Length - 2; step++)
        {
            machine.StepInstruction();
        }
    }

    private static string Hash(AssemblyResult result) => Convert.ToHexString(SHA256.HashData(result.Sections[0].Bytes.Span));
}
