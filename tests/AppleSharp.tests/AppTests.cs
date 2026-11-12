// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using Retrocore.Machines.Apple2;
using Retrocore.Media;
using System.Text.Json;

namespace AppleSharp.Tests;

/// <summary>
///  Tests first-host configuration, persistent raw storage and deterministic wall-clock budgets.
/// </summary>
[TestClass]
public class AppTests
{
    private readonly List<string> _files = [];

    /// <summary>
    ///  Checks front-panel commands remain compact when stored with button and menu state.
    /// </summary>
    [TestMethod]
    public void CommandStorageRemainsByteBacked() =>
        Enum.GetUnderlyingType(typeof(Command)).Should().Be(typeof(byte));

    /// <summary>
    ///  Deletes only the named temporary files created by this test instance.
    /// </summary>
    [TestCleanup]
    public void Cleanup()
    {
        foreach (string path in _files) { if (File.Exists(path)) { File.Delete(path); } }
    }

    /// <summary>
    ///  Checks that no CLI argument implicitly enables writes or replaces saved model selection.
    /// </summary>
    [TestMethod]
    public void EmptyCommandLineHasNoPermissionOrModelOverrides()
    {
        AppOptions options = AppOptions.Parse([]);
        options.Model.Should().BeNull();
        options.Writable.Should().BeNull();
        options.DiskPath.Should().BeNull();
        AppSettings settings = new();
        settings.Writable.Should().BeFalse();
        settings.Model.Should().Be(Apple2Model.IIeEnhanced);
    }

    /// <summary>
    ///  Checks explicit model, settings, disk and write options, including a read-only override.
    /// </summary>
    [TestMethod]
    public void ExplicitOverridesAndPathsAreParsed()
    {
        string disk = Temporary(".po");
        string settings = Temporary(".json");
        AppOptions options = AppOptions.Parse(["--model", "original", "--disk", disk, "--settings", settings, "--writable", "--read-only"]);
        options.Model.Should().Be(Apple2Model.IIe);
        options.DiskPath.Should().Be(disk);
        options.SettingsPath.Should().Be(settings);
        options.Writable.Should().BeFalse();
    }

    /// <summary>
    ///  Checks generated ROM-folder options accept quoted full paths with spaces, as the platform writes them.
    /// </summary>
    /// <param name="option">A generated option or its documented alias.</param>
    [TestMethod]
    [DataRow("--rom-directory")]
    [DataRow("--rom-folder")]
    [DataRow("-r")]
    public void RomFolderAliasesAreGenerated(string option)
    {
        string folder = OperatingSystem.IsWindows() ? @"N:\external ROMs\APPLE IIe" : "/external ROMs/APPLE IIe";
        AppOptions options = AppOptions.Parse([option, folder]);
        options.RomDirectory.Should().Be(folder);
        options.Help.Should().BeFalse();
    }

    /// <summary>
    ///  Checks the generated framework help describes the actual root command and ROM aliases.
    /// </summary>
    [TestMethod]
    public void FrameworkHelpDescribesRomFolderOptions()
    {
        AppOptions options = AppOptions.Parse(["--help"]);
        options.Help.Should().BeTrue();
        options.HelpText.Should().Contain("--rom-directory").And.Contain("--rom-folder").And.Contain("-r");
    }

    /// <summary>
    ///  Checks generated permission flags retain the previous last-switch-wins behavior.
    /// </summary>
    [TestMethod]
    public void PermissionFlagOrderIsPreserved()
    {
        AppOptions.Parse(["--read-only", "--writable"]).Writable.Should().BeTrue();
        AppOptions.Parse(["--writable", "--read-only"]).Writable.Should().BeFalse();
        AppOptions.Parse(["--sound", "--mute"]).Muted.Should().BeTrue();
        AppOptions.Parse(["--mute", "--sound"]).Muted.Should().BeFalse();
    }

    /// <summary>
    ///  Checks unknown switches and missing values fail explicitly.
    /// </summary>
    /// <param name="argument">The invalid argument.</param>
    [TestMethod]
    [DataRow("--disk")]
    [DataRow("--settings")]
    [DataRow("--rom-directory")]
    [DataRow("--unknown")]
    public void InvalidArgumentsFail(string argument)
    {
        Action action = () => AppOptions.Parse([argument]);
        action.Should().Throw<ArgumentException>();
    }

    /// <summary>
    ///  Checks unsupported model names are rejected.
    /// </summary>
    [TestMethod]
    public void InvalidModelFails()
    {
        Action action = () => AppOptions.Parse(["--model", "iigs"]);
        action.Should().Throw<ArgumentException>();
    }

