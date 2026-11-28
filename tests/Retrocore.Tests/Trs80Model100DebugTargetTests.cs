// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using Retrocore.Basic;
using Retrocore.Debug;
using Retrocore.Machines.Devices;
using Retrocore.Machines.Trs80Model100;
using System.Text.Json.Nodes;

namespace Retrocore.Tests;

/// <summary>
///  The Model 100 under the debugger: finding its ROM, and its RAM kept between sessions in a RAM image, as its battery
///  keeps it.
/// </summary>
/// <remarks>
///  <para>
///   The tests that run the ROM launch with it, read as <see cref="Trs80Model100RomTests"/> does, and are
///   inconclusive without it, CSAVE and CLOAD among them; those that need nothing of it, the cassette's recordings fed
///   to it directly and the session's end, run on a ROM of zeros.
///  </para>
/// </remarks>
[TestClass]
public sealed class Trs80Model100DebugTargetTests
{
    /// <summary>
    ///  A launch with no ROM to be found says which ROM it needs, and where it looked.
    /// </summary>
    [TestMethod]
    public void LaunchNeedsTheRom()
    {
        string empty = Path.Join(Path.GetTempPath(), $"retrocore-model100-{Guid.NewGuid():N}");
        Action model100 = () => Trs80Model100DebugTarget.Launch(new JsonObject { ["romDirectory"] = empty });
        model100.Should().Throw<ArgumentException>().WithMessage("*Model 100's ROM is missing*m100rom.m12*");
        JsonObject args102 = new() { ["romDirectory"] = empty, ["model"] = "102" };
        Action tandy102 = () => Trs80Model100DebugTarget.Launch(args102);
        tandy102.Should().Throw<ArgumentException>().WithMessage("*Tandy 102's ROM is missing*m102rom.m12*");
        Action model = () => Trs80Model100DebugTarget.Launch(new JsonObject { ["model"] = "200" });
        model.Should().Throw<ArgumentException>().WithMessage("model must be 100 or 102.");
    }

    /// <summary>
    ///  The target takes the Model 100's key codes up to 140, BREAK, and no further.
    /// </summary>
    [TestMethod]
    public void KeysGoUpToBreak()
    {
        string folder = Folder();
        try
        {
            Trs80Model100DebugTarget target = Launch(Path.Join(folder, "m100.ram"));
            target.MaximumKey.Should().Be(140);
            target.Key(140).Should().BeTrue();
            target.Key(141).Should().BeFalse();
        }
        finally
        {
            Directory.Delete(folder, recursive: true);
        }
    }

    /// <summary>
    ///  The SDK's source maps the US Model 100's and Tandy 102's ROMs, so the debugger steps through them by name, and
    ///  maps no other dump.
    /// </summary>
    /// <param name="name">The ROM's file.</param>
    /// <param name="model">The launch's model.</param>
    [TestMethod]
    [DataRow("m100.bin", "100")]
    [DataRow("t102.bin", "102")]
    public void TheSdkSourceMapsTheRom(string name, string model)
    {
        string folder = Folder();
        try
        {
            byte[] rom = Trs80Model100RomTests.Rom(name);
            JsonObject options = new() { ["model"] = model };
            Trs80Model100DebugTarget target = Launch(Path.Join(folder, "m100.ram"), options, rom);
            DebugInfo debug = new();
            target.AddSdkModules(debug, directory: null);
            debug.Modules.Should().ContainSingle();
            ushort newstt = (ushort)debug.Resolve("NEWSTT");
            newstt.Should().Be(0x0804);
            DebugPosition? position = debug.Position(target, newstt);
            position.Should().NotBeNull();
            position?.Chain[0].Path.Should().EndWith("Interpreter.asm");
            debug.Resolve("MENU").Should().Be(0x5797, "Tandy's documented entry");

            // Another dump of the ROM, one byte changed, gets no source.
            byte[] other = (byte[])rom.Clone();
            other[0x7F00] ^= 0xFF;
            Trs80Model100DebugTarget patched = Launch(Path.Join(folder, "other.ram"), options, other);
            DebugInfo none = new();
            patched.AddSdkModules(none, directory: null);
            none.Modules.Should().BeEmpty();
        }
        finally
        {
            Directory.Delete(folder, recursive: true);
        }
    }

