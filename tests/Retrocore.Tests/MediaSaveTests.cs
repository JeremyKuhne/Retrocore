// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using Retrocore.Debug;
using Retrocore.Machines.Apple2;
using Retrocore.Media;
using System.Text.Json.Nodes;

namespace Retrocore.Tests;

/// <summary>
///  The host's saves and detach checks, as the media persistence plan's first phase has them: a save writes over
///  only the revision the disk matches, keeps one backup, writes nothing for an unchanged disk, asks before losing
///  what a format cannot hold, and says when an image cannot be written; a changed disk does not leave its drive
///  until it is saved or let go.
/// </summary>
[TestClass]
public sealed class MediaSaveTests
{
    private static string s_root = "";

    /// <summary>
    ///  Points local data, where backups and locks go, at a folder of the tests' own.
    /// </summary>
    /// <param name="context">The test context.</param>
    [ClassInitialize]
    public static void Initialize(TestContext context)
    {
        s_root = Path.Join(Path.GetTempPath(), $"retrocore-media-{Environment.ProcessId}");
        Directory.CreateDirectory(s_root);
        Environment.SetEnvironmentVariable("RETROCORE_LOCAL_DATA", Path.Join(s_root, "local"));
    }

    /// <summary>
    ///  Removes the tests' folder.
    /// </summary>
    [ClassCleanup]
    public static void Cleanup()
    {
        foreach (string file in Directory.EnumerateFiles(s_root, "*", SearchOption.AllDirectories))
        {
            File.SetAttributes(file, FileAttributes.Normal);
        }

        Directory.Delete(s_root, recursive: true);
    }

    /// <summary>
    ///  A changed disk saves to its own image in the order it was read, keeps the revision it replaced as the one
    ///  backup, and is unchanged after.
    /// </summary>
    [TestMethod]
    public void SaveWritesItsImageAndKeepsABackup()
    {
        (string image, byte[] original) = Image("own.dsk");
        Apple2FloppyDrive drive = Drive(image);
        Change(drive);

        JsonObject answer = MediaActions.Save(drive, Speaking());
        answer.String("outcome").Should().Be("saved");
        answer.String("device").Should().Be("disk1");
        drive.Media?.Changed.Should().BeFalse();
        answer.String("backup").Should().NotBeNull("a changed disk is written, keeping what it replaced");
        File.ReadAllBytes(answer.String("backup") ?? "").Should().Equal(original);
        Directory.EnumerateFiles(Path.GetDirectoryName(image) ?? "", "*.saving").Should().BeEmpty();

        // The saved image reads back as the disk the machine wrote.
        WozDisk saved = DiskIIImage.Load(File.ReadAllBytes(image), "dsk").Disk;
        SectorDiskReader.Read(saved, proDosOrder: false).Should().Equal(SectorDiskReader.Read(drive.Disk ?? throw new InvalidOperationException(), proDosOrder: false));
    }

    /// <summary>
    ///  An unchanged disk saved to its own unchanged image writes nothing, so the file stays the one it read.
    /// </summary>
    [TestMethod]
    public void UnchangedSaveWritesNothing()
    {
        (string image, byte[] original) = Image("unchanged.dsk");
        DateTime written = File.GetLastWriteTimeUtc(image);
        Apple2FloppyDrive drive = Drive(image);

        JsonObject answer = MediaActions.Save(drive, Speaking());
        answer.String("outcome").Should().Be("saved");
        answer["backup"].Should().BeNull();
        File.ReadAllBytes(image).Should().Equal(original);
        File.GetLastWriteTimeUtc(image).Should().Be(written);
    }

