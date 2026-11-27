// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using Retrocore.Machines.Devices;
using Retrocore.Machines.Trs80Model100;

namespace Retrocore.Tests;

/// <summary>
///  The Model 100's cassette port and buzzer: tapes in and out of WAV files, the motor, SOD and SID, and the ROM's
///  own CSAVE and CLOAD.
/// </summary>
[TestClass]
public sealed class Trs80Model100CassetteTests
{
    /// <summary>
    ///  A tape written as a WAV file reads back with the same level changes, each within a sample's time.
    /// </summary>
    [TestMethod]
    public void TapesRoundTripThroughWave()
    {
        // 1200 and 2400 Hz half cycles, as the ROM writes them.
        int[] halves = [1024, 1024, 512, 512, 1024, 1024, 600, 512];
        Trs80Model100Tape tape = new(startsHigh: false, halves);
        Trs80Model100Tape read = Trs80Model100Tape.FromWave(tape.ToWave());
        read.StartsHigh.Should().BeFalse();
        read.HalfCycles.Should().HaveCount(halves.Length, "the file ends a sample after the last change");
        int sample = Trs80Model100Timing.ClockHertz / 44100;
        for (int index = 0; index < read.HalfCycles.Count; index++)
        {
            read.HalfCycles[index].Should().BeCloseTo(halves[index], (uint)sample + 1, "half cycle {0}", index);
        }

        ((Action)(() => Trs80Model100Tape.FromWave("not a wave"u8))).Should().Throw<InvalidDataException>();

        // The same samples as WAVE_FORMAT_EXTENSIBLE with the PCM subformat, and a file that starts silent.
        Trs80Model100Tape extensible = Trs80Model100Tape.FromWave(Extensible(tape.ToWave()));
        extensible.HalfCycles.Should().Equal(read.HalfCycles);
        byte[] silent = new Trs80Model100Tape(startsHigh: true, [5000]).ToWave();
        silent.AsSpan(44).Clear();
        Trs80Model100Tape.FromWave(silent).StartsHigh.Should().BeFalse("silence starts low");
    }

    /// <summary>
    ///  A tape plays only while the motor runs, SID reads its level inverted and is high with no tape, and a recording
    ///  takes SOD's changes only while the motor runs, keeping its level SOD's.
    /// </summary>
    [TestMethod]
    public void TheMotorMovesTheTape()
    {
        Trs80Model100Cassette cassette = new();
        cassette.SerialInput.Should().BeTrue("with no tape, the input is low, so SID is high");
        cassette.Play(new Trs80Model100Tape(startsHigh: true, [10, 20]));
        cassette.SerialInput.Should().BeFalse("a high level reads low");
        for (int cycle = 0; cycle < 50; cycle++) { cassette.Tick(motor: false, output: false); }
        cassette.Position.Should().Be(0, "the motor is off");

        for (int cycle = 0; cycle < 10; cycle++) { cassette.Tick(motor: true, output: false); }
        cassette.Position.Should().Be(1);
        cassette.SerialInput.Should().BeTrue();
        for (int cycle = 0; cycle < 20; cycle++) { cassette.Tick(motor: true, output: false); }
        cassette.AtEnd.Should().BeTrue();

        Trs80Model100Tape recording = new();
        cassette.Record(recording);
        cassette.SerialInput.Should().BeTrue("a recording does not play");
        bool level = false;
        Toggle(cassette, motor: true, [30, 5], ref level);
        Toggle(cassette, motor: false, [100], ref level);
        Toggle(cassette, motor: true, [7], ref level);
        // SOD changed while the motor was stopped, so the tape takes that change as it moves again, a half of one
        // cycle, then the next.
        recording.HalfCycles.Should().Equal(30, 5, 1, 6);
        cassette.SerialInput.Should().Be(!level, "while recording, SID reads SOD back inverted");
        recording.StartsHigh.Should().BeFalse();
    }

