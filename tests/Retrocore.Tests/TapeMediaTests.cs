// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using Retrocore.Debug;
using Retrocore.Machines.Altair;
using Retrocore.Machines.Apple1;
using Retrocore.Machines.Devices;
using Retrocore.Machines.Trs80;
using Retrocore.Machines.Trs80Model100;
using Retrocore.Media.Trs80;
using System.Text.Json.Nodes;

namespace Retrocore.Tests;

/// <summary>
///  Recordings as changed tapes, as the media persistence plan's fourth phase has them: a recorder that records to a
///  file writes the file blank as it starts, and what it records is a change to that tape, saved through the host's
///  save steps, kept in the recovery journal at a checkpoint, a stop or a crash, and put back in the next launch. The
///  TRS-80's recorder holds its bits until the motor stops; a snapshot takes the bytes they make without stopping it.
/// </summary>
[TestClass]
public sealed class TapeMediaTests
{
    private static string s_root = "";

    /// <summary>
    ///  Makes the tests' folder.
    /// </summary>
    /// <param name="context">The test context.</param>
    [ClassInitialize]
    public static void Initialize(TestContext context)
    {
        s_root = Path.Join(Path.GetTempPath(), $"retrocore-tapes-{Environment.ProcessId}");
        Directory.CreateDirectory(s_root);
    }

    /// <summary>
    ///  Removes the tests' folder.
    /// </summary>
    [ClassCleanup]
    public static void Cleanup() => Directory.Delete(s_root, recursive: true);

    /// <summary>
    ///  A TRS-80's CSAVE caught while its recorder still holds every bit: the tape is changed though no byte is on it
    ///  yet, a checkpoint waits for the recorder and then takes the bytes the bits make, without the recorder letting
    ///  them go, and a session that stops there leaves them in the journal. The next launch puts the tape back changed,
    ///  as far as the recording got, and it saves to the recording's file; the whole recording begins with it.
    /// </summary>
    [TestMethod]
    public void ACsaveStoppedMidRecordingComesBackAsFarAsItGot()
    {
        string id = Id();
        string cas = Path.Join(s_root, $"stopped-{Guid.NewGuid():N}.cas");
        Trs80DebugTarget target = Trs80();
        Trs80CassetteDrive drive = target.Machine.Cassette;
        Type(target.Machine, "10 PRINT \"KEPT\";6*7\r");
        Act(target, drive, "record", At(cas)).Should().BeNull("there is no tape in the recorder");
        File.ReadAllBytes(cas).Should().BeEmpty("the recording's file is written blank as it starts");
        drive.Media?.Changed.Should().BeFalse("nothing is recorded yet");

        Type(target.Machine, "CSAVE \"K\"\r");
        RunUntil(target.Machine, () => target.Machine.Bus.Cassette.MotorOn, seconds: 5);
        Run(target.Machine, seconds: 1);
        CassetteImage tape = target.Machine.Cassette.Tape ?? throw new InvalidOperationException("The recorder is empty.");
        tape.Bytes.Should().BeEmpty("the recorder holds its bits until the motor stops");
        drive.Media?.Changed.Should().BeTrue("the recorder heard bits");
        drive.Activity.Should().Be(DeviceActivity.Writing);

        // A snapshot takes the bytes the held bits make, and leaves them held.
        long length = target.Machine.Bus.Cassette.Length;
        byte[] caught = tape.Snapshot().Image.ToArray();
        caught.Length.Should().BeGreaterThan(48, "a second of leader at 500 baud is about 62 bytes");
        tape.Snapshot().Image.ToArray().Should().Equal(caught);
        tape.Bytes.Should().BeEmpty("taking a snapshot does not stop the recorder");
        target.Machine.Bus.Cassette.Length.Should().Be(length);

        // The checkpoint waits for the recorder, then takes the tape as it is, caught mid-write.
        RecoveryJournal journal = Open(id);
        List<JournalDisk> waiting = MediaActions.Journal(target.Devices, journal, idle: true);
        waiting.Single().Waiting.Should().BeTrue();
        journal.Commit(MediaActions.Journal(target.Devices, journal, whole: true), close: true);
        Guid medium = MediaActions.Source(tape)?.Id ?? throw new InvalidOperationException("The tape has no source.");
        journal.KeptOf(medium)?.MidWrite.Should().BeTrue();

        // The machine carries on and finishes the recording, which begins with what was kept.
        RunUntil(target.Machine, () => !target.Machine.Bus.Cassette.MotorOn, seconds: 30);
        tape.Bytes.Count.Should().BeGreaterThan(caught.Length);
        tape.Bytes.Take(caught.Length).Should().Equal(caught);

        // The next launch puts the tape back, as far as it got, changed against the blank file.
        Trs80DebugTarget next = Trs80();
        RecoveryJournal again = Open(id);
        MediaActions.Recover(next.Devices, again).Should().BeEmpty();
        Trs80CassetteDrive back = next.Machine.Cassette;
        back.Media?.Changed.Should().BeTrue();
        back.Media?.Label.Should().Be(cas);
        back.Transport.Mode.Should().Be(TapeMode.Playing, "a recovered tape is there for CLOAD");
        CassetteImage recovered = next.Machine.Cassette.Tape ?? throw new InvalidOperationException("The recorder is empty.");
        recovered.Bytes.Should().Equal(caught);

        Act(next, back, "save", Speaking())?.String("outcome").Should().Be("saved");
        File.ReadAllBytes(cas).Should().Equal(caught);
        back.Media?.Changed.Should().BeFalse();
        again.Commit(MediaActions.Journal(next.Devices, again), close: true);
        Disks(id).Should().BeEmpty("a saved tape leaves the journal");
    }

