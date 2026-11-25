// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using Retrocore.Machines.Atari;
using Retrocore.Media.Atari;

namespace Retrocore.Tests;

/// <summary>
///  The 410 Program Recorder and the OS's <c>C:</c> handler: BASIC's tape commands, a boot tape, and MAME's Serpentine
///  tape (<c>%USERPROFILE%\Retrocore\atari8-media\tapes</c>).
/// </summary>
/// <remarks>
///  <para>
///   MAME 0.289 can't check these: its <c>a800</c> cassette is unfinished (the driver lists it as a TODO), and its
///   decoder, counting 44.1 kHz ticks between zero crossings, takes some half-cycles of the 5,327 Hz mark for space.
///   The tapes here are checked by the OS itself, which tests each record's checksum.
///  </para>
/// </remarks>
[TestClass]
public class AtariTapeTests
{
    private static string Text(string[] screen) => string.Join('\n', screen.Select(line => line.TrimEnd()));

    // Runs until the motor has stopped and BASIC is READY, for up to some emulated seconds.
    private static void RunToReady(AtariMachine machine, int seconds = 60)
    {
        for (int tenth = 0; tenth < seconds * 4; tenth++)
        {
            machine.Run(TimeSpan.FromSeconds(0.25));
            string[] screen = machine.ReadTextScreen();
            bool ready = screen[^2].Trim() == "READY" || screen[^1].Trim() == "READY";
            if (ready && !machine.Cassette.Motor) { return; }
        }
    }

    // Types a tape command and presses RETURN at the OS's beep, as the C: handler asks.
    private static void TapeCommand(AtariMachine machine, string command)
    {
        AtariMachineTests.Type(machine, command + "\r");
        machine.Run(TimeSpan.FromSeconds(1));
        AtariMachineTests.Type(machine, "\r");
        machine.Run(TimeSpan.FromSeconds(2));
        RunToReady(machine);
    }

    /// <summary>
    ///  <c>CSAVE</c> records the program on a blank tape (the OS's 20-second leader, then its records), and
    ///  <c>CLOAD</c> reads it back.
    /// </summary>
    [TestMethod]
    public void CsaveAndCloadRoundTrip()
    {
        AtariMachine machine = AtariMachineTests.Machine(basic: 'C');
        AtariMachineTests.RunToReady(machine);
        AtariMachineTests.Type(machine, "10 PRINT \"FROM TAPE\"\r");

        AtariTape tape = new();
        machine.Cassette.Insert(tape);
        machine.Cassette.Record();
        TapeCommand(machine, "CSAVE");
        machine.Cassette.Stop();
        tape.IsDirty.Should().BeTrue();
        tape.Blocks.Count.Should().BeGreaterThanOrEqualTo(2);
        tape.Blocks[0].Gap.Should().BeInRange(15_000, 25_000, "the OS writes a long leader");
        tape.Blocks[0].Baud.Should().BeInRange(590, 610);
        tape.Blocks[^1].Data[2].Should().Be(0xFE, "the last record ends the file");

        machine.Cassette.Rewind();
        machine.Cassette.Play();
        AtariMachineTests.Type(machine, "NEW\r");
        TapeCommand(machine, "CLOAD");
        AtariMachineTests.Type(machine, "RUN\r");
        string[] screen = machine.ReadTextScreen();
        screen.Should().Contain(line => line.Trim() == "FROM TAPE", Text(screen));
    }

    /// <summary>
    ///  A gap longer than a <c>.cas</c> chunk's 16-bit field is saved as the longest it holds, not wrapped, and a
    ///  record longer than its length field goes as two chunks, the second with no gap.
    /// </summary>
    [TestMethod]
    public void LongGapsAndRecordsFitTheFields()
    {
        AtariTape tape = new([new(Gap: 70_000, Baud: AtariTape.StandardBaud, Data: [0x55, 0x55, 0xFC], Durations: null)]);
        AtariTape.Load(tape.ToCas()).Blocks[0].Gap.Should().Be(ushort.MaxValue);

        byte[] data = new byte[70_000];
        data.AsSpan().Fill(0x5A);
        tape = new([new(Gap: 100, Baud: AtariTape.StandardBaud, Data: data, Durations: null)]);
        IReadOnlyList<AtariTapeBlock> blocks = AtariTape.Load(tape.ToCas()).Blocks;
        blocks.Should().HaveCount(2);
        blocks[0].Gap.Should().Be(100);
        blocks[1].Gap.Should().Be(0);
        blocks.Sum(block => block.Data.Length).Should().Be(70_000);

        // Raw tone splits after an even number of runs, so the second chunk starts on space as its run does.
        ushort[] durations = new ushort[40_001];
        for (int i = 0; i < durations.Length; i++) { durations[i] = (ushort)(1 + (i % 3)); }
        AtariTapeBlock tone = new(Gap: 0, Baud: AtariTape.StandardBaud, Data: [], Durations: durations);
        blocks = AtariTape.Load(new AtariTape([tone]).ToCas()).Blocks;
        blocks.Should().HaveCount(2);
        double split = blocks[0].Duration;
        foreach (double at in (double[])[split - 0.00005, split + 0.00005, split + 0.5, tone.Duration - 0.00005])
        {
            bool level = at < split ? blocks[0].LevelAt(at) : blocks[1].LevelAt(at - split);
            level.Should().Be(tone.LevelAt(at), $"the level {at} s in");
        }
    }