    /// <summary>
    ///  The buzzer follows port B bit 5 while bit 2 is set, and the 81C55's timer output while bit 2 is clear and bit 5
    ///  set; the timer's square wave reaches the sound's sink.
    /// </summary>
    [TestMethod]
    public void TheBuzzerFollowsItsSource()
    {
        Trs80Model100Machine machine = new(new(), new(new byte[Trs80Model100Roms.RomSize]));
        Trs80Model100Bus bus = machine.Bus;

        // Port B as outputs, then bit 2 with bit 5 high and low.
        bus.Out(0xB0, 0x02);
        bus.Out(0xB2, 0x24);
        bus.Speaker.Should().BeTrue();
        bus.Out(0xB2, 0x04);
        bus.Speaker.Should().BeFalse();

        // The timer at 100 counts in square-wave mode, its output on the buzzer with bit 2 clear and bit 5 set.
        bus.Out(0xB4, 100);
        bus.Out(0xB5, 0x40);
        bus.Out(0xB0, 0xC2);
        bus.Out(0xB2, 0x20);
        PeakAudioSink sink = new();
        bus.Audio.Sink = sink;
        int changes = 0;
        bool last = bus.Speaker;
        for (int cycle = 0; cycle < 20_000; cycle++)
        {
            machine.StepCycle();
            if (bus.Speaker != last) { changes++; last = bus.Speaker; }
        }

        bus.Audio.Flush();
        changes.Should().BeGreaterThan(100, "the timer toggles the buzzer");
        sink.Peak.Should().BeGreaterThan(0.1f);
        machine.Devices.Should().ContainSingle().Which.Should().BeSameAs(bus.CassetteDrive);

        // The motor stops with the power.
        bus.CassetteDrive.Record(new Trs80Model100Tape(), "tape.wav");
        bus.Out(0xE0, 0x08);
        machine.StepCycle();
        bus.CassetteDrive.Transport.Motor.Should().BeTrue();
        bus.Out(0xB2, 0x10);
        machine.StepCycle();
        machine.IsPoweredOff.Should().BeTrue();
        bus.CassetteDrive.Transport.Motor.Should().BeFalse("the power is off");
    }

    /// <summary>
    ///  A program the ROM saves with CSAVE goes on tape in the blocks MAME 0.264 records (a leader of $55, $7F, a
    ///  header of $D3 and the name, then a data block of $8D and the program), and another machine's ROM loads it
    ///  back with CLOAD; inconclusive without the user's ROM.
    /// </summary>
    [TestMethod]
    public void CsaveAndCloadRoundTrip()
    {
        Trs80Model100Machine saver = Trs80Model100RomTests.Boot("m100.bin");
        Trs80Model100RomTests.Type(saver, "BASIC\r");
        saver.RunSeconds(1);
        Trs80Model100RomTests.Type(saver, "10 PRINT \"TAPE\";6*7\r");
        Trs80Model100Tape tape = new();
        saver.Bus.CassetteDrive.Record(tape, "tape.wav");
        saver.Bus.CassetteDrive.Activity.Should().Be(DeviceActivity.Idle, "the motor is off until CSAVE runs it");
        Trs80Model100RomTests.Type(saver, "CSAVE \"PROG\"\r");
        saver.RunSeconds(15);
        saver.Bus.CassetteMotor.Should().BeFalse("CSAVE stops the motor when it is done");
        saver.Bus.CassetteDrive.Eject().Should().BeSameAs(tape);

        List<byte[]> blocks = Blocks(tape);
        blocks.Should().HaveCount(2);
        blocks[0][0].Should().Be(0xD3);
        System.Text.Encoding.ASCII.GetString(blocks[0], 1, 6).Should().Be("PROG  ");
        blocks[1][0].Should().Be(0x8D);

        Trs80Model100Machine loader = Trs80Model100RomTests.Boot("m100.bin");
        Trs80Model100RomTests.Type(loader, "BASIC\r");
        loader.RunSeconds(1);
        loader.Bus.CassetteDrive.Play(Trs80Model100Tape.FromWave(tape.ToWave()), "tape.wav");
        Trs80Model100RomTests.Type(loader, "CLOAD \"PROG\"\r");
        loader.RunSeconds(15);
        Trs80Model100RomTests.Type(loader, "RUN\r");
        loader.RunSeconds(1);
        string screen = string.Join("\n", loader.ScreenText());
        screen.Should().Contain("Found:PROG").And.Contain("TAPE 42");
    }