    /// <summary>
    ///  A TRS-80 host that crashes after a checkpoint kept a whole CSAVE leaves it for the next launch, which puts it
    ///  back in the recorder to play: CLOAD reads the program, and RUN runs it.
    /// </summary>
    [TestMethod]
    public void ACsaveKeptByACrashedSessionLoadsAgain()
    {
        string id = Id();
        string cas = Path.Join(s_root, $"crashed-{Guid.NewGuid():N}.cas");
        Trs80DebugTarget target = Trs80();
        Trs80CassetteDrive drive = target.Machine.Cassette;
        Type(target.Machine, "10 PRINT \"BACK\";7*6\r");
        Act(target, drive, "record", At(cas));
        Type(target.Machine, "CSAVE \"B\"\r");
        RunUntil(target.Machine, () => target.Machine.Bus.Cassette.MotorOn, seconds: 5);
        RunUntil(target.Machine, () => !target.Machine.Bus.Cassette.MotorOn, seconds: 30);
        drive.Activity.Should().Be(DeviceActivity.Idle, "a recorder whose motor stopped is between recordings");

        RecoveryJournal journal = Open(id);
        journal.Commit(MediaActions.Journal(target.Devices, journal, idle: true));
        Crash(journal);
        Offered(id).Should().NotBeNull("a session that did not stop cleanly is offered");

        Trs80DebugTarget next = Trs80();
        RecoveryJournal again = Open(id);
        MediaActions.Recover(next.Devices, again).Should().BeEmpty();
        next.Machine.Cassette.Media?.Changed.Should().BeTrue();
        Type(next.Machine, "CLOAD \"B\"\r");
        RunUntil(next.Machine, () => next.Machine.Bus.Cassette.MotorOn, seconds: 5);
        RunUntil(next.Machine, () => !next.Machine.Bus.Cassette.MotorOn, seconds: 30);
        Type(next.Machine, "CLS\r");
        Run(next.Machine, seconds: 0.5);
        Type(next.Machine, "RUN\r");
        Run(next.Machine, seconds: 1);
        Screen(next.Machine).Should().Contain("BACK 42");
        again.Commit(MediaActions.Journal(next.Devices, again), close: true);
    }