    /// <summary>
    ///  A RAM image that does not exist yet starts the machine cold and is written when the session ends; the next
    ///  session loads it, and the ROM carries on in BASIC where POWER OFF,RESUME left it, with its variables.
    ///  <c>coldStart</c> starts from empty RAM all the same.
    /// </summary>
    [TestMethod]
    public void RamImageKeepsTheSession()
    {
        string folder = Folder();
        try
        {
            string image = Path.Join(folder, "m100.ram");
            Trs80Model100DebugTarget first = Launch(image);
            first.RamImagePath.Should().Be(image);
            Run(first, 4);
            Type(first, "\ra=42\rpower off,resume\r");
            Run(first, 2);
            first.Machine.IsPoweredOff.Should().BeTrue();
            File.Exists(image).Should().BeFalse("nothing is written until the session ends");
            first.SaveRecordings();
            new FileInfo(image).Length.Should().Be(32 * 1024);
            Directory.GetFiles(folder).Should().ContainSingle("the save leaves no temporary file");

            Trs80Model100DebugTarget second = Launch(image);
            second.Machine.IsPoweredOff.Should().BeFalse();
            Run(second, 3);
            Type(second, "?a\r");
            Run(second, 2);
            second.Machine.ScreenText().Should().Contain(" 42", "BASIC's variables were in the image");

            Trs80Model100DebugTarget cold = Launch(image, new JsonObject { ["coldStart"] = true });
            Run(cold, 4);
            cold.Machine.ScreenText()[7].Should().Be("Select: _              29638 Bytes free");
            cold.Machine.ScreenText()[0].Should().StartWith("Jan 01,1900", "a cold start clears the date");
        }
        finally
        {
            Directory.Delete(folder, recursive: true);
        }
    }

    /// <summary>
    ///  An image of another RAM size is refused rather than loaded.
    /// </summary>
    [TestMethod]
    public void RamImageMustFitTheRam()
    {
        string folder = Folder();
        try
        {
            string image = Path.Join(folder, "m100.ram");
            File.WriteAllBytes(image, new byte[32 * 1024]);

            // The ROM is read first, so a missing one leaves the test inconclusive rather than failing the throw check.
            byte[] rom = Trs80Model100RomTests.Rom("m100.bin");
            Action launch = () => Launch(image, new JsonObject { ["ramKilobytes"] = 8 }, rom);
            launch.Should().Throw<ArgumentException>().WithMessage("*has 32768 bytes; a 8 KB machine's has 8192*");
        }
        finally
        {
            Directory.Delete(folder, recursive: true);
        }
    }

    /// <summary>
    ///  The launch's files go into RAM's directory, the menu is drawn again with them, the Hardware view lists them,
    ///  BASIC runs one, and the target's BASIC is the Model 100's; a file that is not a Model 100's is refused before any is
    ///  written.
    /// </summary>
    [TestMethod]
    public void LaunchedFilesGoOnTheMenu()
    {
        string folder = Folder();
        try
        {
            string basic = Path.Join(folder, "hello.model100.bas");
            File.WriteAllText(basic, "10 PRINT \"HI\";6*7\n");
            string notes = Path.Join(folder, "notes.txt");
            File.WriteAllText(notes, "first\nsecond\n");
            string code = Path.Join(folder, "mc.co");
            File.WriteAllBytes(code, [0x60, 0xEA, 0x01, 0x00, 0x60, 0xEA, 0xC9]);
            JsonArray files = [basic, notes, code];
            JsonObject options = new() { ["files"] = files };
            Trs80Model100DebugTarget target = Launch(Path.Join(folder, "m100.ram"), options);
            Run(target, 3);

            string menu = string.Join("\n", target.Machine.ScreenText());
            menu.Should().Contain("HELLO.BA").And.Contain("NOTES.DO").And.Contain("MC.CO");
            target.Hardware().Single(row => row.Id == "files").Value.Should().Be("HELLO.BA, NOTES.DO, MC.CO");

            Type(target, "BASIC\r");
            Run(target, 1);
            Type(target, "RUN \"HELLO\"\r");
            Run(target, 1);
            string.Join("\n", target.Machine.ScreenText()).Should().Contain("HI 42", "the program ran");
            target.Basic.Should().BeSameAs(BasicDialect.Model100);

            string text = Path.Join(folder, "TOOLONGNAME.txt");
            File.WriteAllText(text, "x");
            JsonArray bad = [notes, text];
            JsonObject badOptions = new() { ["files"] = bad };
            Action refused = () => Launch(Path.Join(folder, "other.ram"), badOptions);
            refused.Should().Throw<ArgumentException>().WithMessage("*TOOLONGNAME.DO is not a Model 100 file name*");
            JsonObject notList = new() { ["files"] = notes };
            Action single = () => Launch(Path.Join(folder, "other.ram"), notList);
            single.Should().Throw<ArgumentException>().WithMessage("files must be a list of paths.");
        }
        finally
        {
            Directory.Delete(folder, recursive: true);
        }
    }

