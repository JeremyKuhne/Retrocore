// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using Retrocore.Debug;
using System.Text.Json.Nodes;

namespace Retrocore.Tests;

/// <summary>
///  The Model 100 under the debugger: finding its ROM, and its RAM kept between sessions in a RAM image, as its battery
///  keeps it.
/// </summary>
/// <remarks>
///  <para>
///   The tests that boot read the ROM as <see cref="Trs80Model100RomTests"/> does, and are inconclusive without it.
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
            Action launch = () => Launch(image, new JsonObject { ["ramKilobytes"] = 8 });
            launch.Should().Throw<ArgumentException>().WithMessage("*has 32768 bytes; a 8 KB machine's has 8192*");
        }
        finally
        {
            Directory.Delete(folder, recursive: true);
        }
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

    private static string Folder()
    {
        string folder = Path.Join(Path.GetTempPath(), $"retrocore-model100-{Guid.NewGuid():N}");
        Directory.CreateDirectory(folder);
        return folder;
    }

    private static Trs80Model100DebugTarget Launch(string image, JsonObject? more = null)
    {
        byte[] rom = Trs80Model100RomTests.Rom("m100.bin");
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