    /// <summary>
    ///  A TRS-80 recording that cannot be written stays changed in the recorder and in the journal: a read-only file
    ///  answers <c>readOnly</c>, and a folder that went away fails the save; the eject still asks, and once the file
    ///  can be written the recording saves.
    /// </summary>
    [TestMethod]
    public void AFailedWriteKeepsTheRecording()
    {
        string id = Id();
        string folder = Path.Join(s_root, $"failing-{Guid.NewGuid():N}");
        Directory.CreateDirectory(folder);
        string cas = Path.Join(folder, "program.cas");
        Trs80DebugTarget target = Trs80();
        Trs80CassetteDrive drive = target.Machine.Cassette;
        Type(target.Machine, "10 PRINT 1\r");
        Act(target, drive, "record", At(cas));
        Type(target.Machine, "CSAVE \"F\"\r");
        RunUntil(target.Machine, () => target.Machine.Bus.Cassette.MotorOn, seconds: 5);
        RunUntil(target.Machine, () => !target.Machine.Bus.Cassette.MotorOn, seconds: 30);
        CassetteImage tape = target.Machine.Cassette.Tape ?? throw new InvalidOperationException("The recorder is empty.");
        byte[] recorded = tape.ToArray();

        File.SetAttributes(cas, FileAttributes.ReadOnly);
        JsonObject? refused = Act(target, drive, "save", Speaking());
        refused?.String("outcome").Should().Be("readOnly");
        refused?.String("reason").Should().Be("file");
        File.SetAttributes(cas, FileAttributes.Normal);
        File.ReadAllBytes(cas).Should().BeEmpty();
        drive.Media?.Changed.Should().BeTrue();

        // The folder goes; saving there again, as agreed, cannot write the file.
        Directory.Delete(folder, recursive: true);
        Act(target, drive, "save", Speaking())?.String("outcome").Should().Be("conflict", "the blank file is gone");
        JsonObject again = Speaking();
        again["overwrite"] = new JsonObject { ["sha256"] = null };
        Action save = () => Act(target, drive, "save", again);
        save.Should().Throw<IOException>();
        drive.Media?.Changed.Should().BeTrue("a failed save leaves the recording changed");
        tape.ToArray().Should().Equal(recorded);

        RecoveryJournal journal = Open(id);
        journal.Commit(MediaActions.Journal(target.Devices, journal));
        Disks(id).Should().ContainSingle("the journal keeps the recording");
        Act(target, drive, "eject", Speaking())?.String("outcome").Should().Be("changed");
        drive.Media.Should().NotBeNull("an eject asks first");

        Directory.CreateDirectory(folder);
        Act(target, drive, "save", again)?.String("outcome").Should().Be("saved");
        File.ReadAllBytes(cas).Should().Equal(recorded);
        journal.Commit(MediaActions.Journal(target.Devices, journal), close: true);
        Disks(id).Should().BeEmpty();
    }

    /// <summary>
    ///  A file written at a TRS-80 recording's path after the recording started is a conflict, whether it replaces the
    ///  blank or appears where the blank was deleted; Overwrite with the file's revision saves over it.
    /// </summary>
    [TestMethod]
    public void AFileWrittenAtTheRecordingsPathIsAConflict()
    {
        string cas = Path.Join(s_root, $"conflict-{Guid.NewGuid():N}.cas");
        Trs80DebugTarget target = Trs80();
        Trs80CassetteDrive drive = target.Machine.Cassette;
        Act(target, drive, "record", At(cas));
        Type(target.Machine, "CSAVE \"C\"\r");
        RunUntil(target.Machine, () => target.Machine.Bus.Cassette.MotorOn, seconds: 5);
        Run(target.Machine, seconds: 0.5);

        File.WriteAllBytes(cas, [1, 2, 3]);
        JsonObject conflict = Act(target, drive, "save", Speaking()) ?? throw new InvalidOperationException("No answer.");
        conflict.String("outcome").Should().Be("conflict");
        File.ReadAllBytes(cas).Should().Equal(1, 2, 3);

        File.Delete(cas);
        File.WriteAllBytes(cas, [4, 5]);
        conflict = Act(target, drive, "save", Speaking()) ?? throw new InvalidOperationException("No answer.");
        conflict.String("outcome").Should().Be("conflict");
        string current = conflict["current"]?["sha256"]?.GetValue<string>() ?? throw new InvalidOperationException("No revision.");

        JsonObject overwrite = Speaking();
        overwrite["overwrite"] = new JsonObject { ["sha256"] = current };
        Act(target, drive, "save", overwrite)?.String("outcome").Should().Be("saved");
        byte[] saved = File.ReadAllBytes(cas);
        saved.Length.Should().BeGreaterThan(16, "the half second of leader recorded so far is saved");
        target.Machine.Cassette.Tape?.Bytes.Should().BeEmpty("saving does not stop the recorder");
    }