    /// <summary>
    ///  A tape recorded through the cassette's record action takes the ROM's CSAVE, the machine runs fast while the
    ///  motor moves it, saving it writes its WAV file, and the launch's cassette option plays that file to CLOAD; a
    ///  record to a folder that does not exist is refused and leaves the deck as it was.
    /// </summary>
    [TestMethod]
    public void CassettesRecordAndPlay()
    {
        string folder = Folder();
        try
        {
            string wave = Path.Join(folder, "prog.wav");
            Trs80Model100DebugTarget saver = Launch(Path.Join(folder, "a.ram"));
            Run(saver, 3);
            Type(saver, "BASIC\r");
            Run(saver, 1);
            Type(saver, "10 PRINT \"CAS\";6*7\r");
            IDevice drive = saver.Devices.Single();
            JsonObject missing = new() { ["path"] = Path.Join(folder, "no", "x.wav") };
            Action nowhere = () => saver.DeviceAction(drive, "record", missing);
            nowhere.Should().Throw<ArgumentException>().WithMessage("*does not exist*");
            JsonObject recording = new() { ["path"] = wave };
            saver.DeviceAction(drive, "record", recording);
            saver.Hardware().Single(row => row.Id == "cassette").Value.Should().Be(wave);
            saver.Accelerated.Should().BeFalse("the motor is off");
            Type(saver, "CSAVE \"PROG\"\r");
            Run(saver, 1);
            saver.Accelerated.Should().BeTrue("CSAVE runs the motor");
            Run(saver, 14);
            (drive.Media?.Changed).Should().BeTrue("the recording is a changed tape");
            (MediaActions.Device(drive, "save", Speaking())?.String("outcome")).Should().Be("saved");
            saver.DeviceAction(drive, "eject", []);
            Trs80Model100Tape.FromWave(File.ReadAllBytes(wave)).HalfCycles.Should().NotBeEmpty();
            Directory.GetFiles(folder, "*.tmp").Should().BeEmpty();

            JsonObject options = new() { ["cassette"] = wave, ["sound"] = "off" };
            Trs80Model100DebugTarget loader = Launch(Path.Join(folder, "b.ram"), options);
            loader.Hardware().Single(row => row.Id == "sound").Value.Should().Be("off");
            loader.TakeAudio().Should().BeNull();
            Run(loader, 3);
            Type(loader, "BASIC\r");
            Run(loader, 1);
            Type(loader, "CLOAD \"PROG\"\r");
            Run(loader, 15);
            Type(loader, "RUN\r");
            Run(loader, 1);
            string.Join("\n", loader.Machine.ScreenText()).Should().Contain("CAS 42");
        }
        finally
        {
            Directory.Delete(folder, recursive: true);
        }
    }