    /// <summary>
    ///  An image written by something else since the disk was read is a conflict, naming both revisions; the save
    ///  goes ahead over exactly the revision the user agreed to replace.
    /// </summary>
    [TestMethod]
    public void ChangedImageIsAConflictUntilItsRevisionIsAuthorized()
    {
        (string image, _) = Image("conflict.dsk");
        Apple2FloppyDrive drive = Drive(image);
        Change(drive);
        byte[] outside = new byte[35 * 4096];
        outside[0] = 0x55;
        File.WriteAllBytes(image, outside);

        JsonObject conflict = MediaActions.Save(drive, Speaking());
        conflict.String("outcome").Should().Be("conflict");
        string current = conflict["current"]?["sha256"]?.GetValue<string>() ?? "";
        current.Should().NotBe(conflict["baseline"]?["sha256"]?.GetValue<string>());
        conflict["medium"]?.GetValue<string>().Should().StartWith("m-");
        File.ReadAllBytes(image).Should().Equal(outside, "nothing was written");

        JsonObject stale = Speaking();
        stale["overwrite"] = new JsonObject { ["sha256"] = new string('0', 64) };
        MediaActions.Save(drive, stale).String("outcome").Should().Be("conflict", "an old answer does not authorize another revision");

        JsonObject authorized = Speaking();
        authorized["overwrite"] = new JsonObject { ["sha256"] = current };
        JsonObject saved = MediaActions.Save(drive, authorized);
        saved.String("outcome").Should().Be("saved");
        File.ReadAllBytes(saved.String("backup") ?? "").Should().Equal(outside, "the backup holds what was replaced");
        drive.Media?.Changed.Should().BeFalse();
    }

    /// <summary>
    ///  A format that cannot hold all of the disk answers with what it would lose and writes nothing; accepted, it
    ///  saves and the disk stays changed.
    /// </summary>
    [TestMethod]
    public void LossySaveAsksAndStaysChanged()
    {
        string woz = Path.Join(s_root, $"seven-{Guid.NewGuid():N}.woz");
        File.WriteAllBytes(woz, SectorDiskConverter.Convert(new byte[35 * 4096], proDosOrder: false, volume: 7).Export());
        Apple2FloppyDrive drive = Drive(woz);
        string dsk = Path.ChangeExtension(woz, ".dsk");

        JsonObject asked = Speaking();
        asked["path"] = dsk;
        JsonObject losses = MediaActions.Save(drive, asked);
        losses.String("outcome").Should().Be("losses");
        losses.String("format").Should().Be("DSK");
        losses["losses"]?.AsArray().Should().ContainSingle();
        File.Exists(dsk).Should().BeFalse();

        asked["acceptLosses"] = true;
        JsonObject saved = MediaActions.Save(drive, asked);
        saved.String("outcome").Should().Be("saved");
        File.Exists(dsk).Should().BeTrue();
        drive.Media?.Label.Should().Be(dsk);
        drive.Media?.Changed.Should().BeTrue("the image cannot give the disk back");
    }

    /// <summary>
    ///  An image that cannot be written answers readOnly with why: a read-only file, a disk no image gave, and an
    ///  image that can only be read; Save As still works.
    /// </summary>
    [TestMethod]
    public void UnwritableImagesAnswerReadOnly()
    {
        (string image, _) = Image("locked.dsk");
        Apple2FloppyDrive drive = Drive(image);
        Change(drive);
        File.SetAttributes(image, FileAttributes.ReadOnly);
        MediaActions.Save(drive, Speaking()).String("reason").Should().Be("file");
        File.SetAttributes(image, FileAttributes.Normal);

        Apple2FloppyDrive built = Drive(path: null);
        built.Insert(SectorDiskConverter.Convert(new byte[35 * 4096], proDosOrder: false), "DOS 3.3 disk with HELLO", "DSK");
        MediaActions.Save(built, Speaking()).String("reason").Should().Be("noImage");

        string d13 = Path.Join(s_root, $"old-{Guid.NewGuid():N}.d13");
        File.WriteAllBytes(d13, new byte[35 * 13 * 256]);
        Apple2FloppyDrive thirteen = Drive(d13);
        MediaActions.Save(thirteen, Speaking()).String("reason").Should().Be("format");

        JsonObject saveAs = Speaking();
        saveAs["path"] = Path.ChangeExtension(d13, ".woz");
        MediaActions.Save(thirteen, saveAs).String("outcome").Should().Be("saved");
        thirteen.Media?.Format.Should().Be("WOZ");
    }

