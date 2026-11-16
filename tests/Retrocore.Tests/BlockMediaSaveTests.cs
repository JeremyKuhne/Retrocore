// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using Retrocore.Debug;
using Retrocore.Machines.Apple2;
using Retrocore.Machines.Devices;
using Retrocore.Media;
using System.Buffers.Binary;
using System.Text.Json.Nodes;

namespace Retrocore.Tests;

/// <summary>
///  The block drives save as the Disk II does, step by step through the debug host: the 3.5 drive, the ProFile and
///  slot 7, to bare blocks and to 2MG, with the 2MG's header, comment and creator data kept and its flag as the lock.
/// </summary>
[TestClass]
public sealed class BlockMediaSaveTests
{
    private static readonly string s_inputs = Path.Join(AppContext.BaseDirectory, "Inputs");
    private static readonly Lazy<Apple2Roms> s_roms = new(() => SdkModules.BuildRoms(Apple2Model.IIeEnhanced, s_inputs));
    private static string s_root = "";

    /// <summary>
    ///  Makes the tests' folder; local data, where backups and locks go, is the run's (<see cref="TestLocalData"/>).
    /// </summary>
    /// <param name="context">The test context.</param>
    [ClassInitialize]
    public static void Initialize(TestContext context)
    {
        _ = context;
        s_root = Path.Join(Path.GetTempPath(), $"retrocore-blocks-{Environment.ProcessId}");
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
    ///  An unchanged 2MG wraps back to its own bytes, comment, creator data, unknown bytes and all; a changed one keeps
    ///  them around its new blocks, and its locked flag follows the lock.
    /// </summary>
    [TestMethod]
    public void TwoImgKeepsItsHeaderAndFlagsTheLock()
    {
        byte[] file = TwoImg(blocks: 1600, locked: false, out byte[] blocks);
        Disk35Disk disk = Disk35Disk.Load(file);
        BlockImageCodec codec = BlockImageCodec.For(".2mg") ?? throw new InvalidOperationException();
        codec.Encode(disk.Snapshot()).Bytes.Should().Equal(file, "an unchanged 2MG is the file it read");

        byte[] block = new byte[512];
        block.AsSpan().Fill(0xA5);
        disk.WriteBlock(7, block);
        disk.IsWriteProtected = true;
        byte[] saved = codec.Encode(disk.Snapshot()).Bytes;
        saved.Length.Should().Be(file.Length);
        saved.AsSpan(0, 16).SequenceEqual(file.AsSpan(0, 16)).Should().BeTrue("the header is kept");
        BinaryPrimitives.ReadUInt32LittleEndian(saved.AsSpan(16)).Should().Be(0x8000_0000 | 0x1FE, "the lock is the locked flag");
        saved.AsSpan(64 + blocks.Length).SequenceEqual(file.AsSpan(64 + blocks.Length)).Should().BeTrue("the comment and the rest are kept");
        saved.AsSpan(64 + 7 * 512, 512).ToArray().Should().AllBeEquivalentTo((byte)0xA5);

        Disk35Disk again = Disk35Disk.Load(saved);
        again.IsWriteProtected.Should().BeTrue();
        byte[] read = new byte[512];
        again.ReadBlock(7, read);
        read.Should().Equal(block);

        EncodedImage bare = (BlockImageCodec.For("po") ?? throw new InvalidOperationException()).Encode(disk.Snapshot());
        bare.Bytes.Length.Should().Be(blocks.Length);
        bare.IsLossless.Should().BeTrue();
        bare.Notes.Should().ContainSingle().Which.Should().Contain("comment");
    }

    /// <summary>
    ///  A ProFile's image saves to its own file, keeping a backup, and reads back as what the machine wrote; Save As
    ///  writes a 2MG, which the ProFile reads again.
    /// </summary>
    [TestMethod]
    public void ProFileSavesItsImage()
    {
        (string path, byte[] original) = Image("hard.po", blocks: 280);
        ProFileDrive drive = ProFile();
        ProFileMedia.Insert(drive, path);
        drive.Info.Operations.HasFlag(MediaOperations.Save).Should().BeTrue();
        drive.Medium.Should().BeOfType<MemoryBlockDevice>();
        int generation = drive.MountGeneration;

        Write(drive.Image, block: 3, 0x5A);
        drive.Media?.Changed.Should().BeTrue();
        MediaActions.HasUnsaved(drive).Should().BeTrue();
        MediaActions.Device(drive, "eject", Speaking())?.String("outcome").Should().Be("changed");

        JsonObject answer = MediaActions.Device(drive, "save", Speaking()) ?? throw new InvalidOperationException("No answer.");
        answer.String("outcome").Should().Be("saved");
        answer.Int("generation").Should().Be(generation);
        answer.String("backup").Should().NotBeNull();
        File.ReadAllBytes(answer.String("backup") ?? "").Should().Equal(original);
        drive.Media?.Changed.Should().BeFalse();
        File.ReadAllBytes(path).AsSpan(3 * 512, 512).ToArray().Should().AllBeEquivalentTo((byte)0x5A);

        string copy = Path.Join(s_root, $"hard-{Guid.NewGuid():N}.2mg");
        JsonObject saveAs = Speaking();
        saveAs["path"] = copy;
        Write(drive.Image, block: 4, 0x6B);
        MediaActions.Save(drive, saveAs).String("outcome").Should().Be("saved");
        drive.Media?.Format.Should().Be("2MG");
        drive.Media?.Label.Should().Be(copy);
        TwoImgContainer.IsTwoImg(File.ReadAllBytes(copy)).Should().BeTrue();

        ProFileMedia.Insert(drive, copy);
        drive.Media?.Changed.Should().BeFalse("a saved disk comes out without a question");
        byte[] read = new byte[512];
        drive.Image?.ReadBlock(4, read);
        read.Should().AllBeEquivalentTo((byte)0x6B);
    }

    /// <summary>
    ///  A locked ProFile fails a write as a failed write does, and changes nothing; the lock alone is not a change.
    /// </summary>
    [TestMethod]
    public void LockedProFileFailsWrites()
    {
        (string path, _) = Image("locked.hdv", blocks: 280);
        ProFileDrive drive = ProFile();
        ProFileMedia.Insert(drive, path);
        drive.Info.Operations.HasFlag(MediaOperations.WriteProtect).Should().BeTrue();
        drive.SetWriteProtected(writeProtected: true);
        drive.Media?.WriteProtected.Should().BeTrue();
        drive.Media?.Changed.Should().BeFalse("a lock alone is not yet a change to save");

        byte status = WriteThroughHandshakes(drive, block: 2, 0x77);
        (status & 1).Should().Be(1, "the operation-unsuccessful bit");
        drive.Media?.Changed.Should().BeFalse();

        drive.SetWriteProtected(writeProtected: false);
        WriteThroughHandshakes(drive, block: 2, 0x77).Should().Be(0);
        drive.Media?.Changed.Should().BeTrue();
    }

    /// <summary>
    ///  A 3.5-inch disk saves to its 2MG with the header kept, and to the formats it offers; a format it does not
    ///  save is refused with the ones it does.
    /// </summary>
    [TestMethod]
    public void Disk35SavesToItsFormats()
    {
        string path = Path.Join(s_root, $"disk35-{Guid.NewGuid():N}.2mg");
        byte[] file = TwoImg(blocks: 1600, locked: false, out _);
        File.WriteAllBytes(path, file);
        Apple2Machine machine = new(Apple2Model.IIeEnhanced, s_roms.Value);
        machine.Bus.InstallDisk35(5);
        Apple2Disk35Drive drive = machine.Bus.Disk35.Drives[0];
        DeviceAction(drive, path);
        drive.Media?.Format.Should().Be("2MG");

        MediaActions.Save(drive, Speaking()).String("outcome").Should().Be("saved");
        File.ReadAllBytes(path).Should().Equal(file, "an unchanged disk writes nothing");

        int generation = drive.MountGeneration;
        Write(drive.Disk, block: 100, 0x3C);
        MediaActions.Save(drive, Speaking()).String("outcome").Should().Be("saved");
        byte[] saved = File.ReadAllBytes(path);
        saved.AsSpan(0, 64).SequenceEqual(file.AsSpan(0, 64)).Should().BeTrue();
        saved.AsSpan(64 + 1600 * 512).SequenceEqual(file.AsSpan(64 + 1600 * 512)).Should().BeTrue();
        drive.MountGeneration.Should().Be(generation);

        JsonObject asWoz = Speaking();
        asWoz["path"] = Path.Join(s_root, "disk35.woz");
        Action wrong = () => MediaActions.Save(drive, asWoz);
        wrong.Should().Throw<ArgumentException>().WithMessage("*.po, .2mg, .hdv, .img*");

        string bare = Path.Join(s_root, $"disk35-{Guid.NewGuid():N}.po");
        JsonObject asPo = Speaking();
        asPo["path"] = bare;
        JsonObject answer = MediaActions.Save(drive, asPo);
        answer.String("outcome").Should().Be("saved");
        answer.Array("notes").Should().ContainSingle();
        new FileInfo(bare).Length.Should().Be(1600 * 512);

        drive.Eject();
        drive.MountGeneration.Should().NotBe(generation, "a disk coming out is a new mount");
    }

    /// <summary>
    ///  Slot 7's image loads locked, as it always has; unlocked, the machine writes it and it saves, and the ROM says
    ///  the device writes from the next reset.
    /// </summary>
    [TestMethod]
    public void Slot7SavesOnceUnlocked()
    {
        (string path, _) = Image("slot7.po", blocks: 280);
        Apple2Machine machine = Apple2Loader.Load(Apple2Model.IIeEnhanced, s_roms.Value, path);
        Apple2BlockStorage storage = machine.BlockStorage ?? throw new InvalidOperationException("Slot 7 is empty.");
        storage.Media?.WriteProtected.Should().BeTrue();
        storage.WritesAnnounced.Should().BeFalse();
        storage.Info.Operations.Should().Be(MediaOperations.WriteProtect | MediaOperations.Save);

        storage.SetWriteProtected(writeProtected: false);
        storage.WritesAnnounced.Should().BeFalse("ProDOS read the ROM as it started");
        machine.Reset();
        storage.WritesAnnounced.Should().BeTrue();

        Write(machine.Bus.BlockDevice, block: 9, 0x42);
        storage.Media?.Changed.Should().BeTrue();
        MediaActions.Device(storage, "save", Speaking())?.String("outcome").Should().Be("saved");
        storage.Media?.Changed.Should().BeFalse();
        File.ReadAllBytes(path).AsSpan(9 * 512, 512).ToArray().Should().AllBeEquivalentTo((byte)0x42);
    }

    /// <summary>
    ///  A 2MG whose data length is left zero has the length of its block count, figured without wrapping: a count too
    ///  large for the file is refused, not taken as one that fits.
    /// </summary>
    [TestMethod]
    public void TwoImgBlockCountCannotWrap()
    {
        byte[] file = TwoImg(blocks: 1600, locked: false, out _);
        BinaryPrimitives.WriteUInt32LittleEndian(file.AsSpan(28), 0);
        BinaryPrimitives.WriteUInt32LittleEndian(file.AsSpan(20), 0x0080_0640);
        Action load = () => MemoryBlockDevice.Load(file);
        load.Should().Throw<InvalidDataException>();

        BinaryPrimitives.WriteUInt32LittleEndian(file.AsSpan(20), 1600);
        MemoryBlockDevice.Load(file).BlockCount.Should().Be(1600u);
    }

    /// <summary>
    ///  A drive saves an image back as what it holds, not what its name says: a 2MG named <c>.po</c> saves as a 2MG,
    ///  and bare blocks named <c>.2mg</c> save as bare blocks.
    /// </summary>
    [TestMethod]
    public void ImageSavesAsWhatItHolds()
    {
        string misnamed = Path.Join(s_root, $"misnamed-{Guid.NewGuid():N}.po");
        byte[] file = TwoImg(blocks: 280, locked: false, out _);
        File.WriteAllBytes(misnamed, file);
        ProFileDrive drive = ProFile();
        ProFileMedia.Insert(drive, misnamed);
        drive.Media?.Format.Should().Be("2MG");
        Write(drive.Image, block: 2, 0x11);
        MediaActions.Save(drive, Speaking()).String("outcome").Should().Be("saved");
        byte[] saved = File.ReadAllBytes(misnamed);
        saved.Length.Should().Be(file.Length);
        saved.AsSpan(0, 16).SequenceEqual(file.AsSpan(0, 16)).Should().BeTrue("the 2MG's header is kept");

        (string bare, byte[] blocks) = Image("bare.2mg", blocks: 280);
        ProFileMedia.Insert(drive, bare);
        drive.Media?.Format.Should().Be("PO");
        Write(drive.Image, block: 2, 0x22);
        MediaActions.Save(drive, Speaking()).String("outcome").Should().Be("saved");
        byte[] again = File.ReadAllBytes(bare);
        again.Length.Should().Be(blocks.Length);
        TwoImgContainer.IsTwoImg(again).Should().BeFalse();
    }

    /// <summary>
    ///  An image too large for a ProFile is refused by its size, a 2MG's by the data its header gives, before it is
    ///  read; the drive keeps the image it had.
    /// </summary>
    [TestMethod]
    public void OversizedImageIsRefusedUnread()
    {
        (string path, _) = Image("kept.po", blocks: 280);
        ProFileDrive drive = ProFile();
        ProFileMedia.Insert(drive, path);

        string large = Path.Join(s_root, $"large-{Guid.NewGuid():N}.po");
        using (FileStream stream = File.Create(large)) { stream.SetLength((ProFileMedia.MaximumBlocks + 1) * 512L); }
        Action bare = () => ProFileMedia.Insert(drive, large);
        bare.Should().Throw<InvalidDataException>();

        string header = Path.Join(s_root, $"large-{Guid.NewGuid():N}.2mg");
        byte[] file = TwoImg(blocks: 280, locked: false, out _);
        BinaryPrimitives.WriteUInt32LittleEndian(file.AsSpan(28), (ProFileMedia.MaximumBlocks + 1) * 512u);
        File.WriteAllBytes(header, file);
        Action twoImg = () => ProFileMedia.Insert(drive, header);
        twoImg.Should().Throw<InvalidDataException>();
        drive.Media?.Label.Should().Be(path);
    }

    /// <summary>
    ///  A ProFile holding a 3.5-inch disk saves it as it saves its own images, and the disk is unchanged after.
    /// </summary>
    [TestMethod]
    public void ProFileSavesA35Disk()
    {
        string path = Path.Join(s_root, $"profile35-{Guid.NewGuid():N}.2mg");
        File.WriteAllBytes(path, TwoImg(blocks: 1600, locked: false, out _));
        Disk35Disk disk = Disk35Disk.Load(File.ReadAllBytes(path));
        ProFileDrive drive = ProFile();
        drive.Insert(disk, path, "2MG");
        MediaActions.Register(disk, path, BlockImageCodec.For(".2mg"), File.ReadAllBytes(path));
        drive.Medium.Should().BeSameAs(disk);

        Write(disk, block: 12, 0x5C);
        drive.Media?.Changed.Should().BeTrue();
        string copy = Path.Join(s_root, $"profile35-{Guid.NewGuid():N}.po");
        JsonObject saveAs = Speaking();
        saveAs["path"] = copy;
        MediaActions.Save(drive, saveAs).String("outcome").Should().Be("saved");
        drive.Media?.Changed.Should().BeFalse();
        drive.Media?.Label.Should().Be(copy);
        File.ReadAllBytes(copy).AsSpan(12 * 512, 512).ToArray().Should().AllBeEquivalentTo((byte)0x5C);
    }

    /// <summary>
    ///  A saved machine whose slot 7 a Save As moved gives the launch that image, as no insert can; one that did not
    ///  move it, a Disk II launch, and an image no longer there leave the launch as it is.
    /// </summary>
    [TestMethod]
    public void Slot7SaveAsMovesItsLaunch()
    {
        (string path, _) = Image("launch.po", blocks: 280);
        string copy = Path.Join(s_root, $"moved-{Guid.NewGuid():N}.2mg");
        File.WriteAllBytes(copy, TwoImg(blocks: 280, locked: false, out _));
        JsonObject launch = new() { ["machine"] = "apple2", ["diskImage"] = path };
        static JsonObject Saved(string image) => new()
        {
            ["media"] = new JsonObject { ["slot7"] = new JsonObject { ["path"] = image } },
        };

        LaunchMedia.WithSaved(launch, saved: null).Should().BeSameAs(launch);
        LaunchMedia.WithSaved(launch, Saved(path)).Should().BeSameAs(launch, "slot 7 is where the launch put it");
        JsonObject moved = LaunchMedia.WithSaved(launch, Saved(copy));
        moved.String("diskImage").Should().Be(copy);
        moved.String("machine").Should().Be("apple2");
        launch.String("diskImage").Should().Be(path, "the launch it came from is not changed");

        JsonObject diskII = new() { ["machine"] = "apple2", ["diskImage"] = path, ["diskController"] = "diskII" };
        LaunchMedia.WithSaved(diskII, Saved(copy)).Should().BeSameAs(diskII, "the Disk II has no slot 7 device");
        LaunchMedia.WithSaved(launch, Saved(Path.Join(s_root, "gone.po"))).Should().BeSameAs(launch);

        Apple2Machine machine = Apple2Loader.Load(Apple2Model.IIeEnhanced, s_roms.Value, path);
        Apple2BlockStorage storage = machine.BlockStorage ?? throw new InvalidOperationException("Slot 7 is empty.");
        LaunchMedia.FromLaunch(storage).Should().BeTrue("a saved machine keeps slot 7's image");
        LaunchMedia.FromLaunch(ProFile()).Should().BeFalse();
    }

    // A ProFile on no card, with a clock that never moves.
    private static ProFileDrive ProFile() => new("slot4profile", ".PROFILE", "ProFile card", () => 0, activityTime: 1);

    // Inserts a 3.5-inch image as the debug host does.
    private static void DeviceAction(Apple2Disk35Drive drive, string path) => Apple2Loader.Insert(drive, path);

    // Writes a block of one byte, as the machine would, unlocking the medium first.
    private static void Write(IBlockDevice? device, uint block, byte value)
    {
        IBlockDevice blocks = device ?? throw new InvalidOperationException("The drive is empty.");
        if (blocks is IMedium medium) { medium.IsWriteProtected = false; }
        byte[] bytes = new byte[512];
        bytes.AsSpan().Fill(value);
        blocks.WriteBlock(block, bytes);
    }

    // Writes a block through the ProFile's handshakes, as its card does; returns the first status byte.
    private static byte WriteThroughHandshakes(ProFileDrive drive, uint block, byte value)
    {
        void Handshake()
        {
            drive.SetCommand(high: true);
            drive.WriteData(ProFileDrive.Acknowledge);
            drive.SetCommand(high: false);
        }

        Handshake();
        foreach (byte b in new byte[] { 1, 0, (byte)(block >> 8), (byte)block, 0, 0 }) { drive.WriteData(b); }
        Handshake();
        for (int i = 0; i < 512 + 20; i++) { drive.WriteData(value); }
        Handshake();
        return drive.ReadData();
    }

    // A bare block image of random bytes in the tests' folder.
    private static (string Path, byte[] Bytes) Image(string name, int blocks)
    {
        byte[] bytes = new byte[blocks * 512];
        new Random(name.Length).NextBytes(bytes);
        string path = Path.Join(s_root, $"{Path.GetFileNameWithoutExtension(name)}-{Guid.NewGuid():N}{Path.GetExtension(name)}");
        File.WriteAllBytes(path, bytes);
        return (path, bytes);
    }

    // A 2MG of random blocks with a creator and version of its own, flags this code does not know, a comment, creator
    // data, and bytes after them that no field names.
    private static byte[] TwoImg(int blocks, bool locked, out byte[] data)
    {
        data = new byte[blocks * 512];
        new Random(blocks).NextBytes(data);
        byte[] comment = "Made by a test"u8.ToArray();
        byte[] creator = [1, 2, 3, 4, 5];
        byte[] tail = [0xDE, 0xAD];
        byte[] file = new byte[64 + data.Length + comment.Length + creator.Length + tail.Length];
        Span<byte> header = file;
        "2IMG"u8.CopyTo(header);
        "TEST"u8.CopyTo(header[4..]);
        BinaryPrimitives.WriteUInt16LittleEndian(header[8..], 64);
        BinaryPrimitives.WriteUInt16LittleEndian(header[10..], 1);
        BinaryPrimitives.WriteUInt32LittleEndian(header[12..], 1);
        BinaryPrimitives.WriteUInt32LittleEndian(header[16..], (locked ? 0x8000_0000u : 0) | 0x1FE);
        BinaryPrimitives.WriteUInt32LittleEndian(header[20..], (uint)blocks);
        BinaryPrimitives.WriteUInt32LittleEndian(header[24..], 64);
        BinaryPrimitives.WriteUInt32LittleEndian(header[28..], (uint)data.Length);
        int commentAt = 64 + data.Length;
        BinaryPrimitives.WriteUInt32LittleEndian(header[32..], (uint)commentAt);
        BinaryPrimitives.WriteUInt32LittleEndian(header[36..], (uint)comment.Length);
        BinaryPrimitives.WriteUInt32LittleEndian(header[40..], (uint)(commentAt + comment.Length));
        BinaryPrimitives.WriteUInt32LittleEndian(header[44..], (uint)creator.Length);
        header[48] = 0x99;
        data.CopyTo(file, 64);
        comment.CopyTo(file, commentAt);
        creator.CopyTo(file, commentAt + comment.Length);
        tail.CopyTo(file, commentAt + comment.Length + creator.Length);
        return file;
    }

    // Arguments from a client that speaks the answers.
    private static JsonObject Speaking() => new() { ["supportsRetrocoreMedia"] = true };
}
