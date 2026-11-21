// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using Retrocore.Debug;
using Retrocore.Machines.Apple2;
using Retrocore.Media;
using System.Diagnostics;
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
    ///  Makes the tests' folder; local data, where backups and locks go, is the run's (<see cref="TestLocalData"/>).
    /// </summary>
    /// <param name="context">The test context.</param>
    [ClassInitialize]
    public static void Initialize(TestContext context)
    {
        s_root = Path.Join(Path.GetTempPath(), $"retrocore-media-{Environment.ProcessId}");
        Directory.CreateDirectory(s_root);
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
        Directory.EnumerateFiles(Path.GetDirectoryName(image) ?? "", $".{Path.GetFileName(image)}.*.saving").Should().BeEmpty();

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
    ///  The host watches each image a disk came from: a write by something else marks the source stale, with the
    ///  revision the disk matches and the one there now, and marking the file read-only shows as a read-only image,
    ///  each sent to the device list as it happens; a save over the file makes it current again.
    /// </summary>
    [TestMethod]
    public void ImageChangedOnDiskShowsInItsDrive()
    {
        (string image, _) = Image("watched.dsk");
        Apple2FloppyDrive drive = Drive(image);
        Source(drive)?.Bool("stale").Should().BeFalse();
        Source(drive)?["readOnly"].Should().BeNull();

        byte[] outside = new byte[35 * 4096];
        outside[0] = 0x55;
        Until(() => File.WriteAllBytes(image, outside), () => Source(drive)?.Bool("stale") == true);
        JsonObject stale = Source(drive) ?? throw new InvalidOperationException("No source.");
        stale["baseline"]?["sha256"]?.GetValue<string>().Should().NotBe(stale["current"]?["sha256"]?.GetValue<string>());
        stale["current"]?["length"]?.GetValue<long>().Should().Be(outside.Length);

        Until(() => File.SetAttributes(image, FileAttributes.ReadOnly), () => Source(drive)?.String("readOnly") == "file");
        Until(() => File.SetAttributes(image, FileAttributes.Normal), () => Source(drive)?["readOnly"] is null);

        Change(drive);
        JsonObject authorized = Speaking();
        authorized["overwrite"] = new JsonObject { ["sha256"] = stale["current"]?["sha256"]?.GetValue<string>() };
        MediaActions.Save(drive, authorized).String("outcome").Should().Be("saved");
        Source(drive)?.Bool("stale").Should().BeFalse("the disk now matches the file it wrote");
        Source(drive)?["baseline"].Should().BeNull();
    }

    /// <summary>
    ///  An image changed between being read and being watched is found stale by the check that follows its watch.
    /// </summary>
    [TestMethod]
    public void ImageChangedBeforeItIsWatchedShowsStale()
    {
        (string image, byte[] read) = Image("early.dsk");
        File.WriteAllBytes(image, new byte[35 * 4096]);
        Apple2FloppyDrive drive = Drive(path: null);
        LoadedDisk loaded = DiskIIImage.Load(read, ".dsk");
        void Insert()
        {
            MediaActions.Register(loaded.Disk, image, loaded.Codec, read);
            drive.Insert(loaded.Disk, image, "DSK");
        }

        Until(Insert, () => Source(drive)?.Bool("stale") == true);
    }

    /// <summary>
    ///  An image read through a link is watched where the link leads, as a save writes there.
    /// </summary>
    [TestMethod]
    public void ImageThroughALinkIsWatchedWhereItLeads()
    {
        (string target, _) = Image("target.dsk");
        string folder = Path.Join(s_root, $"links-{Guid.NewGuid():N}");
        Directory.CreateDirectory(folder);
        string link = Path.Join(folder, "link.dsk");
        try
        {
            File.CreateSymbolicLink(link, target);
        }
        catch (Exception exception) when (exception is IOException or UnauthorizedAccessException)
        {
            Assert.Inconclusive($"Symbolic links cannot be made here: {exception.Message}");
        }

        Apple2FloppyDrive drive = Drive(link);
        Source(drive)?.Bool("stale").Should().BeFalse();
        byte[] outside = new byte[35 * 4096];
        outside[0] = 0x55;
        Until(() => File.WriteAllBytes(target, outside), () => Source(drive)?.Bool("stale") == true);

        // The file the link leads to marked read-only is a read-only image, as a save would find it.
        Until(() => File.SetAttributes(target, FileAttributes.ReadOnly), () => Source(drive)?.String("readOnly") == "file");
        File.SetAttributes(target, FileAttributes.Normal);

        // A link on the way pointed at another file: the next sweep finds the disk's path leads elsewhere.
        string middle = Path.Join(folder, "middle.dsk");
        (string other, _) = Image("other.dsk");
        File.CreateSymbolicLink(middle, target);
        string through = Path.Join(folder, "through.dsk");
        File.CreateSymbolicLink(through, middle);
        File.WriteAllBytes(target, File.ReadAllBytes(other));
        Apple2FloppyDrive chained = Drive(through);
        Source(chained)?.Bool("stale").Should().BeFalse();
        // The file the link now leads to holds other bytes than the one the disk was read from.
        string third = Path.Join(folder, "third.dsk");
        byte[] elsewhere = new byte[35 * 4096];
        elsewhere[1] = 0x77;
        File.WriteAllBytes(third, elsewhere);
        void Repoint()
        {
            File.Delete(middle);
            File.CreateSymbolicLink(middle, third);
        }

        Until(Repoint, () => Source(chained)?.Bool("stale") == true);
    }

    /// <summary>
    ///  An image whose folder is deleted and made again is still watched: the sweep makes the watch again and finds the
    ///  file the disk was read from is not the one there now.
    /// </summary>
    [TestMethod]
    public void ImageWhoseFolderIsMadeAgainIsStillWatched()
    {
        string folder = Path.Join(s_root, $"again-{Guid.NewGuid():N}");
        Directory.CreateDirectory(folder);
        string image = Path.Join(folder, "work.dsk");
        byte[] read = new byte[35 * 4096];
        new Random(5).NextBytes(read);
        File.WriteAllBytes(image, read);
        Apple2FloppyDrive drive = Drive(image);
        Until(() => Directory.Delete(folder, recursive: true), () => Source(drive)?.Bool("stale") == true);

        // Made again with the file as it was: the same file, so the disk matches it again.
        void MakeAgain()
        {
            Directory.CreateDirectory(folder);
            File.WriteAllBytes(image, read);
        }

        Until(MakeAgain, () => Source(drive)?.Bool("stale") == false);
        byte[] outside = new byte[35 * 4096];
        Until(() => File.WriteAllBytes(image, outside), () => Source(drive)?.Bool("stale") == true);
    }

    /// <summary>
    ///  An image is still watched while every thread of the thread pool is busy and work waits behind them, as when a
    ///  full test run fills the machine: the watch keeps its own time, not the pool's.
    /// </summary>
    [TestMethod]
    [DoNotParallelize]
    public void ImageIsWatchedWhileThePoolIsBusy()
    {
        (string image, _) = Image("busy.dsk");
        Apple2FloppyDrive drive = Drive(image);
        Until(() => { }, () => Source(drive)?.Bool("stale") == false);

        // A pool that adds no threads, as one whose work keeps finishing does not, and work holding each of them until
        // let go, so anything else queued waits.
        ThreadPool.GetMaxThreads(out int workers, out int completions);
        ThreadPool.GetMinThreads(out int least, out _);
        ThreadPool.SetMaxThreads(least, completions).Should().BeTrue();
        using ManualResetEventSlim release = new();
        int queued = least * 2;
        int done = 0;
        for (int i = 0; i < queued; i++)
        {
            ThreadPool.UnsafeQueueUserWorkItem(
                _ =>
                {
                    release.Wait(TimeSpan.FromSeconds(30));
                    Interlocked.Increment(ref done);
                },
                state: null);
        }

        try
        {
            byte[] outside = new byte[35 * 4096];
            Until(() => File.WriteAllBytes(image, outside), () => Source(drive)?.Bool("stale") == true);
        }
        finally
        {
            release.Set();
            ThreadPool.SetMaxThreads(workers, completions);
            SpinWait.SpinUntil(() => Volatile.Read(ref done) == queued, TimeSpan.FromSeconds(30));
        }
    }

    /// <summary>
    ///  An image is still watched while something told of another image's change has not returned, as a debug session
    ///  waiting for its machine: each image's check goes on.
    /// </summary>
    [TestMethod]
    [DoNotParallelize]
    public void ImageIsWatchedWhileAnotherChangeIsBeingTold()
    {
        (string first, _) = Image("first.dsk");
        (string second, _) = Image("second.dsk");
        Apple2FloppyDrive one = Drive(first);
        Apple2FloppyDrive two = Drive(second, "disk2");
        Until(() => { }, () => Source(one)?.Bool("stale") == false && Source(two)?.Bool("stale") == false);

        using ManualResetEventSlim release = new();
        void Held() => release.Wait(TimeSpan.FromSeconds(30));
        MediaActions.SourcesChanged += Held;
        try
        {
            byte[] outside = new byte[35 * 4096];
            Until(() => File.WriteAllBytes(first, outside), () => Source(one)?.Bool("stale") == true);
            Until(() => File.WriteAllBytes(second, outside), () => Source(two)?.Bool("stale") == true);
        }
        finally
        {
            MediaActions.SourcesChanged -= Held;
            release.Set();
        }
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

        // Agreed to, the file is made writable and saved over.
        JsonObject writable = Speaking();
        writable["makeWritable"] = true;
        MediaActions.Save(drive, writable).String("outcome").Should().Be("saved");
        File.GetAttributes(image).HasFlag(FileAttributes.ReadOnly).Should().BeFalse();
        drive.Media?.Changed.Should().BeFalse();

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
    ///  turn, a disk that went in since is asked about again, and an answer for an old mount does nothing. Each drive
    ///  here is built anew, as a card put back in is, and still gives its mount a generation of its own.
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
        one.MountGeneration.Should().NotBe(two.MountGeneration, "no two mounts share a generation, even in drives built anew");
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

    /// <summary>
    ///  A save that does not save is an error for a client that does not speak the answers, so it never takes one
    ///  for a save.
    /// </summary>
    [TestMethod]
    public void UnsavedOutcomesAreErrorsForOlderClients()
    {
        string woz = Path.Join(s_root, $"older-{Guid.NewGuid():N}.woz");
        File.WriteAllBytes(woz, SectorDiskConverter.Convert(new byte[35 * 4096], proDosOrder: false, volume: 7).Export());
        Apple2FloppyDrive drive = Drive(woz);
        JsonObject older = new() { ["path"] = Path.ChangeExtension(woz, ".dsk") };
        Action lossy = () => MediaActions.Device(drive, "save", older);
        lossy.Should().Throw<InvalidOperationException>().WithMessage("*was not saved*");

        older["acceptLosses"] = true;
        MediaActions.Device(drive, "save", older)?.String("outcome").Should().Be("saved");
    }

    /// <summary>
    ///  A save through a linked folder is a save to the image itself: its backup is the image's, as a save by its own
    ///  path keeps it, so both paths share one lock and one backup.
    /// </summary>
    [TestMethod]
    public void LinkedFolderIsTheSameImage()
    {
        string real = Directory.CreateDirectory(Path.Join(s_root, $"real-{Guid.NewGuid():N}")).FullName;
        string link = Path.Join(s_root, $"link-{Guid.NewGuid():N}");
        try
        {
            Directory.CreateSymbolicLink(link, real);
        }
        catch (Exception exception) when (exception is IOException or UnauthorizedAccessException)
        {
            // Windows makes symbolic links only with the privilege; a junction, which anyone can make, links too.
            if (OperatingSystem.IsWindows())
            {
                System.Diagnostics.ProcessStartInfo start = new("cmd.exe", ["/c", "mklink", "/J", link, real]);
                start.CreateNoWindow = true;
                using System.Diagnostics.Process? junction = System.Diagnostics.Process.Start(start);

                junction?.WaitForExit();
            }

            if (!Directory.Exists(link))
            {
                Assert.Inconclusive($"Folder links cannot be made here: {exception.Message}");
            }
        }

        string image = Path.Join(real, "linked.dsk");
        byte[] bytes = new byte[35 * 4096];
        new Random(7).NextBytes(bytes);
        File.WriteAllBytes(image, bytes);
        Apple2FloppyDrive drive = Drive(Path.Join(link, "linked.dsk"));
        Change(drive);
        JsonObject saved = MediaActions.Save(drive, Speaking());
        saved.String("outcome").Should().Be("saved");
        saved.String("backup").Should().Be(LocalData.BackupFor(image));
        Directory.Delete(link);
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

    // The drive's media source as the device list gives it.
    private static JsonObject? Source(Apple2FloppyDrive drive) => DeviceJson.Write(drive)["media"]?["source"]?.AsObject();

    // Does something to an image and waits for the host to see it, as its watcher tells the device list.
    private static void Until(Action act, Func<bool> seen)
    {
        using ManualResetEventSlim changed = new();

        // The event may be raised with the handlers it had before this one was removed, after the wait is disposed.
        void Changed()
        {
            try
            {
                changed.Set();
            }
            catch (ObjectDisposedException)
            {
                // This wait is over.
            }
        }

        MediaActions.SourcesChanged += Changed;
        try
        {
            act();
            Stopwatch clock = Stopwatch.StartNew();
            while (!seen() && clock.Elapsed < TimeSpan.FromSeconds(10))
            {
                changed.Wait(TimeSpan.FromMilliseconds(100));
                changed.Reset();
            }

            seen().Should().BeTrue("the host's watcher sees the change");
        }
        finally
        {
            MediaActions.SourcesChanged -= Changed;
        }
    }

    // Arguments from a client that speaks media's answers.
    private static JsonObject Speaking() => new() { ["supportsRetrocoreMedia"] = 1 };
}