    /// <summary>
    ///  An Altair recording stopped and crashed with: the bytes the 88-ACR sent are a changed tape, kept at a stop and
    ///  after a crash, put back in the next launch's recorder to play, and saved to the recording's TAP file. A failed
    ///  write leaves it changed, and a file written at its path meanwhile is a conflict.
    /// </summary>
    [TestMethod]
    public void AnAltairRecordingIsAChangedTape()
    {
        string id = Id();
        string tap = Path.Join(s_root, $"altair-{Guid.NewGuid():N}.tap");
        AltairDebugTarget target = Altair();
        AltairCassette drive = target.Machine.Bus.Cassette ?? throw new InvalidOperationException("The 88-ACR is missing.");
        Act(target, drive, "record", At(tap));
        File.ReadAllBytes(tap).Should().BeEmpty();
        Send(target, "HI");
        drive.Media?.Changed.Should().BeTrue();
        drive.Activity.Should().Be(DeviceActivity.Writing, "a recorder records from the moment the tape goes in");

        // Stopped: the last checkpoint keeps it, and the next launch puts it back to play.
        RecoveryJournal journal = Open(id);
        journal.Commit(MediaActions.Journal(target.Devices, journal, whole: true), close: true);
        AltairDebugTarget next = Altair();
        AltairCassette back = next.Machine.Bus.Cassette ?? throw new InvalidOperationException("The 88-ACR is missing.");
        RecoveryJournal again = Open(id);
        MediaActions.Recover(next.Devices, again).Should().BeEmpty();
        back.Media?.Changed.Should().BeTrue();
        back.Transport.Mode.Should().Be(TapeMode.Playing);
        back.Tape?.ToArray().Should().Equal("HI"u8.ToArray());

        // A file written at its path meanwhile is a conflict; a read-only file is refused.
        File.WriteAllBytes(tap, [9]);
        Act(next, back, "save", Speaking())?.String("outcome").Should().Be("conflict");
        File.WriteAllBytes(tap, []);
        File.SetAttributes(tap, FileAttributes.ReadOnly);
        Act(next, back, "save", Speaking())?.String("outcome").Should().Be("readOnly");
        File.SetAttributes(tap, FileAttributes.Normal);
        back.Media?.Changed.Should().BeTrue();

        // Crashed: a checkpoint keeps it, and the launch after puts it back once more.
        again.Commit(MediaActions.Journal(next.Devices, again));
        Crash(again);
        AltairDebugTarget last = Altair();
        RecoveryJournal third = Open(id);
        MediaActions.Recover(last.Devices, third).Should().BeEmpty();
        AltairCassette kept = last.Machine.Bus.Cassette ?? throw new InvalidOperationException("The 88-ACR is missing.");
        kept.Tape?.ToArray().Should().Equal("HI"u8.ToArray());
        MediaSaved(last, kept).Should().Be("saved");
        File.ReadAllBytes(tap).Should().Equal("HI"u8.ToArray());
        third.Commit(MediaActions.Journal(last.Devices, third), close: true);
        Disks(id).Should().BeEmpty();
    }