    /// <summary>
    ///  A tape protected after RECORD goes down records nothing, and <c>CSAVE</c> runs on without the recorder failing.
    /// </summary>
    [TestMethod]
    public void TapeProtectedAfterRecordKeepsItsBlocks()
    {
        AtariMachine machine = AtariMachineTests.Machine(basic: 'C');
        AtariMachineTests.RunToReady(machine);
        AtariMachineTests.Type(machine, "10 PRINT \"FROM TAPE\"\r");

        AtariTape tape = new();
        tape.Append(new(Gap: 1000, Baud: AtariTape.StandardBaud, Data: [0x55, 0x55, 0xFC], Durations: null));
        machine.Cassette.Insert(tape);
        machine.Cassette.Record();
        tape.IsWriteProtected = true;
        TapeCommand(machine, "CSAVE");
        machine.Cassette.Stop();
        tape.Blocks.Should().ContainSingle("the protected tape keeps the block it had");
    }

    /// <summary>
    ///  <c>SAVE "C:"</c> and <c>LOAD "C:"</c> go through CIO to the cassette, the same round trip.
    /// </summary>
    [TestMethod]
    public void SaveAndLoadThroughCio()
    {
        AtariMachine machine = AtariMachineTests.Machine(basic: 'C');
        AtariMachineTests.RunToReady(machine);
        AtariMachineTests.Type(machine, "10 PRINT \"THROUGH CIO\"\r");
        AtariTape tape = new();
        machine.Cassette.Insert(tape);
        machine.Cassette.Record();
        TapeCommand(machine, "SAVE \"C:\"");
        machine.Cassette.Stop();

        // The tape survives a trip through a .cas file.
        AtariTape copy = AtariTape.Load(tape.ToCas());
        copy.Blocks.Should().HaveCount(tape.Blocks.Count);
        machine.Cassette.Insert(copy);
        machine.Cassette.Play();
        AtariMachineTests.Type(machine, "NEW\r");
        TapeCommand(machine, "LOAD \"C:\"");
        AtariMachineTests.Type(machine, "RUN\r");
        string[] screen = machine.ReadTextScreen();
        screen.Should().Contain(line => line.Trim() == "THROUGH CIO", Text(screen));
    }

    /// <summary>
    ///  Holding START at power-on boots the tape: the OS loads its records at the boot header's address, calls the
    ///  code after the header, and jumps through <c>DOSVEC</c>, which the code set.
    /// </summary>
    [TestMethod]
    public void StartBootsATape()
    {
        byte[] program =
        [
            0x00, 0x01, 0x00, 0x30, 0x14, 0x30,             // one record at $3000, CASINI = $3014 (an RTS)
            0xA9, 0x55, 0x8D, 0x00, 0x06,                   // $3006: LDA #$55; STA $0600
            0xA9, 0x15, 0x85, 0x0A, 0xA9, 0x30, 0x85, 0x0B, // DOSVEC = $3015
            0x18, 0x60,                                     // $3013: CLC; RTS
            0x4C, 0x15, 0x30                                // $3015: JMP $3015
        ];

        AtariMachine machine = AtariMachineTests.Machine();
        machine.Cassette.Insert(AtariTapeBuilder.BootTape(program));
        machine.Cassette.Play();
        machine.Keyboard.ConsoleKeys = AtariConsoleKeys.Start;
        machine.Run(TimeSpan.FromSeconds(2));
        machine.Keyboard.ConsoleKeys = AtariConsoleKeys.None;
        AtariMachineTests.Type(machine, "\r");
        machine.Run(TimeSpan.FromSeconds(30));
        machine.Bus.Peek(0x0600).Should().Be(0x55, "the boot code ran");
        machine.Processor.Registers.ProgramCounter.Should().BeInRange((ushort)0x3015, (ushort)0x3017, "DOSVEC runs");
    }