    /// <summary>
    ///  A changed disk does not leave its drive: ejecting it or inserting another over it answers changed to a client
    ///  that speaks the answers, is refused for one that does not, and goes once discard is given. An unchanged disk
    ///  goes.
    /// </summary>
    [TestMethod]
    public void ChangedDiskDoesNotLeaveUntilSavedOrDiscarded()
    {
        (string image, _) = Image("detach.dsk");
        Apple2FloppyDrive drive = Drive(image);
        MediaActions.Device(drive, "eject", Speaking()).Should().BeNull("an unchanged disk goes");

        Change(drive);
        JsonObject changed = MediaActions.Device(drive, "eject", Speaking()) ?? throw new InvalidOperationException("No answer.");
        changed.String("outcome").Should().Be("changed");
        changed.String("device").Should().Be("disk1");
        changed["generation"]?.GetValue<int>().Should().Be(drive.MountGeneration);
        MediaActions.Device(drive, "insert", Speaking())?.String("outcome").Should().Be("changed");
        MediaActions.Device(drive, "writeProtect", Speaking()).Should().BeNull("only leaving the drive is held back");

        Action older = () => MediaActions.Device(drive, "eject", []);
        older.Should().Throw<InvalidOperationException>().WithMessage("*not saved*");

        JsonObject discard = Speaking();
        discard["discard"] = true;
        MediaActions.Device(drive, "eject", discard).Should().BeNull();

        MediaActions.Save(drive, Speaking()).String("outcome").Should().Be("saved");
        MediaActions.Device(drive, "eject", Speaking()).Should().BeNull("a saved disk goes");
    }

    /// <summary>
    ///  Save As moves the disk to the new image: a later save goes there, in its format.
    /// </summary>
    [TestMethod]
    public void SaveAsMovesTheDisk()
    {
        (string image, byte[] original) = Image("first.dsk");
        Apple2FloppyDrive drive = Drive(image);
        Change(drive);
        string copy = Path.Join(s_root, $"copy-{Guid.NewGuid():N}.woz");
        JsonObject saveAs = Speaking();
        saveAs["path"] = copy;
        MediaActions.Save(drive, saveAs).String("outcome").Should().Be("saved");
        drive.Media?.Label.Should().Be(copy);
        drive.Media?.Format.Should().Be("WOZ");
        File.ReadAllBytes(image).Should().Equal(original, "the image it came from is untouched");

        Change(drive);
        MediaActions.Save(drive, Speaking()).String("outcome").Should().Be("saved");
        WozDisk.Load(File.ReadAllBytes(copy)).Should().NotBeNull();
        File.ReadAllBytes(image).Should().Equal(original);
    }

    /// <summary>
    ///  Save As writes only where there is no file, or over the revision of the file the person chose: one that
    ///  appeared or changed since is a conflict.
    /// </summary>
    [TestMethod]
    public void SaveAsReplacesOnlyTheFileChosen()
    {
        (string image, _) = Image("source.dsk");
        Apple2FloppyDrive drive = Drive(image);
        (string there, byte[] before) = Image("there.dsk");

        JsonObject unasked = Speaking();
        unasked["path"] = there;
        JsonObject conflict = MediaActions.Save(drive, unasked);
        conflict.String("outcome").Should().Be("conflict", "a file is there that no one agreed to replace");
        conflict.String("path").Should().Be(there);
        conflict["baseline"].Should().BeNull();
        File.ReadAllBytes(there).Should().Equal(before);

        string chosen = FileRevision.Read(there)?.Sha256 ?? "";
        File.WriteAllBytes(there, new byte[35 * 4096]);
        JsonObject stale = Speaking();
        stale["path"] = there;
        stale["overwrite"] = new JsonObject { ["sha256"] = chosen };
        MediaActions.Save(drive, stale).String("outcome").Should().Be("conflict", "the file changed since it was chosen");

        stale["overwrite"] = new JsonObject { ["sha256"] = FileRevision.Read(there)?.Sha256 };
        MediaActions.Save(drive, stale).String("outcome").Should().Be("saved");
    }

    /// <summary>
    ///  An image deleted since its disk was read is a conflict with no current revision, and agreeing to write where
    ///  there is no file saves it there again.
    /// </summary>
    [TestMethod]
    public void DeletedImageIsSavedAgainOnceAgreed()
    {
        (string image, _) = Image("deleted.dsk");
        Apple2FloppyDrive drive = Drive(image);
        Change(drive);
        File.Delete(image);

        JsonObject conflict = MediaActions.Save(drive, Speaking());
        conflict.String("outcome").Should().Be("conflict");
        conflict["current"].Should().BeNull();

        JsonObject again = Speaking();
        again["overwrite"] = new JsonObject { ["sha256"] = null };
        MediaActions.Save(drive, again).String("outcome").Should().Be("saved");
        File.Exists(image).Should().BeTrue();
        drive.Media?.Changed.Should().BeFalse();
    }