    /// <summary>
    ///  An Apple-1 recording is kept as its half cycles, exactly, and saves as a WAV file with a note that it rounds
    ///  them, which leaves it saved, as the ACI reads it the same.
    /// </summary>
    [TestMethod]
    public void AnApple1RecordingIsKeptAsItsHalfCycles()
    {
        string id = Id();
        string wav = Path.Join(s_root, $"apple1-{Guid.NewGuid():N}.wav");
        Apple1DebugTarget target = Apple1DebugTarget.Launch([]);
        Apple1CassetteDrive drive = target.Machine.CassetteDrive ?? throw new InvalidOperationException("No cassette interface.");
        Act(target, drive, "record", At(wav));
        Apple1Tape.FromWave(File.ReadAllBytes(wav)).HalfCycles.Should().BeEmpty("the file is written blank");
        Apple1Tape tape = drive.Tape ?? throw new InvalidOperationException("The recorder is empty.");
        Apple1Tape.FromData([0x12, 0x34]).HalfCycles.ToList().ForEach(half => tape.Add(half));
        drive.Media?.Changed.Should().BeTrue();

        RecoveryJournal journal = Open(id);
        journal.Commit(MediaActions.Journal(target.Devices, journal, whole: true), close: true);
        Apple1DebugTarget next = Apple1DebugTarget.Launch([]);
        Apple1CassetteDrive back = next.Machine.CassetteDrive ?? throw new InvalidOperationException("No cassette interface.");
        RecoveryJournal again = Open(id);
        MediaActions.Recover(next.Devices, again).Should().BeEmpty();
        back.Tape?.HalfCycles.Should().Equal(tape.HalfCycles, "the journal keeps the half cycles themselves");

        JsonObject saved = Act(next, back, "save", Speaking()) ?? throw new InvalidOperationException("No answer.");
        saved.String("outcome").Should().Be("saved");
        saved["notes"]?.AsArray().Should().ContainSingle();
        saved["losses"].Should().BeNull();
        back.Media?.Changed.Should().BeFalse("a WAV file is read back the same");
        Apple1Tape.FromWave(File.ReadAllBytes(wav)).HalfCycles.Count.Should().BeInRange(tape.HalfCycles.Count - 2, tape.HalfCycles.Count + 1);
        again.Commit(MediaActions.Journal(next.Devices, again), close: true);
    }

    /// <summary>
    ///  A Model 100 recording is kept as its starting level and half cycles and comes back in the next launch; the
    ///  session's end writes the RAM image and not the recording.
    /// </summary>
    [TestMethod]
    public void AModel100RecordingIsKeptAndNotWrittenAtTheEnd()
    {
        string id = Id();
        string folder = Path.Join(s_root, $"model100-{Guid.NewGuid():N}");
        Directory.CreateDirectory(folder);
        string wav = Path.Join(folder, "rec.wav");
        Trs80Model100DebugTarget target = Model100(Path.Join(folder, "m100.ram"));
        Trs80Model100CassetteDrive drive = target.Machine.Bus.CassetteDrive;
        Act(target, drive, "record", At(wav));
        byte[] blank = File.ReadAllBytes(wav);
        Trs80Model100Cassette cassette = target.Machine.Bus.Cassette;
        bool level = false;
        for (int change = 0; change < 6; change++)
        {
            level = !level;
            for (int cycle = 0; cycle < 500; cycle++) { cassette.Tick(motor: true, output: level); }
        }

        cassette.Tick(motor: false, output: level);
        drive.Media?.Changed.Should().BeTrue();
        target.SaveRecordings();
        File.ReadAllBytes(wav).Should().Equal(blank, "the session's end writes the RAM image alone");
        File.Exists(Path.Join(folder, "m100.ram")).Should().BeTrue();

        Trs80Model100Tape tape = target.Machine.Bus.CassetteDrive.Tape ?? throw new InvalidOperationException("The recorder is empty.");
        RecoveryJournal journal = Open(id);
        journal.Commit(MediaActions.Journal(target.Devices, journal, whole: true), close: true);
        Trs80Model100DebugTarget next = Model100(Path.Join(folder, "m100.ram"));
        RecoveryJournal again = Open(id);
        MediaActions.Recover(next.Devices, again).Should().BeEmpty();
        Trs80Model100Tape back = next.Machine.Bus.CassetteDrive.Tape ?? throw new InvalidOperationException("The recorder is empty.");
        back.StartsHigh.Should().Be(tape.StartsHigh);
        back.HalfCycles.Should().Equal(tape.HalfCycles);
        Act(next, next.Machine.Bus.CassetteDrive, "save", Speaking())?.String("outcome").Should().Be("saved");
        Trs80Model100Tape.FromWave(File.ReadAllBytes(wav)).HalfCycles.Should().NotBeEmpty();
        again.Commit(MediaActions.Journal(next.Devices, again), close: true);
    }