    /// <summary>
    ///  Serpentine, a commercial boot tape from MAME's <c>a800_cass</c> list, loads its game (82 of its 140 blocks; the
    ///  rest are another side's levels) through the OS's boot and its own loader, which times each record's
    ///  <c>$55</c> bytes for the baud rate as the OS does.
    /// </summary>
    [TestMethod]
    public void SerpentineBootsFromTape()
    {
        string path = Path.Join(ExternalTestData.Root, "atari8-media", "tapes", "serpentine (atari 400) (side a).cas");
        if (!File.Exists(path)) { Assert.Inconclusive($"Serpentine's tape isn't at {path}."); }
        AtariTape tape = AtariTape.Load(File.ReadAllBytes(path));
        tape.Blocks.Should().HaveCount(140);

        AtariMachine machine = AtariMachineTests.Machine();
        machine.Cassette.Insert(tape);
        machine.Cassette.Play();
        machine.Keyboard.ConsoleKeys = AtariConsoleKeys.Start;
        machine.Run(TimeSpan.FromSeconds(2));
        machine.Keyboard.ConsoleKeys = AtariConsoleKeys.None;
        AtariMachineTests.Type(machine, "\r");
        for (int second = 0; second < 300 && (machine.Cassette.Block < 82 || machine.Cassette.Motor); second += 5)
        {
            machine.Run(TimeSpan.FromSeconds(5));
        }

        machine.Cassette.Block.Should().Be(82, "the game's records are in");
        machine.Cassette.Motor.Should().BeFalse("the game stopped the tape");
        machine.Run(TimeSpan.FromSeconds(5));
        machine.Processor.Registers.ProgramCounter.Should().BeLessThan(0xC000, "the game runs from RAM");
    }

    /// <summary>
    ///  A <c>.cas</c> file round-trips its blocks, rates and raw tone; a block's bits are a start bit, the byte low bit
    ///  first, and a stop bit; and the WAV has the 410's tones.
    /// </summary>
    [TestMethod]
    public void CasAndWaveFormats()
    {
        AtariTape tape = new(
        [
            new(1000, 600, [0x55, 0x80], Durations: null),
            new(250, 1200, [0x01], Durations: null),
            new(100, 1200, [], [20, 30])
        ],
            "Test");

        AtariTape copy = AtariTape.Load(tape.ToCas());
        copy.Description.Should().Be("Test");
        copy.Blocks.Select(b => (b.Gap, b.Baud)).Should().Equal((1000, 600), (250, 1200), (100, 1200));
        copy.Blocks[0].Data.Should().Equal(0x55, 0x80);
        copy.Blocks[2].Durations.Should().Equal(20, 30);

        AtariTapeBlock block = copy.Blocks[0];
        double bit = 1.0 / 600;
        block.LevelAt(0.5).Should().BeTrue("the gap is mark");
        block.LevelAt(1.0 + (bit * 0.5)).Should().BeFalse("the start bit is space");
        block.LevelAt(1.0 + (bit * 1.5)).Should().BeTrue("$55's bit 0");
        block.LevelAt(1.0 + (bit * 2.5)).Should().BeFalse("$55's bit 1");
        block.LevelAt(1.0 + (bit * 9.5)).Should().BeTrue("the stop bit is mark");
        copy.Blocks[2].LevelAt(0.1 + 0.001).Should().BeFalse("raw tone starts with space");
        copy.Blocks[2].LevelAt(0.1 + 0.003).Should().BeTrue();

        byte[] wave = AtariTapeWave.Write(copy, 44_100);
        wave.AsSpan(0, 4).SequenceEqual("RIFF"u8).Should().BeTrue();
        int crossings = 0;
        for (int i = 1; i < 44_100 / 2; i++)
        {
            short a = BitConverter.ToInt16(wave, 44 + ((i - 1) * 2));
            short b = BitConverter.ToInt16(wave, 44 + (i * 2));
            if ((a < 0) != (b < 0)) { crossings++; }
        }

        (crossings / 2.0 / 0.5).Should().BeApproximately(AtariTapeWave.MarkHertz, 30, "the first half second is mark tone");
    }
}