    /// <summary>
    ///  Checks source-generated JSON persists explicit choices and a missing file is first-launch setup.
    /// </summary>
    [TestMethod]
    public void SettingsRoundTripUsesGeneratedMetadata()
    {
        string path = Temporary(".json");
        AppSettings.Load(path).Should().Be(new AppSettings());
        AppSettings expected = new()
        {
            RomDirectory = @"N:\external roms",
            Model = Apple2Model.IIe,
            DiskPath = @"N:\disk.po",
            Writable = true,
            Fullscreen = true
        };

        expected.Save(path);
        AppSettings.Load(path).Should().Be(expected);
        (expected with { Writable = false }).Save(path);
        AppSettings.Load(path).Writable.Should().BeFalse();
    }

    /// <summary>
    ///  Checks malformed or unsupported saved configuration is not silently replaced with defaults.
    /// </summary>
    /// <param name="json">The invalid configuration.</param>
    [TestMethod]
    [DataRow("null")]
    [DataRow("{\"model\":7}")]
    [DataRow("{\"romDirectory\":\"\"}")]
    public void InvalidSettingsFail(string json)
    {
        string path = Temporary(".json");
        File.WriteAllText(path, json);
        Action action = () => AppSettings.Load(path);
        action.Should().Throw<InvalidDataException>();
    }

    /// <summary>
    ///  Checks corrupt JSON reports a parser error.
    /// </summary>
    [TestMethod]
    public void CorruptSettingsFail()
    {
        string path = Temporary(".json");
        File.WriteAllText(path, "{");
        Action action = () => AppSettings.Load(path);
        action.Should().Throw<JsonException>();
    }

    /// <summary>
    ///  Checks writable blocks survive disposal, remounting and a double dispose.
    /// </summary>
    [TestMethod]
    public void WritableBlocksPersistImmediately()
    {
        string path = Temporary(".po");
        File.WriteAllBytes(path, new byte[1024]);
        byte[] block = Enumerable.Range(0, 512).Select(value => (byte)value).ToArray();
        FileBlockDevice disk = new(path, writable: true);
        disk.WriteBlock(block: 1, block);
        disk.Dispose();
        disk.Dispose();
        File.ReadAllBytes(path)[512..].Should().Equal(block);
        using FileBlockDevice reopened = new(path, writable: false);
        byte[] actual = new byte[512];
        reopened.ReadBlock(block: 1, actual);
        actual.Should().Equal(block);
    }

    /// <summary>
    ///  Checks read-only mounts reject writes without changing the image.
    /// </summary>
    [TestMethod]
    public void ReadOnlyMountCannotModifyTheImage()
    {
        string path = Temporary(".po");
        File.WriteAllBytes(path, new byte[1024]);
        using (FileBlockDevice disk = new(path, writable: false))
        {
            Action action = () => disk.WriteBlock(block: 0, new byte[512]);
            action.Should().Throw<InvalidOperationException>();
            disk.BlockCount.Should().Be(2);
            disk.IsReadOnly.Should().BeTrue();
        }

        File.ReadAllBytes(path).Should().OnlyContain(value => value == 0);
    }

    /// <summary>
    ///  Checks whole blocks, two boot blocks and the firmware's 16-bit capacity limit.
    /// </summary>
    /// <param name="length">The invalid image length.</param>
    [TestMethod]
    [DataRow(0L)]
    [DataRow(512L)]
    [DataRow(1025L)]
    [DataRow(65536L * 512)]
    public void InvalidRawImagesFail(long length)
    {
        string path = Temporary(".po");
        using (FileStream stream = File.Create(path)) { stream.SetLength(length); }
        Action action = () => new FileBlockDevice(path, writable: false);
        action.Should().Throw<InvalidDataException>();
    }

    /// <summary>
    ///  Checks transfer bounds and block-buffer sizes.
    /// </summary>
    [TestMethod]
    public void InvalidBlockRequestsFail()
    {
        string path = Temporary(".po");
        File.WriteAllBytes(path, new byte[1024]);
        using FileBlockDevice disk = new(path, writable: true);
        Action shortBuffer = () => disk.ReadBlock(block: 0, new byte[511]);
        Action invalidBlock = () => disk.ReadBlock(block: 2, new byte[512]);
        shortBuffer.Should().Throw<ArgumentException>();
        invalidBlock.Should().Throw<ArgumentOutOfRangeException>();
    }

    /// <summary>
    ///  Checks fractional wall-clock increments produce exactly one second of CPU clocks.
    /// </summary>
    [TestMethod]
    public void ClockPreservesFractionalCycles()
    {
        FrameClock clock = new(frequency: 1000, timestamp: 0);
        ulong total = 0;
        for (int tick = 1; tick <= 1000; tick++) { total += clock.Take(tick, running: true); }
        total.Should().Be(FrameClock.CyclesPerSecond);
    }