    // A Model I with Level II from the SDK's sources, run to its READY prompt.
    private static Trs80DebugTarget Trs80()
    {
        Trs80DebugTarget target = Trs80DebugTarget.Launch(new JsonObject { ["expansionInterface"] = false });
        Run(target.Machine, seconds: 1);
        Type(target.Machine, "\r");
        Run(target.Machine, seconds: 3);
        return target;
    }

    private static AltairDebugTarget Altair() => AltairDebugTarget.Launch([]);

    // A Model 100 on a ROM of zeros, which the cassette needs nothing of.
    private static Trs80Model100DebugTarget Model100(string image)
    {
        string rom = Path.Join(s_root, $"rom-{Guid.NewGuid():N}.bin");
        File.WriteAllBytes(rom, new byte[32 * 1024]);
        JsonObject args = new() { ["rom"] = rom, ["ramImage"] = image, ["time"] = "2026-11-26T09:30:00" };
        return Trs80Model100DebugTarget.Launch(args);
    }

    // Sends bytes through the 88-ACR, a character time each.
    private static void Send(AltairDebugTarget target, string text)
    {
        AltairSio acr = target.Machine.Bus.Acr ?? throw new InvalidOperationException("The 88-ACR is missing.");
        foreach (char character in text)
        {
            acr.Write(1, (byte)character);
            target.Machine.Run((ulong)AltairTiming.CyclesPerCharacter(AltairBus.CassetteBaudRate) * 2);
        }
    }

    // Acts on a device as the debug session does: the host first, then the machine when the host leaves it to it.
    private static JsonObject? Act(IDebugTarget target, IDevice device, string action, JsonObject args)
    {
        JsonObject? answer = MediaActions.Device(device, action, args, (what, with) => target.DeviceAction(device, what, with));
        if (answer is null) { target.DeviceAction(device, action, args); }
        return answer;
    }

    private static string? MediaSaved(IDebugTarget target, IDevice device) => Act(target, device, "save", Speaking())?.String("outcome");

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

    private static string Id() => $"test-{Guid.NewGuid():N}";

    private static RecoveryJournal Open(string id) => RecoveryJournal.Open(id, []) ?? throw new InvalidOperationException("The journal is taken.");

    // Ends a session as a process that stops without closing its journal does.
    private static void Crash(RecoveryJournal journal) => journal.Release();

    private static JsonObject? Offered(string id) =>
        RecoveryJournal.Unclean().OfType<JsonObject>().FirstOrDefault(journal => journal.String("id") == id);

    private static JsonArray Disks(string id) =>
        JsonNode.Parse(File.ReadAllText(Path.Join(RecoveryJournal.Root, id, "journal.json")))?["disks"]?.AsArray() ?? [];

    // A request's path.
    private static JsonObject At(string path) => new() { ["path"] = path };

    // Arguments from a client that speaks media's answers.
    private static JsonObject Speaking() => new() { ["supportsRetrocoreMedia"] = 1 };
}
