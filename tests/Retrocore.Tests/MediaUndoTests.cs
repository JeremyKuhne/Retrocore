// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using Retrocore.Debug;
using Retrocore.Machines.Apple2;
using Retrocore.Machines.Devices;
using Retrocore.Media;
using System.Text.Json.Nodes;

namespace Retrocore.Tests;

/// <summary>
///  What the host keeps of a disk that leaves its drive, as the media persistence plan's third phase has it: a revert
///  reads the image again and a discard lets a changed disk go, each keeping the disk for Undo; a disk the machine
///  ejects with changes is kept until it is saved, put back or let go; and a drive says what its disk changed.
/// </summary>
[TestClass]
public sealed class MediaUndoTests
{
    private static readonly string s_inputs = Path.Join(AppContext.BaseDirectory, "Inputs");
    private static readonly Lazy<Apple2Roms> s_roms = new(() => SdkModules.BuildRoms(Apple2Model.IIeEnhanced, s_inputs));
    private static string s_root = "";

    /// <summary>
    ///  Makes the tests' folder.
    /// </summary>
    /// <param name="context">The test context.</param>
    [ClassInitialize]
    public static void Initialize(TestContext context)
    {
        s_root = Path.Join(Path.GetTempPath(), $"retrocore-undo-{Environment.ProcessId}");
        Directory.CreateDirectory(s_root);
    }

    /// <summary>
    ///  Removes the tests' folder.
    /// </summary>
    [ClassCleanup]
    public static void Cleanup() => Directory.Delete(s_root, recursive: true);

    /// <summary>
    ///  Revert reads the image as it is now in place of the changed disk, which Undo puts back, the reverted disk going.
    /// </summary>
    [TestMethod]
    public void RevertReadsTheImageAndUndoPutsTheDiskBack()
    {
        (Apple2Disk35Drive drive, string image) = Drive("revert.po");
        IMedium changed = drive.Medium ?? throw new InvalidOperationException("The drive is empty.");
        Write(drive, block: 7, 0x42);
        drive.Media?.Changed.Should().BeTrue();

        JsonObject answer = MediaActions.Device(drive, "revert", Speaking(), Machine(drive)) ?? throw new InvalidOperationException("No answer.");
        answer.String("outcome").Should().Be("reverted");
        drive.Media?.Changed.Should().BeFalse("the disk is the image again");
        drive.Medium.Should().NotBeSameAs(changed);
        string undo = answer.String("undo") ?? throw new InvalidOperationException("Nothing to undo.");
        DeviceJson.Write(drive)["undo"]?["id"]?.GetValue<string>().Should().Be(undo);
        DeviceJson.Write(drive)["undo"]?["why"]?.GetValue<string>().Should().Be("reverted");

        JsonObject args = Speaking();
        args["medium"] = undo;
        MediaActions.Device(drive, "undo", args)?.String("outcome").Should().Be("undone");
        drive.Medium.Should().BeSameAs(changed, "Undo puts back the disk the revert dropped");
        drive.Media?.Changed.Should().BeTrue();
        drive.Media?.Label.Should().Be(image);
        MediaActions.Undoable(drive).Should().BeNull();
        DeviceJson.Write(drive)["undo"].Should().BeNull();
    }

    /// <summary>
    ///  A changed disk let go of by an eject is kept for Undo, which puts it back in the empty drive.
    /// </summary>
    [TestMethod]
    public void DiscardKeepsTheDiskForUndo()
    {
        (Apple2Disk35Drive drive, _) = Drive("discard.po");
        IMedium changed = drive.Medium ?? throw new InvalidOperationException("The drive is empty.");
        Write(drive, block: 3, 0x11);

        JsonObject discard = Speaking();
        JsonObject mount = new() { ["device"] = drive.Id, ["generation"] = drive.MountGeneration };
        discard["discards"] = new JsonArray(mount);
        MediaActions.Device(drive, "eject", discard).Should().BeNull("the machine ejects the disk let go of");
        drive.Eject();
        KeptDisk kept = MediaActions.Undoable(drive) ?? throw new InvalidOperationException("Nothing kept.");
        kept.Why.Should().Be("discarded");

        JsonObject args = Speaking();
        args["medium"] = kept.Id;
        MediaActions.Device(drive, "undo", args)?.String("outcome").Should().Be("undone");
        drive.Medium.Should().BeSameAs(changed);
        drive.Media?.Changed.Should().BeTrue();

        // An old Undo puts back nothing.
        Action again = () => MediaActions.Device(drive, "undo", args);
        again.Should().Throw<InvalidOperationException>();
    }