    /// <summary>
    ///  A recording is a changed tape: its file is written blank as it starts, an unchanged one comes out without a
    ///  word, and a changed one is held back by an eject until it is saved or let go; a tape that is not a WAV file, or
    ///  is missing, is refused with the recording left in; and once saved, the recording plays from its own file. The
    ///  cassette needs nothing of the ROM, so this runs on a ROM of zeros.
    /// </summary>
    [TestMethod]
    public void RecordingsAreChangedTapes()
    {
        string folder = Folder();
        try
        {
            string wave = Path.Join(folder, "rec.wav");
            File.WriteAllText(wave, "was here");
            Trs80Model100DebugTarget target = Launch(Path.Join(folder, "m100.ram"), rom: new byte[32 * 1024]);
            IDevice drive = target.Devices.Single();
            JsonObject recording = new() { ["path"] = wave };
            target.DeviceAction(drive, "record", recording);
            Trs80Model100Tape.FromWave(File.ReadAllBytes(wave)).HalfCycles.Should().BeEmpty("the file is written blank at once");
            (drive.Media?.Changed).Should().BeFalse();
            MediaActions.Device(drive, "eject", Speaking()).Should().BeNull("an unchanged recording comes out without a word");
            target.DeviceAction(drive, "eject", []);
            drive.Media.Should().BeNull();

            // A recording with changes on it: SOD toggled while the motor runs.
            target.DeviceAction(drive, "record", recording);
            Record(target, changes: 4);
            (drive.Media?.Changed).Should().BeTrue();
            string bad = Path.Join(folder, "bad.wav");
            File.WriteAllText(bad, "not a wave");
            JsonObject insertBad = new() { ["path"] = bad };
            Action insert = () => target.DeviceAction(drive, "insert", insertBad);
            insert.Should().Throw<InvalidDataException>();
            (drive.Media?.Label).Should().Be(wave, "the recording is still in");
            JsonObject missingTape = new() { ["path"] = Path.Join(folder, "missing.wav") };
            Action missing = () => target.DeviceAction(drive, "insert", missingTape);
            missing.Should().Throw<ArgumentException>().WithMessage("*does not exist*");
            (drive.Media?.Label).Should().Be(wave, "the recording is still in");

            // An eject asks about it, and an older client is told to save it first.
            (MediaActions.Device(drive, "eject", Speaking())?.String("outcome")).Should().Be("changed");
            Action older = () => MediaActions.Device(drive, "eject", []);
            older.Should().Throw<InvalidOperationException>().WithMessage("*not saved*");
            drive.Media.Should().NotBeNull();

            (MediaActions.Device(drive, "save", Speaking())?.String("outcome")).Should().Be("saved");
            (drive.Media?.Changed).Should().BeFalse();
            Trs80Model100Tape.FromWave(File.ReadAllBytes(wave)).HalfCycles.Should().NotBeEmpty();
            target.DeviceAction(drive, "insert", recording);
            (drive.Media?.WriteProtected).Should().BeTrue("the tape now plays");
            Directory.GetFiles(folder, "*.tmp").Should().BeEmpty();
        }
        finally
        {
            Directory.Delete(folder, recursive: true);
        }
    }

    /// <summary>
    ///  The session's end writes the RAM image and not the recording, which is a changed tape the recovery journal
    ///  keeps; a RAM image that cannot be written fails the save, with the recording still in. It runs on a ROM of
    ///  zeros.
    /// </summary>
    [TestMethod]
    public void SessionsSaveTheRamAndNotTheRecording()
    {
        string folder = Folder();
        try
        {
            string image = Path.Join(folder, "m100.ram");
            string wave = Path.Join(folder, "rec.wav");
            Trs80Model100DebugTarget target = Launch(image, rom: new byte[32 * 1024]);
            IDevice drive = target.Devices.Single();
            JsonObject recording = new() { ["path"] = wave };
            target.DeviceAction(drive, "record", recording);
            byte[] blank = File.ReadAllBytes(wave);
            Record(target, changes: 4);
            target.SaveRecordings();
            File.ReadAllBytes(wave).Should().Equal(blank);
            File.Exists(image).Should().BeTrue();
            (drive.Media?.Changed).Should().BeTrue("the recording stays in, changed");

            File.Delete(image);
            Directory.CreateDirectory(image);
            Action save = target.SaveRecordings;
            Exception thrown = save.Should().Throw<Exception>().Which;
            (thrown is IOException or UnauthorizedAccessException).Should().BeTrue(thrown.ToString());
            (drive.Media?.Changed).Should().BeTrue();
            Directory.Delete(image);
        }
        finally
        {
            Directory.Delete(folder, recursive: true);
        }
    }