    /// <summary>
    ///  Letting a disk go holds only for the mount it was asked about: a card's other changed disk is asked about in
    ///  turn, a disk that went in since is asked about again, and an answer for an old mount does nothing.
    /// </summary>
    [TestMethod]
    public void AnswersHoldOnlyForTheMountAskedAbout()
    {
        (string first, _) = Image("one.dsk");
        (string second, _) = Image("two.dsk");
        Apple2FloppyDrive one = Drive(first);
        Apple2FloppyDrive two = Drive(second, "disk2");
        Change(one);
        Change(two);
        Apple2FloppyDrive[] card = [one, two];
        string[] ids = ["disk1", "disk2"];

        JsonObject args = Speaking();
        args["action"] = "removeCard";
        JsonObject? asked = MediaActions.Hardware(ids, card, "removeCard", args);
        asked?.String("device").Should().Be("disk1");
        JsonArray discards = [new JsonObject { ["device"] = "disk1", ["generation"] = one.MountGeneration }];
        args["discards"] = discards;
        MediaActions.Hardware(ids, card, "removeCard", args)?.String("device").Should().Be("disk2", "the other disk was not asked about");

        int old = one.MountGeneration;
        byte[] bytes = File.ReadAllBytes(first);
        one.Insert(DiskIIImage.Load(bytes, ".dsk").Disk, first, "DSK");
        Change(one);
        discards.Add(new JsonObject { ["device"] = "disk2", ["generation"] = two.MountGeneration });
        MediaActions.Hardware(ids, card, "removeCard", args)?.String("device").Should().Be("disk1", "a new disk went in since");

        JsonObject late = Speaking();
        late["generation"] = old;
        Action save = () => MediaActions.Device(one, "save", late);
        save.Should().Throw<InvalidOperationException>().WithMessage("*since you were asked*");
    }

    // A 35-track DOS-order sector image of random bytes, in the tests' folder.
    private static (string Path, byte[] Bytes) Image(string name)
    {
        byte[] bytes = new byte[35 * 4096];
        new Random(name.Length).NextBytes(bytes);
        string path = Path.Join(s_root, $"{Path.GetFileNameWithoutExtension(name)}-{Guid.NewGuid():N}{Path.GetExtension(name)}");
        File.WriteAllBytes(path, bytes);
        return (path, bytes);
    }

    // A Disk II drive with an image inserted as the debug host inserts one.
    private static Apple2FloppyDrive Drive(string? path, string id = "disk1")
    {
        DiskIIController controller = new();
        controller.SetFirmware(new DiskIIFirmware(new byte[256], new byte[256]));
        Apple2FloppyDrive drive = new(controller, drive: 1, id, "Drive 1", "drive", "controller");
        if (path is null) { return drive; }

        // As the debug host's Apple2Loader.Insert does.
        byte[] bytes = File.ReadAllBytes(path);
        LoadedDisk loaded = DiskIIImage.Load(bytes, Path.GetExtension(path));
        MediaActions.Register(loaded.Disk, path, loaded.Codec, bytes);
        drive.Insert(loaded.Disk, path, loaded.Codec?.Format ?? "D13");
        return drive;
    }

    // The machine writes the disk: a bit on track 5, written as it was, so every sector still reads.
    private static void Change(Apple2FloppyDrive drive)
    {
        WozDisk disk = drive.Disk ?? throw new InvalidOperationException("The drive is empty.");
        disk.IsWriteProtected = false;
        DiskTrack track = disk.Track(5 * 4) ?? throw new InvalidOperationException("Track 5 is not formatted.");
        disk.WriteBit(quarterTrack: 5 * 4, position: 4000, transition: track.ReadBit(4000));
    }

    // Arguments from a client that speaks media's answers.
    private static JsonObject Speaking() => new() { ["supportsRetrocoreMedia"] = 1 };
}