    /// <summary>
    ///  Checks bounded catch-up retains all running time rather than dropping frames.
    /// </summary>
    [TestMethod]
    public void ClockRetainsBacklogButDiscardsPausedTime()
    {
        FrameClock clock = new(frequency: 1000, timestamp: 0);
        ulong total = clock.Take(timestamp: 1000, running: true);
        total.Should().Be((ulong)Apple2Video.CyclesPerFrame * 4);
        for (int pass = 0; pass < 20; pass++) { total += clock.Take(timestamp: 1000, running: true); }
        total.Should().Be(FrameClock.CyclesPerSecond);
        clock.Take(timestamp: 2000, running: false).Should().Be(0);
        clock.Take(timestamp: 2001, running: true).Should().Be(1020);
        Action reversed = () => clock.Take(timestamp: 1999, running: true);
        reversed.Should().Throw<ArgumentOutOfRangeException>();
    }

    /// <summary>
    ///  Checks letterboxing uses the Apple II display aspect rather than square 14 MHz dots.
    /// </summary>
    /// <param name="width">The window width.</param>
    /// <param name="height">The window height.</param>
    [TestMethod]
    [DataRow(600, 400)]
    [DataRow(960, 800)]
    [DataRow(1920, 1080)]
    public void ScreenKeepsDisplayAspect(int width, int height)
    {
        var screen = WindowLayout.Screen(width, height);
        (screen.W / screen.H).Should().BeApproximately(280f / 192, precision: 0.0001f);
        screen.X.Should().BeGreaterThanOrEqualTo(0);
        screen.Y.Should().BeGreaterThanOrEqualTo(72);
        (screen.Y + screen.H).Should().BeLessThanOrEqualTo(height - 48);
    }

    /// <summary>
    ///  Checks native floppy firmware, layout and mute overrides are distinct from slot-seven media.
    /// </summary>
    [TestMethod]
    public void M3NativeOptionsAreExplicit()
    {
        string first = Temporary(".woz");
        string second = Temporary(".dsk");
        string boot = Temporary(".bin");
        string sequencer = Temporary(".bin");
        AppOptions options = AppOptions.Parse(
            [
            "--floppy", first, "--floppy2", second, "--disk-ii-rom", boot,
            "--sequencer-rom", sequencer, "--p6-layout", "beneath-prodos", "--mute"
        ]);

        options.Floppy1Path.Should().Be(first);
        options.Floppy2Path.Should().Be(second);
        options.DiskBootRom.Should().Be(boot);
        options.DiskSequencerRom.Should().Be(sequencer);
        options.SequencerLayout.Should().Be(P6PromLayout.BeneathProDos);
        options.Muted.Should().BeTrue();
        options.DiskPath.Should().BeNull();
    }

    /// <summary>
    ///  Checks native WOZ changes survive explicit motor-off/eject persistence.
    /// </summary>
    [TestMethod]
    public void NativeFloppyChangesPersistWithoutLosingAliases()
    {
        string path = Temporary(".woz");
        WozDisk original = WozDisk.CreateBlank();
        original.SetTrack(quarterTrack: 0, [0xA5], bitCount: 8);
        original.MapTrack(quarterTrack: 1, sourceQuarterTrack: 0);
        File.WriteAllBytes(path, original.Export());
        using (FloppyMount mount = new(path, writable: true))
        {
            mount.Disk.WriteBit(quarterTrack: 1, position: 0, transition: false);
            mount.Save();
            mount.Disk.IsDirty.Should().BeFalse();
        }

        WozDisk saved = WozDisk.Load(File.ReadAllBytes(path));
        saved.Track(0)?.ReadBit(0).Should().BeFalse();
        saved.Track(1).Should().BeSameAs(saved.Track(0));
    }

    /// <summary>
    ///  Checks persistence does not overwrite another writer's changes.
    /// </summary>
    [TestMethod]
    public void NativeFloppySaveRejectsExternalChanges()
    {
        string path = Temporary(".woz");
        WozDisk original = WozDisk.CreateBlank();
        original.SetTrack(quarterTrack: 0, [0xA5], bitCount: 8);
        File.WriteAllBytes(path, original.Export());
        FloppyMount mount = new(path, writable: true);
        mount.Disk.WriteBit(quarterTrack: 0, position: 0, transition: false);
        File.WriteAllBytes(path, [1,2,3]);
        Action save = mount.Save;
        save.Should().Throw<IOException>();
        mount.Disk.IsDirty.Should().BeTrue();
        // The failed write remains unacknowledged; avoid a second intentional save during test cleanup.
        mount.Disk.MarkSaved();
        mount.Dispose();
        File.ReadAllBytes(path).Should().Equal(1,2,3);
    }

    private string Temporary(string extension)
    {
        string path = Path.GetFullPath(Path.Join(Path.GetTempPath(), "AppleSharp-tests-" + Guid.NewGuid().ToString("N") + extension));
        _files.Add(path);
        return path;
    }
}