    /// <summary>
    ///  Undo over a changed disk asks first, as an eject does.
    /// </summary>
    [TestMethod]
    public void UndoOverAChangedDiskAsks()
    {
        (Apple2Disk35Drive drive, _) = Drive("over.po");
        Write(drive, block: 1, 0x22);
        string undo = MediaActions.Device(drive, "revert", Speaking(), Machine(drive))?.String("undo") ?? "";
        Write(drive, block: 2, 0x33);

        JsonObject args = Speaking();
        args["medium"] = undo;
        MediaActions.Device(drive, "undo", args)?.String("outcome").Should().Be("changed");
    }

    /// <summary>
    ///  A changed disk the machine ejects is kept under its drive until it is saved, put back or let go; an unchanged
    ///  one is its image and goes.
    /// </summary>
    [TestMethod]
    public void MachineEjectedDisksAreKept()
    {
        (Apple2Disk35Drive drive, string image) = Drive("ejected.po");
        drive.EjectByProgram();
        MediaActions.Ejected(drive).Should().BeEmpty("an unchanged disk is its image");

        DeviceAction(drive, image);
        IMedium first = drive.Medium ?? throw new InvalidOperationException("The drive is empty.");
        Write(drive, block: 9, 0x44);
        drive.EjectByProgram();
        KeptDisk kept = MediaActions.Ejected(drive).Single();
        kept.Medium.Should().BeSameAs(first);
        kept.Label.Should().Be(image);
        JsonObject listed = DeviceJson.Write(drive);
        listed["ejected"]?[0]?["changed"]?.GetValue<bool>().Should().BeTrue();
        listed["ejected"]?[0]?["why"]?.GetValue<string>().Should().Be("ejected");

        // Saved where it came from, it is the image and goes from the list.
        JsonObject save = Speaking();
        save["ejected"] = kept.Id;
        MediaActions.Device(drive, "save", save)?.String("outcome").Should().Be("saved");
        File.ReadAllBytes(image).AsSpan(9 * 512, 512).ToArray().Should().AllBeEquivalentTo((byte)0x44);
        MediaActions.Ejected(drive).Should().BeEmpty();

        // Another, put back in the drive.
        DeviceAction(drive, image);
        Write(drive, block: 10, 0x55);
        IMedium second = drive.Medium ?? throw new InvalidOperationException("The drive is empty.");
        drive.EjectByProgram();
        JsonObject again = Speaking();
        again["ejected"] = MediaActions.Ejected(drive).Single().Id;
        MediaActions.Device(drive, "insertAgain", again)?.String("outcome").Should().Be("inserted");
        drive.Medium.Should().BeSameAs(second);
        MediaActions.Ejected(drive).Should().BeEmpty();

        // And one let go, which Undo puts back among the ejected.
        drive.EjectByProgram();
        JsonObject discard = Speaking();
        discard["ejected"] = MediaActions.Ejected(drive).Single().Id;
        string undo = MediaActions.Device(drive, "discard", discard)?.String("undo") ?? "";
        MediaActions.Ejected(drive).Should().BeEmpty();
        JsonObject args = Speaking();
        args["medium"] = undo;
        MediaActions.Device(drive, "undo", args)?.String("outcome").Should().Be("undone");
        MediaActions.Ejected(drive).Single().Medium.Should().BeSameAs(second);
    }