    /// <summary>
    ///  BASIC's BEEP sounds the buzzer; inconclusive without the user's ROM.
    /// </summary>
    [TestMethod]
    public void BeepSounds()
    {
        Trs80Model100Machine machine = Trs80Model100RomTests.Boot("m100.bin");
        Trs80Model100RomTests.Type(machine, "BASIC\r");
        machine.RunSeconds(1);
        PeakAudioSink sink = new();
        machine.Bus.Audio.Sink = sink;
        Trs80Model100RomTests.Type(machine, "BEEP\r");
        machine.RunSeconds(1);
        machine.Bus.Audio.Flush();
        sink.Peak.Should().BeGreaterThan(0.1f);
    }

    // A 16-bit mono WAV file rewritten with a WAVE_FORMAT_EXTENSIBLE fmt chunk of 40 bytes, its subformat PCM.
    private static byte[] Extensible(byte[] wave)
    {
        byte[] data = wave[36..];
        byte[] file = new byte[12 + 8 + 40 + data.Length];
        wave.AsSpan(0, 12).CopyTo(file);
        System.Buffers.Binary.BinaryPrimitives.WriteInt32LittleEndian(file.AsSpan(4), file.Length - 8);
        "fmt "u8.CopyTo(file.AsSpan(12));
        System.Buffers.Binary.BinaryPrimitives.WriteInt32LittleEndian(file.AsSpan(16), 40);
        wave.AsSpan(20, 16).CopyTo(file.AsSpan(20));
        System.Buffers.Binary.BinaryPrimitives.WriteUInt16LittleEndian(file.AsSpan(20), 0xFFFE);
        System.Buffers.Binary.BinaryPrimitives.WriteUInt16LittleEndian(file.AsSpan(36), 22);
        System.Buffers.Binary.BinaryPrimitives.WriteUInt16LittleEndian(file.AsSpan(38), 16);
        System.Buffers.Binary.BinaryPrimitives.WriteUInt16LittleEndian(file.AsSpan(44), 1);
        data.CopyTo(file.AsSpan(60));
        return file;
    }

    // Changes SOD after each count of cycles, keeping its level from one call to the next.
    private static void Toggle(Trs80Model100Cassette cassette, bool motor, int[] counts, ref bool level)
    {
        foreach (int count in counts)
        {
            for (int cycle = 1; cycle < count; cycle++) { cassette.Tick(motor, level); }
            level = !level;
            cassette.Tick(motor, level);
        }
    }

    // The tape's blocks. A cycle of 2400 Hz is a 1 and one of 1200 Hz a 0, its halves alike; a half that does not
    // pair with the next is skipped. After a leader of $55 (least significant bit first) and $7F, a block is bytes of
    // eight bits, most significant first, each with a ninth after it, up to the next leader.
    private static List<byte[]> Blocks(Trs80Model100Tape tape)
    {
        int threshold = Trs80Model100Timing.ClockHertz / 1800 / 2;
        IReadOnlyList<int> halves = tape.HalfCycles;
        char[] bits = new char[halves.Count];
        int count = 0;
        int index = 0;
        while (index + 1 < halves.Count)
        {
            bool shortFirst = halves[index] < threshold;
            if (shortFirst != halves[index + 1] < threshold)
            {
                index++;
                continue;
            }

            bits[count++] = shortFirst ? '1' : '0';
            index += 2;
        }

        string stream = new(bits, 0, count);
        const string Sync = "1010101011111110";
        List<byte[]> blocks = [];
        int at = stream.IndexOf(Sync, StringComparison.Ordinal);
        while (at >= 0)
        {
            int start = at + Sync.Length;
            int next = stream.IndexOf(Sync, start, StringComparison.Ordinal);
            int end = next < 0 ? stream.Length : next;
            List<byte> bytes = [];
            for (int bit = start; bit + 9 <= end; bit += 9) { bytes.Add(Convert.ToByte(stream.Substring(bit, 8), 2)); }
            blocks.Add([.. bytes]);
            at = next;
        }

        return blocks;
    }
}
