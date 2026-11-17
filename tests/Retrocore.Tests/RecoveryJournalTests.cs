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
///  The recovery journal, as the media persistence plan's fourth phase has it: a machine's changed disks, in its
///  drives and ejected from them, are kept in local data as they change and as it stops, and go back in their drives,
///  still changed against their images, when it starts again; a disk saved leaves it, and one that cannot go back
///  stays in it.
/// </summary>
[TestClass]
public sealed class RecoveryJournalTests
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
        s_root = Path.Join(Path.GetTempPath(), $"retrocore-journal-{Environment.ProcessId}");
        Directory.CreateDirectory(s_root);
    }

    /// <summary>
    ///  Removes the tests' folder.
    /// </summary>
    [ClassCleanup]
    public static void Cleanup() => Directory.Delete(s_root, recursive: true);

    /// <summary>
    ///  A changed disk kept as the machine stops goes back in its drive in the next machine, as the machine left it and
    ///  changed against its image as it was read; saved, it leaves the journal with its snapshot.
    /// </summary>
    [TestMethod]
    public void AKeptDiskComesBackChangedAndLeavesOnceSaved()
    {
        string id = Id();
        (Apple2Disk35Drive drive, string image) = Drive("kept.po");
        Write(drive, block: 7, 0x42);
        Stop(Open(id), drive);

        Apple2Disk35Drive next = Again(image);
        RecoveryJournal journal = Open(id);
        journal.Kept.Should().HaveCount(1);
        MediaActions.Recover([next], journal).Should().BeEmpty();
        next.Media?.Changed.Should().BeTrue("the disk is still changed against its image");
        Block(next, 7).Should().AllSatisfy(value => value.Should().Be(0x42));
        MediaActions.Source(next.Medium ?? throw new InvalidOperationException("The drive is empty."))?.Path.Should().Be(image);
        MediaActions.Device(next, "differences", Speaking())?["differences"]?["summary"]?.GetValue<string>().Should().Be("block 7");

        MediaActions.Device(next, "save", Speaking())?.String("outcome").Should().Be("saved");
        Stop(journal, next);
        Disks(id).Should().BeEmpty();
        Snapshots(id).Should().BeEmpty("a saved disk's snapshots go with it");
    }

    /// <summary>
    ///  A Disk II disk is kept as WOZ2 and comes back with the codec its image was read with, so it saves to its
    ///  <c>.dsk</c> in the same sector order.
    /// </summary>
    [TestMethod]
    public void ADiskIIDiskComesBackWithItsImagesCodec()
    {
        string id = Id();
        string dsk = Path.Join(s_root, $"kept-{Guid.NewGuid():N}.dsk");
        byte[] bytes = new byte[35 * 4096];
        new Random(5).NextBytes(bytes);
        File.WriteAllBytes(dsk, bytes);
        Apple2FloppyDrive floppy = Floppy(dsk);
        floppy.Disk?.MarkChanged();
        Stop(Open(id), floppy);
        Disks(id).Single()?["kind"]?.GetValue<string>().Should().Be(WozDisk.SnapshotKind);

        Apple2FloppyDrive next = Floppy(dsk);
        RecoveryJournal journal = Open(id);
        MediaActions.Recover([next], journal).Should().BeEmpty();
        next.Media?.Changed.Should().BeTrue();
        MediaActions.Source(next.Disk ?? throw new InvalidOperationException("The drive is empty."))?.Codec
            .Should().BeOfType<SectorImageCodec>().Which.Format.Should().Be("DSK");

        MediaActions.Device(next, "save", Speaking())?.String("outcome").Should().Be("saved");
        File.ReadAllBytes(dsk).Should().Equal(bytes, "the disk is the image it was read from, in its order");
        Stop(journal, next);
    }

    /// <summary>
    ///  A checkpoint writes a disk's snapshot only when it changed since the last, and keeps one snapshot of each.
    /// </summary>
    [TestMethod]
    public void ACheckpointCopiesOnlyWhatChanged()
    {
        string id = Id();
        (Apple2Disk35Drive drive, _) = Drive("checkpoint.po");
        RecoveryJournal journal = Open(id);
        Write(drive, block: 3, 0x11);
        journal.Commit(MediaActions.Journal([drive], journal));
        string[] first = Snapshots(id);
        first.Should().HaveCount(1);

        journal.Commit(MediaActions.Journal([drive], journal));
        Snapshots(id).Should().Equal(first, "the disk did not change");

        Write(drive, block: 4, 0x22);
        journal.Commit(MediaActions.Journal([drive], journal));
        string[] second = Snapshots(id);
        second.Should().HaveCount(1).And.NotEqual(first, "a new snapshot replaces the old once the journal names it");
        Stop(journal, drive);
    }

    /// <summary>
    ///  A changed disk the machine ejected is kept under its drive, by its ejected id, and comes back there.
    /// </summary>
    [TestMethod]
    public void AnEjectedDiskComesBackUnderItsDrive()
    {
        string id = Id();
        (Apple2Disk35Drive drive, string image) = Drive("ejected.po");
        Write(drive, block: 9, 0x33);
        drive.EjectByProgram();
        string ejected = MediaActions.Ejected(drive).Single().Id;
        Stop(Open(id), drive);
        Disks(id).Single()?["ejected"]?["id"]?.GetValue<string>().Should().Be(ejected);

        Apple2Disk35Drive next = Again(image);
        RecoveryJournal journal = Open(id);
        MediaActions.Recover([next], journal).Should().BeEmpty();
        KeptDisk kept = MediaActions.Ejected(next).Single();
        kept.Id.Should().Be(ejected);
        kept.Medium.IsDirty.Should().BeTrue();
        next.Media?.Changed.Should().BeFalse("the drive has its image, unchanged");
        Stop(journal, next);
    }

    /// <summary>
    ///  A kept disk that cannot go back, as when the machine has no drive for it now, stays in the journal as it was.
    /// </summary>
    [TestMethod]
    public void ADiskThatCannotGoBackStays()
    {
        string id = Id();
        (Apple2Disk35Drive drive, _) = Drive("stays.po");
        Write(drive, block: 2, 0x44);
        Stop(Open(id), drive);
        string[] snapshots = Snapshots(id);

        RecoveryJournal journal = Open(id);
        MediaActions.Recover([], journal).Should().ContainSingle().Which.Should().Contain("could not be put back");
        Stop(journal);
        Disks(id).Should().HaveCount(1);
        Snapshots(id).Should().Equal(snapshots);
    }

    /// <summary>
    ///  A running session keeps its journal: another session of the same machine gets none until it stops.
    /// </summary>
    [TestMethod]
    public void ARunningSessionKeepsItsJournal()
    {
        string id = Id();
        RecoveryJournal first = Open(id);
        RecoveryJournal.Open(id, []).Should().BeNull();
        first.Commit([], close: true);
        Open(id).Commit([], close: true);
    }

    /// <summary>
    ///  A journal that cannot be read is set aside with its snapshots, which no later commit removes.
    /// </summary>
    [TestMethod]
    public void AnUnreadableJournalIsSetAsideWithItsDisks()
    {
        string id = Id();
        (Apple2Disk35Drive drive, _) = Drive("unreadable.po");
        Write(drive, block: 1, 0x55);
        Stop(Open(id), drive);
        string snapshot = Snapshots(id).Single();
        string folder = Path.Join(RecoveryJournal.Root, id);
        File.WriteAllText(Path.Join(folder, "journal.json"), "{ not json");

        List<string> problems = [];
        RecoveryJournal journal = RecoveryJournal.Open(id, problems) ?? throw new InvalidOperationException("The journal is taken.");
        problems.Should().ContainSingle().Which.Should().Contain("could not be read");
        journal.Kept.Should().BeEmpty();
        Stop(journal);

        string aside = Directory.EnumerateDirectories(folder, "Unreadable-*").Single();
        File.Exists(Path.Join(aside, "Media", snapshot)).Should().BeTrue("the disk is kept beside the journal it was in");
        File.ReadAllText(Path.Join(aside, "journal.json")).Should().Be("{ not json");
    }

    /// <summary>
    ///  A journal that reads as JSON but not as a journal is set aside too, never taken for an empty one.
    /// </summary>
    /// <param name="text">The journal's text.</param>
    [TestMethod]
    [DataRow("{}")]
    [DataRow("""{ "disks": {} }""")]
    [DataRow("""{ "disks": [1] }""")]
    public void AJournalOfTheWrongShapeIsSetAside(string text)
    {
        string id = Id();
        (Apple2Disk35Drive drive, _) = Drive("shape.po");
        Write(drive, block: 1, 0x66);
        Stop(Open(id), drive);
        File.WriteAllText(Path.Join(RecoveryJournal.Root, id, "journal.json"), text);

        List<string> problems = [];
        RecoveryJournal journal = RecoveryJournal.Open(id, problems) ?? throw new InvalidOperationException("The journal is taken.");
        problems.Should().ContainSingle().Which.Should().Contain("could not be read");
        Stop(journal);
        Directory.EnumerateDirectories(Path.Join(RecoveryJournal.Root, id), "Unreadable-*").Should().ContainSingle();
    }

    /// <summary>
    ///  Two disks kept for one drive, as when one could not go back and another changed there since, never replace
    ///  each other: the first goes back, and the second stays in the journal.
    /// </summary>
    [TestMethod]
    public void TwoDisksKeptForOneDriveBothStay()
    {
        string id = Id();
        (Apple2Disk35Drive drive, string image) = Drive("twice.po");
        Write(drive, block: 1, 0x77);
        Stop(Open(id), drive);

        // The drive is gone for a launch, then back with another changed disk.
        RecoveryJournal without = Open(id);
        MediaActions.Recover([], without).Should().ContainSingle();
        Apple2Disk35Drive other = Again(image);
        Write(other, block: 2, 0x88);
        Stop(without, other);
        Disks(id).Should().HaveCount(2);

        Apple2Disk35Drive next = Again(image);
        RecoveryJournal journal = Open(id);
        MediaActions.Recover([next], journal).Should().ContainSingle().Which.Should().Contain("went back in it");
        Stop(journal, next);
        Disks(id).Should().HaveCount(2, "neither disk is dropped");
        Snapshots(id).Should().HaveCount(2);
    }

    /// <summary>
    ///  An entry with a field of the wrong type stays in the journal, the disk going nowhere, and the entries after it
    ///  still go back.
    /// </summary>
    [TestMethod]
    public void ABadEntryStaysAndTheRestGoBack()
    {
        string id = Id();
        (Apple2Disk35Drive drive, string image) = Drive("bad.po");
        Write(drive, block: 1, 0x99);
        Stop(Open(id), drive);
        string journalPath = Path.Join(RecoveryJournal.Root, id, "journal.json");
        JsonObject root = JsonNode.Parse(File.ReadAllText(journalPath))?.AsObject() ?? throw new InvalidOperationException("No journal.");
        JsonArray disks = root["disks"]?.AsArray() ?? throw new InvalidOperationException("No disks.");
        JsonObject good = disks[0]?.AsObject() ?? throw new InvalidOperationException("No disk.");
        JsonObject badLabel = (JsonObject)good.DeepClone();
        badLabel["label"] = new JsonObject();
        JsonObject badBaseline = (JsonObject)good.DeepClone();
        badBaseline["drive"] = "nowhere";
        (badBaseline["source"]?["baseline"]?.AsObject() ?? throw new InvalidOperationException("No baseline."))["length"] = "long";
        // A snapshot named by a number, which no commit can take for a file name.
        JsonObject badFile = (JsonObject)good.DeepClone();
        badFile["file"] = 5;
        disks.Insert(0, badFile);
        disks.Insert(0, badLabel);
        disks.Insert(1, badBaseline);
        File.WriteAllText(journalPath, root.ToJsonString());

        Apple2Disk35Drive next = Again(image);
        RecoveryJournal journal = Open(id);
        MediaActions.Recover([next], journal).Should().HaveCount(3);
        next.Media?.Changed.Should().BeTrue("the good entry went back");
        Stop(journal, next);
        Disks(id).Should().HaveCount(4, "the bad entries stay as they were");
        Snapshots(id).Should().NotBeEmpty();
    }

    /// <summary>
    ///  A recovery id is letters, digits, dashes and underscores, so it cannot name a folder elsewhere.
    /// </summary>
    [TestMethod]
    public void ARecoveryIdNamesOnlyAJournal()
    {
        Action open = () => RecoveryJournal.Open(@"..\elsewhere", []);
        open.Should().Throw<ArgumentException>();
    }

    private static string Id() => $"test-{Guid.NewGuid():N}";

    private static RecoveryJournal Open(string id) => RecoveryJournal.Open(id, []) ?? throw new InvalidOperationException("The journal is taken.");

    // Ends a session as the debug host does: a last checkpoint, closing the journal.
    private static void Stop(RecoveryJournal journal, params IDevice[] devices) =>
        journal.Commit(MediaActions.Journal(devices, journal), close: true);

    // The disks the journal names.
    private static JsonArray Disks(string id) =>
        JsonNode.Parse(File.ReadAllText(Path.Join(RecoveryJournal.Root, id, "journal.json")))?["disks"]?.AsArray() ?? [];

    // The snapshots in the journal, by name.
    private static string[] Snapshots(string id) =>
        [.. Directory.EnumerateFiles(Path.Join(RecoveryJournal.Root, id, "Media")).Select(file => Path.GetFileName(file)).Order()];

    // A 3.5 drive on a IIe with a block image in it, inserted as the debug host inserts one.
    private static (Apple2Disk35Drive Drive, string Image) Drive(string name)
    {
        byte[] bytes = new byte[1600 * 512];
        new Random(name.Length).NextBytes(bytes);
        string image = Path.Join(s_root, $"{Path.GetFileNameWithoutExtension(name)}-{Guid.NewGuid():N}{Path.GetExtension(name)}");
        File.WriteAllBytes(image, bytes);
        return (Again(image), image);
    }

    // A new machine's 3.5 drive with an image in it, as the next launch's saved machine inserts it.
    private static Apple2Disk35Drive Again(string image)
    {
        Apple2Machine machine = new(Apple2Model.IIeEnhanced, s_roms.Value);
        machine.Bus.InstallDisk35(5);
        Apple2Disk35Drive drive = machine.Bus.Disk35.Drives[0];
        Apple2Loader.Insert(drive, image);
        return drive;
    }

    // A Disk II drive with a sector image in it, read and registered as the debug host does.
    private static Apple2FloppyDrive Floppy(string path)
    {
        DiskIIController controller = new();
        controller.SetFirmware(new DiskIIFirmware(new byte[256], new byte[256]));
        Apple2FloppyDrive floppy = new(controller, drive: 1, "disk1", "Drive 1", "drive", "controller");
        byte[] bytes = File.ReadAllBytes(path);
        LoadedDisk loaded = DiskIIImage.Load(bytes, ".dsk");
        MediaActions.Register(loaded.Disk, path, loaded.Codec, bytes);
        floppy.Insert(loaded.Disk, path, "DSK");
        return floppy;
    }

    // Writes a block of one byte, as the machine would, unlocking the disk first.
    private static void Write(Apple2Disk35Drive drive, uint block, byte value)
    {
        Disk35Disk disk = drive.Disk ?? throw new InvalidOperationException("The drive is empty.");
        disk.IsWriteProtected = false;
        byte[] bytes = new byte[512];
        bytes.AsSpan().Fill(value);
        disk.WriteBlock(block, bytes);
    }

    private static byte[] Block(Apple2Disk35Drive drive, uint block)
    {
        byte[] bytes = new byte[512];
        (drive.Disk ?? throw new InvalidOperationException("The drive is empty.")).ReadBlock(block, bytes);
        return bytes;
    }

    // Arguments from a client that speaks media's answers.
    private static JsonObject Speaking() => new() { ["supportsRetrocoreMedia"] = 1 };
}