    /// <summary>
    ///  A drive says how its disk differs from its image, by the image's own unit: blocks of a block image, sectors on
    ///  their tracks for a sector image.
    /// </summary>
    [TestMethod]
    public void DifferencesAreByTheImagesUnit()
    {
        (Apple2Disk35Drive drive, _) = Drive("differences.po");
        Differences(drive)?["count"]?.GetValue<int>().Should().Be(0);
        Write(drive, block: 7, 0x42);
        Write(drive, block: 8, 0x42);
        Write(drive, block: 200, 0x42);
        JsonObject differences = Differences(drive) ?? throw new InvalidOperationException("No differences.");
        differences.String("unit").Should().Be("block");
        differences["count"]?.GetValue<int>().Should().Be(3);
        differences.String("summary").Should().Be("blocks 7-8, 200");

        // A Disk II .dsk: 256-byte sectors, 16 to a track.
        string dsk = Path.Join(s_root, $"sectors-{Guid.NewGuid():N}.dsk");
        byte[] bytes = new byte[35 * 4096];
        File.WriteAllBytes(dsk, bytes);
        DiskIIController controller = new();
        controller.SetFirmware(new DiskIIFirmware(new byte[256], new byte[256]));
        Apple2FloppyDrive floppy = new(controller, drive: 1, "disk1", "Drive 1", "drive", "controller");
        LoadedDisk loaded = DiskIIImage.Load(bytes, ".dsk");
        MediaActions.Register(loaded.Disk, dsk, loaded.Codec, bytes);
        floppy.Insert(loaded.Disk, dsk, "DSK");
        bytes[((17 * 16) + 3) * 256] = 1;
        bytes[(18 * 16) * 256] = 1;
        File.WriteAllBytes(dsk, bytes);
        JsonObject sectors = Differences(floppy) ?? throw new InvalidOperationException("No differences.");
        sectors.String("unit").Should().Be("sector");
        sectors["count"]?.GetValue<int>().Should().Be(2);
        sectors.String("summary").Should().Be("tracks 17-18");
    }

    // A 3.5 drive on a IIe with a block image in it, inserted as the debug host inserts one.
    private static (Apple2Disk35Drive Drive, string Image) Drive(string name)
    {
        byte[] bytes = new byte[1600 * 512];
        new Random(name.Length).NextBytes(bytes);
        string image = Path.Join(s_root, $"{Path.GetFileNameWithoutExtension(name)}-{Guid.NewGuid():N}{Path.GetExtension(name)}");
        File.WriteAllBytes(image, bytes);
        Apple2Machine machine = new(Apple2Model.IIeEnhanced, s_roms.Value);
        machine.Bus.InstallDisk35(5);
        Apple2Disk35Drive drive = machine.Bus.Disk35.Drives[0];
        DeviceAction(drive, image);
        return (drive, image);
    }

    // Inserts an image as the debug host does.
    private static void DeviceAction(Apple2Disk35Drive drive, string path) => Apple2Loader.Insert(drive, path);

    // The machine's own action on the drive, as the debug host passes it: an insert reads the image.
    private static Action<string, JsonObject> Machine(Apple2Disk35Drive drive) =>
        (action, args) => DeviceAction(drive, args.String("path") ?? throw new ArgumentException($"{action} needs a path."));

    // Writes a block of one byte, as the machine would, unlocking the disk first.
    private static void Write(Apple2Disk35Drive drive, uint block, byte value)
    {
        Disk35Disk disk = drive.Disk ?? throw new InvalidOperationException("The drive is empty.");
        disk.IsWriteProtected = false;
        byte[] bytes = new byte[512];
        bytes.AsSpan().Fill(value);
        disk.WriteBlock(block, bytes);
    }

    // What a drive says its disk changed.
    private static JsonObject? Differences(IDevice device) =>
        MediaActions.Device(device, "differences", Speaking())?["differences"]?.AsObject();

    // Arguments from a client that speaks media's answers.
    private static JsonObject Speaking() => new() { ["supportsRetrocoreMedia"] = 1 };
}
