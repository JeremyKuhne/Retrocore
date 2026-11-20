// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using Retrocore.Debug;
using Retrocore.Machines.Acorn;
using Retrocore.Machines.Apple2;
using Retrocore.Machines.Devices;
using Retrocore.Media;
using Retrocore.Media.Acorn;
using Retrocore.Media.Floppy;
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
    ///  Setting a journal aside that was interrupted, its snapshots moved and its journal not yet, is finished by the
    ///  next open, so the two stay together.
    /// </summary>
    [TestMethod]
    public void AnInterruptedSetAsideIsFinished()
    {
        string id = Id();
        (Apple2Disk35Drive drive, _) = Drive("interrupted.po");
        Write(drive, block: 1, 0x5A);
        Stop(Open(id), drive);
        string snapshot = Snapshots(id).Single();
        string folder = Path.Join(RecoveryJournal.Root, id);
        File.WriteAllText(Path.Join(folder, "journal.json"), "{ not json");
        Directory.CreateDirectory(Path.Join(folder, "Unreadable-pending"));
        Directory.Move(Path.Join(folder, "Media"), Path.Join(folder, "Unreadable-pending", "Media"));

        List<string> problems = [];
        RecoveryJournal journal = RecoveryJournal.Open(id, problems) ?? throw new InvalidOperationException("The journal is taken.");
        problems.Should().ContainSingle().Which.Should().Contain("interrupted");
        Stop(journal);
        string aside = Directory.EnumerateDirectories(folder, "Unreadable-*").Single();
        File.Exists(Path.Join(aside, "Media", snapshot)).Should().BeTrue();
        File.Exists(Path.Join(aside, "journal.json")).Should().BeTrue();
    }

    /// <summary>
    ///  A commit removes only snapshots it wrote or put back, never a file no entry it knows names, as the snapshot of
    ///  an entry kept as it was.
    /// </summary>
    [TestMethod]
    public void ACommitLeavesSnapshotsItDoesNotKnow()
    {
        string id = Id();
        RecoveryJournal journal = Open(id);
        string stray = Path.Join(RecoveryJournal.Root, id, "Media", "stray.woz");
        File.WriteAllText(stray, "a disk");
        Stop(journal);
        File.Exists(stray).Should().BeTrue();
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
    ///  A journal whose session did not end cleanly, with no process holding it, is found with its machine's name and
    ///  disks; recovering it keeps the disks and stops offering it, and a clean or running one is never offered.
    /// </summary>
    [TestMethod]
    public void AnUncleanSessionIsFoundAndRecovered()
    {
        string id = Id();
        (Apple2Disk35Drive drive, string image) = Drive("crashed.po");
        Write(drive, block: 1, 0x21);
        RecoveryJournal running = RecoveryJournal.Open(id, [], "Apple IIe for Work") ?? throw new InvalidOperationException("The journal is taken.");
        running.Commit(MediaActions.Journal([drive], running));
        Offered(id).Should().BeNull("a running session keeps its journal");

        // The process ends without closing it: the system lets go of its lock, and its session says it did not end.
        Crash(running);
        JsonObject offered = Offered(id) ?? throw new InvalidOperationException("The session is not offered.");
        offered.String("name").Should().Be("Apple IIe for Work");
        offered["disks"]?.AsArray().Select(disk => disk?.GetValue<string>()).Should().Equal(image);
        offered.String("kept").Should().NotBeNull();

        RecoveryJournal.Resolve(new JsonObject { ["id"] = id, ["action"] = "recover" });
        Offered(id).Should().BeNull("a recovered session is not offered again");
        Disks(id).Should().HaveCount(1, "its disk is kept for the next launch");
    }

    /// <summary>
    ///  Discarding a session's disks removes its journal and the snapshots it names, and no other file.
    /// </summary>
    [TestMethod]
    public void DiscardingAnUncleanSessionLetsItsDisksGo()
    {
        string id = Id();
        (Apple2Disk35Drive drive, _) = Drive("discarded.po");
        Write(drive, block: 1, 0x31);
        RecoveryJournal running = Open(id);
        running.Commit(MediaActions.Journal([drive], running));
        Crash(running);
        string stray = Path.Join(RecoveryJournal.Root, id, "Media", "stray.woz");
        File.WriteAllText(stray, "a disk");

        RecoveryJournal.Resolve(new JsonObject { ["id"] = id, ["action"] = "discard" });
        Offered(id).Should().BeNull();
        File.Exists(Path.Join(RecoveryJournal.Root, id, "journal.json")).Should().BeFalse();
        Snapshots(id).Should().Equal("stray.woz");
    }

    /// <summary>
    ///  A discard names the journal it asked about: once the machine kept its disks again, the discard lets nothing
    ///  go and says so, and the journal as it is now, found by its id, can be asked about again.
    /// </summary>
    [TestMethod]
    public void ADiscardAskedAboutAnEarlierJournalLetsNothingGo()
    {
        string id = Id();
        (Apple2Disk35Drive drive, _) = Drive("asked.po");
        Write(drive, block: 1, 0x51);
        RecoveryJournal running = Open(id);
        running.Commit(MediaActions.Journal([drive], running));
        Crash(running);
        string asked = Offered(id)?.String("revision") ?? throw new InvalidOperationException("Not offered.");

        // The machine runs again, changes its disk, and stops cleanly.
        RecoveryJournal again = Open(id);
        Write(drive, block: 2, 0x52);
        Stop(again, drive);
        Offered(id).Should().BeNull("a clean stop is not offered as a crash");
        JsonObject now = RecoveryJournal.Unclean(new JsonObject
        {
            ["id"] = id
        }).OfType<JsonObject>().Single();

        now.String("revision").Should().NotBe(asked);

        JsonObject stale = new() { ["id"] = id, ["action"] = "discard", ["revision"] = asked };
        RecoveryJournal.Resolve(stale).String("outcome").Should().Be("changed");
        Disks(id).Should().HaveCount(1, "the disk kept since stays");
        JsonObject current = new() { ["id"] = id, ["action"] = "discard", ["revision"] = now.String("revision") };
        RecoveryJournal.Resolve(current).String("outcome").Should().BeNull();
        File.Exists(Path.Join(RecoveryJournal.Root, id, "journal.json")).Should().BeFalse();
    }

    /// <summary>
    ///  The off machine opens a journal without taking it for a session: what its last session said stays, so a
    ///  session that did not end cleanly is still offered after the off machine showed its disks.
    /// </summary>
    [TestMethod]
    public void TheOffMachineLeavesTheSessionAsItWas()
    {
        string id = Id();
        (Apple2Disk35Drive drive, string image) = Drive("looked.po");
        Write(drive, block: 1, 0x41);
        RecoveryJournal running = Open(id);
        running.Commit(MediaActions.Journal([drive], running));
        Crash(running);

        RecoveryJournal looking = RecoveryJournal.Open(id, [], claim: false) ?? throw new InvalidOperationException("The journal is taken.");
        Apple2Disk35Drive off = Again(image);
        MediaActions.Recover([off], looking).Should().BeEmpty();
        off.Media?.Changed.Should().BeTrue();
        MediaActions.IsKept(off.Medium ?? throw new InvalidOperationException("The drive is empty.")).Should().BeTrue();
        looking.Commit(MediaActions.Journal([off], looking), close: true);
        Offered(id).Should().NotBeNull("only a person's choice, or a session, ends the offer");
    }

    // What the host offers for a journal whose session did not end cleanly, or null.
    private static JsonObject? Offered(string id) =>
        RecoveryJournal.Unclean().OfType<JsonObject>().FirstOrDefault(journal => journal.String("id") == id);

    // Ends a session as a process that stops without closing its journal does: its lock goes, and its session still
    // says it has not ended.
    private static void Crash(RecoveryJournal journal)
    {
        journal.Release();
        string session = Path.Join(RecoveryJournal.Root, journal.Id, "session.json");
        JsonObject json = JsonNode.Parse(File.ReadAllText(session))?.AsObject() ?? throw new InvalidOperationException("No session.");
        json["clean"].Should().NotBeNull();
        json["clean"]?.GetValue<bool>().Should().BeFalse();
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

    /// <summary>
    ///  A BBC Micro's SSD disk and UEF tape are kept and come back with their images' codecs, so each saves to its
    ///  image in its own format.
    /// </summary>
    [TestMethod]
    public void BbcMediaComeBackWithTheirImagesCodecs()
    {
        string id = Id();
        string ssd = Path.Join(s_root, $"kept-{Guid.NewGuid():N}.ssd");
        byte[] disk = AcornDiskImage.Encode(AcornDiskImage.Blank(tracks: 40), doubleSided: false).Bytes;
        File.WriteAllBytes(ssd, disk);
        string uef = Path.Join(s_root, $"kept-{Guid.NewGuid():N}.uef");
        byte[] tape = UefFormat.Write([.. Enumerable.Repeat(1, 4800)]);
        File.WriteAllBytes(uef, tape);

        (BbcFloppyDrive floppy, BbcCassette cassette) = BbcDrives(ssd, uef);
        floppy.Disk?.MarkChanged();
        AcornTape recorded = cassette.Tape ?? throw new InvalidOperationException("The recorder is empty.");
        recorded.Record(recorded.HalfCycles.Count, 2);
        Stop(Open(id), floppy, cassette);
        Disks(id).Select(entry => entry?["kind"]?.GetValue<string>()).Should().BeEquivalentTo([DmkFormat.SnapshotKind, AcornTape.SnapshotKind]);

        (BbcFloppyDrive nextFloppy, BbcCassette nextCassette) = BbcDrives(ssd, uef);
        RecoveryJournal journal = Open(id);
        MediaActions.Recover([nextFloppy, nextCassette], journal).Should().BeEmpty();
        nextFloppy.Media?.Changed.Should().BeTrue();
        nextCassette.Media?.Changed.Should().BeTrue();
        nextCassette.Mode.Should().Be(TapeMode.Playing, "a recovered tape plays, as LOAD and CHAIN need");
        FloppyDisk backDisk = nextFloppy.Disk ?? throw new InvalidOperationException("The drive is empty.");
        MediaActions.Source(backDisk)?.Codec.Should().BeOfType<AcornDiskCodec>().Which.Format.Should().Be("SSD");
        AcornTape back = nextCassette.Tape ?? throw new InvalidOperationException("The recorder is empty.");
        MediaActions.Source(back)?.Codec.Should().BeOfType<AcornTapeCodec>();
        back.HalfCycles.Should().HaveCount(4801);

        MediaActions.Device(nextFloppy, "save", Speaking())?.String("outcome").Should().Be("saved");
        MediaActions.Device(nextCassette, "save", Speaking())?.String("outcome").Should().Be("saved");
        File.ReadAllBytes(ssd).Should().Equal(disk);
        UefFormat.Read(File.ReadAllBytes(uef)).HalfCycles.Should().Equal(back.HalfCycles);
        Stop(journal, nextFloppy, nextCassette);
        Disks(id).Should().BeEmpty();
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

    // A BBC Micro's first disk drive and cassette with images in them, read and registered as the debug host does.
    private static (BbcFloppyDrive Floppy, BbcCassette Cassette) BbcDrives(string ssd, string uef)
    {
        BbcFloppyDrive floppy = new(new Intel8271(), drive: 0);
        byte[] disk = File.ReadAllBytes(ssd);
        FloppyDisk read = AcornDiskImage.Read(disk, doubleSided: false);
        MediaActions.Register(read, ssd, new AcornDiskCodec("SSD"), disk);
        floppy.Insert(read, ssd, "SSD");

        BbcCassette cassette = new();
        byte[] tape = File.ReadAllBytes(uef);
        AcornTape loaded = UefFormat.Read(tape);
        MediaActions.Register(loaded, uef, new AcornTapeCodec(), tape);
        cassette.Insert(loaded, uef);
        return (floppy, cassette);
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