    // Runs the cassette's motor and toggles SOD, as CSAVE does, on the cassette alone.
    private static void Record(Trs80Model100DebugTarget target, int changes)
    {
        Trs80Model100Cassette cassette = target.Machine.Bus.Cassette;
        bool level = false;
        for (int change = 0; change < changes; change++)
        {
            level = !level;
            for (int cycle = 0; cycle < 500; cycle++) { cassette.Tick(motor: true, output: level); }
        }

        cassette.Tick(motor: false, output: level);
    }

    /// <summary>
    ///  A save that cannot be written throws, leaves what was at the image's path as it was and no temporary file,
    ///  and can be tried again once the path can be written.
    /// </summary>
    [TestMethod]
    public void FailedSaveLeavesTheImage()
    {
        string folder = Folder();
        try
        {
            // The image's path is a folder, so the save cannot replace it.
            string image = Path.Join(folder, "m100.ram");
            Trs80Model100DebugTarget target = Launch(image);
            Directory.CreateDirectory(image);
            File.WriteAllBytes(Path.Join(image, "keep"), [1, 2, 3]);
            Action save = target.SaveRecordings;
            Exception thrown = save.Should().Throw<Exception>().Which;
            (thrown is IOException or UnauthorizedAccessException).Should().BeTrue(thrown.ToString());
            File.ReadAllBytes(Path.Join(image, "keep")).Should().Equal(1, 2, 3);
            Directory.GetFiles(folder).Should().BeEmpty("the temporary file is removed");

            Directory.Delete(image, recursive: true);
            target.SaveRecordings();
            new FileInfo(image).Length.Should().Be(32 * 1024);

            // A folder that is gone fails the same way.
            Trs80Model100DebugTarget lost = Launch(Path.Join(folder, "gone", "m100.ram"));
            Action lostSave = lost.SaveRecordings;
            lostSave.Should().Throw<DirectoryNotFoundException>();
        }
        finally
        {
            Directory.Delete(folder, recursive: true);
        }
    }

    // Arguments from a client that speaks media's answers.
    private static JsonObject Speaking() => new() { ["supportsRetrocoreMedia"] = 1 };

    private static string Folder()
    {
        string folder = Path.Join(Path.GetTempPath(), $"retrocore-model100-{Guid.NewGuid():N}");
        Directory.CreateDirectory(folder);
        return folder;
    }

    private static Trs80Model100DebugTarget Launch(string image, JsonObject? more = null, byte[]? rom = null)
    {
        rom ??= Trs80Model100RomTests.Rom("m100.bin");
        string romFile = Path.Join(Path.GetTempPath(), $"retrocore-m100-{Guid.NewGuid():N}.bin");
        File.WriteAllBytes(romFile, rom);
        try
        {
            JsonObject args = new()
            {
                ["rom"] = romFile,
                ["ramImage"] = image,
                ["time"] = "2026-11-26T09:30:00"
            };

            foreach ((string name, JsonNode? value) in more ?? []) { args[name] = value?.DeepClone(); }
            return Trs80Model100DebugTarget.Launch(args);
        }
        finally
        {
            File.Delete(romFile);
        }
    }

    private static void Run(Trs80Model100DebugTarget target, double seconds) =>
        target.Machine.RunSeconds(seconds);

    private static void Type(Trs80Model100DebugTarget target, string text)
    {
        foreach (char character in text) { target.Key(character).Should().BeTrue(); }
        while (target.Machine.Keyboard.IsTyping) { target.Machine.Run(10_000); }
    }
}
