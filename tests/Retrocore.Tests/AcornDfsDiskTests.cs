// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using Retrocore.Debug;
using Retrocore.Machines.Acorn;
using Retrocore.Media;
using Retrocore.Media.Acorn;
using Retrocore.Media.Floppy;

namespace Retrocore.Tests;

/// <summary>
///  The DFS catalogue writer: its bytes against the catalogue's layout, its errors, and its disks under DNFS 1.20.
/// </summary>
/// <remarks>
///  <para>
///   The machines run on the ROMs built from the SDK's sources, so no dumps are needed: DNFS reads the disks the
///   writer makes, independently of the writer's own reader.
///  </para>
/// </remarks>
[TestClass]
public sealed class AcornDfsDiskTests
{
    private const int Sector = AcornDiskImage.SectorSize;

    private static readonly string s_sources = Path.Join(AppContext.BaseDirectory, "Inputs", "Acorn");
    private static readonly Lazy<BbcRoms> s_diskRoms = new(() => BbcSdkModules.Build(s_sources, filingSystem: true));
    private static readonly Lazy<BbcRoms> s_tapeRoms = new(() => BbcSdkModules.Build(s_sources, filingSystem: false));

    // At &2000: prints the message after it through OSWRCH, then returns.
    private static readonly byte[] s_hello =
    [
        0xA2, 0x00,             // LDX #0
        0xBD, 0x0E, 0x20,       // LDA &200E,X
        0xF0, 0x06,             // BEQ &200D
        0x20, 0xEE, 0xFF,       // JSR OSWRCH
        0xE8,                   // INX
        0xD0, 0xF5,             // BNE &2002
        0x60,                   // RTS
        .. "PROGRAM RAN OK"u8, 0x0D, 0x0A, 0x00
    ];

    /// <summary>
    ///  A new disk is the blank formatted one: 800 sectors, no files, no title, no boot option.
    /// </summary>
    [TestMethod]
    public void CreateIsTheBlankDisk()
    {
        AcornDfsDisk disk = AcornDfsDisk.Create();
        disk.Sectors.Should().Be(800);
        disk.Entries.Should().BeEmpty();
        disk.Title.Should().BeEmpty();
        disk.BootOption.Should().Be(AcornBootOption.None);
        disk.FreeSectors.Should().Be(798);
        disk.ToImage().Should().Equal(AcornDiskImage.Encode(AcornDiskImage.Blank(), doubleSided: false).Bytes);
        AcornDfsDisk.Create(40).Sectors.Should().Be(400);
        AcornDfsDisk.Create(40).ToImage().Should().HaveCount(40 * AcornDiskImage.TrackSize);
    }

    /// <summary>
    ///  Each entry's bytes are the catalogue's layout, worked out by hand: the name and directory with the lock in
    ///  sector 0, and in sector 1 the addresses' and length's low bytes, the byte of their bits 16-17 and the start
    ///  sector's bits 8-9, and the start sector. &amp;FFFFxxxx addresses keep 3 in bits 16-17.
    /// </summary>
    [TestMethod]
    public void EntriesAreTheCatalogueLayout()
    {
        AcornDfsDisk disk = AcornDfsDisk.Create();
        disk.Add(new('$', "HELLO", 0x2000, 0x2000, new byte[20])).StartSector.Should().Be(2);
        disk.Add(new('B', "BIG", 0xFFFF1900, 0xFFFF8023, new byte[0x10100])).StartSector.Should().Be(3);
        disk.Add(new('$', "LAST", 0x12345, 0x2ABCD, [7], Locked: true)).StartSector.Should().Be(260);
        byte[] image = disk.ToImage();

        // Highest start sector first: LAST, BIG, HELLO.
        image[Sector + 5].Should().Be(0x18);
        byte[] names = [.. "LAST   "u8, 0xA4, .. "BIG    "u8, (byte)'B', .. "HELLO  "u8, (byte)'$'];
        image.AsSpan(8, 24).ToArray().Should().Equal(names);
        byte[] information =
        [
            0x45, 0x23, 0xCD, 0xAB, 0x01, 0x00, 0x85, 0x04,
            0x00, 0x19, 0x23, 0x80, 0x00, 0x01, 0xDC, 0x03,
            0x00, 0x20, 0x00, 0x20, 0x14, 0x00, 0x00, 0x02
        ];

        image.AsSpan(Sector + 8, 24).ToArray().Should().Equal(information);
        image[260 * Sector].Should().Be(7);
        image[(260 * Sector) + 1].Should().Be(0, "the rest of a file's last sector is cleared");

        AcornDfsDisk read = AcornDfsDisk.Read(image);
        read.Entries.Select(entry => (
            entry.File.FullName,
            entry.File.LoadAddress,
            entry.File.ExecutionAddress,
            entry.File.Data.Length,
            entry.File.Locked,
            entry.StartSector)).Should().Equal(
            ("$.LAST", 0x12345u, 0x2ABCDu, 1, true, 260),
            ("B.BIG", 0xFFFF1900u, 0xFFFF8023u, 0x10100, false, 3),
            ("$.HELLO", 0x2000u, 0x2000u, 20, false, 2));

        read.ToImage().Should().Equal(image);

        FloppyDisk floppy = AcornDiskImage.Read(image, doubleSided: false);
        EncodedImage encoded = AcornDiskImage.Encode(floppy, doubleSided: false);
        encoded.IsLossless.Should().BeTrue();
        encoded.Bytes.Should().Equal(image);
    }

    /// <summary>
    ///  The title is split eight and four and padded with spaces, as *TITLE pads it; the boot option is bits 4-5 of
    ///  sector 1's byte 6, beside the size; each change counts the sequence number up in decimal.
    /// </summary>
    [TestMethod]
    public void TitleBootOptionAndSequence()
    {
        AcornDfsDisk disk = AcornDfsDisk.Create();
        disk.Title = "ADVENTURE";
        disk.BootOption = AcornBootOption.Run;
        byte[] image = disk.ToImage();
        image.AsSpan(0, 8).ToArray().Should().Equal("ADVENTUR"u8.ToArray());
        image.AsSpan(Sector, 4).ToArray().Should().Equal("E   "u8.ToArray());
        image[Sector + 6].Should().Be(0x23, "boot option 2 and the top bits of 800 sectors");
        image[Sector + 7].Should().Be(0x20);
        image[Sector + 4].Should().Be(0x02);

        for (int change = 0; change < 8; change++) { disk.BootOption = AcornBootOption.None; }
        disk.SequenceNumber.Should().Be(0x10);
        AcornDfsDisk.Read(disk.ToImage()).Title.Should().Be("ADVENTURE");

        disk.Invoking(target => target.Title = "THIRTEEN CHRS").Should().Throw<ArgumentException>();
        disk.Invoking(target => target.Title = "TAB\t").Should().Throw<ArgumentException>();
    }

    /// <summary>
    ///  !BOOT is text with a carriage return after each line, with zero addresses as *BUILD leaves it, and sets
    ///  *OPT 4,3.
    /// </summary>
    [TestMethod]
    public void BootFileIsExecText()
    {
        AcornDfsDisk disk = AcornDfsDisk.Create();
        AcornDfsEntry entry = disk.AddBootFile("*BASIC", "*RUN HELLO");
        entry.File.FullName.Should().Be("$.!BOOT");
        entry.File.Data.Should().Equal([.. "*BASIC\r*RUN HELLO\r"u8]);
        entry.File.LoadAddress.Should().Be(0);
        entry.File.ExecutionAddress.Should().Be(0);
        disk.BootOption.Should().Be(AcornBootOption.Exec);
        disk.Invoking(target => target.AddBootFile("A\rB")).Should().Throw<ArgumentException>();
    }

    /// <summary>
    ///  Bad names, directories, addresses and lengths are refused with what a DFS keeps.
    /// </summary>
    /// <param name="directory">The directory.</param>
    /// <param name="name">The name.</param>
    /// <param name="load">The load address.</param>
    /// <param name="length">The length.</param>
    [TestMethod]
    [DataRow('$', "", 0u, 1)]
    [DataRow('$', "EIGHTCHR", 0u, 1)]
    [DataRow('$', "TWO WORD", 0u, 1)]
    [DataRow('$', "A.B", 0u, 1)]
    [DataRow('$', "WILD#", 0u, 1)]
    [DataRow('$', "WILD*", 0u, 1)]
    [DataRow('$', "Q\"", 0u, 1)]
    [DataRow('$', "COL:", 0u, 1)]
    [DataRow('$', "£", 0u, 1)]
    [DataRow('.', "NAME", 0u, 1)]
    [DataRow(' ', "NAME", 0u, 1)]
    [DataRow('$', "NAME", 0x30000u, 1)]
    [DataRow('$', "NAME", 0xFF001900u, 1)]
    [DataRow('$', "NAME", 0u, 0x40000)]
    public void BadFilesAreRefused(char directory, string name, uint load, int length)
    {
        AcornDfsDisk disk = AcornDfsDisk.Create();
        disk.Invoking(target => target.Add(new(directory, name, load, 0, new byte[length])))
            .Should().Throw<ArgumentException>();

        disk.Entries.Should().BeEmpty();
        disk.SequenceNumber.Should().Be(0);
    }

    /// <summary>
    ///  The 32nd file is refused, the catalogue left as it was; a file of a name already there replaces it, in either
    ///  case, but not a locked one.
    /// </summary>
    [TestMethod]
    public void CatalogueFullAndReplacing()
    {
        AcornDfsDisk disk = AcornDfsDisk.Create();
        for (int index = 0; index < AcornDfsDisk.MaximumFiles; index++)
        {
            disk.Add(new('$', $"F{index}", 0x1900, 0x1900, [(byte)index]));
        }

        byte[] full = disk.ToImage();
        disk.Invoking(target => target.Add(new('$', "MORE", 0, 0, [1])))
            .Should().Throw<InvalidOperationException>().WithMessage("*catalogue is full*");

        disk.ToImage().Should().Equal(full);

        // A replacement needs no new entry, and goes where SAVE would put it: the first gap that holds it.
        disk.Add(new('$', "f3", 0x2000, 0x2000, new byte[300])).StartSector.Should().Be(33);
        disk.Entries.Should().HaveCount(AcornDfsDisk.MaximumFiles);
        (disk.Find('$', "F3") ?? throw new AssertFailedException("No F3.")).File.Name.Should().Be("f3");
        disk.Entries[0].File.Name.Should().Be("f3");

        disk.Remove('$', "F0").Should().BeTrue();
        disk.Add(new('L', "KEEP", 0, 0, [1], Locked: true)).StartSector.Should().Be(2);
        disk.Invoking(target => target.Add(new('l', "keep", 0, 0, [2])))
            .Should().Throw<InvalidOperationException>().WithMessage("*locked*");

        disk.Invoking(target => target.Remove('L', "KEEP")).Should().Throw<InvalidOperationException>();
    }

    /// <summary>
    ///  A file goes in the first gap that holds it, from sector 2 up, as SAVE puts it; one that no gap holds is
    ///  refused with the disk unchanged, even when the free sectors add up to enough.
    /// </summary>
    [TestMethod]
    public void SectorsAreAllocatedAsSaveDoes()
    {
        AcornDfsDisk disk = AcornDfsDisk.Create(40);
        disk.Add(new('$', "A", 0, 0, new byte[Sector])).StartSector.Should().Be(2);
        disk.Add(new('$', "B", 0, 0, new byte[Sector + 1])).StartSector.Should().Be(3);
        disk.Add(new('$', "C", 0, 0, new byte[Sector])).StartSector.Should().Be(5);
        disk.Remove('$', "B").Should().BeTrue();
        disk.Remove('$', "B").Should().BeFalse();

        // An empty file takes no sectors, so the gap before the lowest file holds it.
        disk.Add(new('$', "EMPTY", 0, 0, [])).StartSector.Should().Be(2);
        disk.Add(new('$', "D", 0, 0, new byte[Sector])).StartSector.Should().Be(3);
        disk.Add(new('$', "E", 0, 0, new byte[2 * Sector])).StartSector.Should().Be(6);
        disk.Entries.Select(entry => entry.File.Name).Should().Equal("E", "C", "D", "A", "EMPTY");

        // Sector 4 and sectors 8-399 are free: 393 sectors, but no gap of 393.
        disk.FreeSectors.Should().Be(393);
        byte[] before = disk.ToImage();
        disk.Invoking(target => target.Add(new('$', "HUGE", 0, 0, new byte[393 * Sector])))
            .Should().Throw<InvalidOperationException>().WithMessage("*disk is full*");

        disk.ToImage().Should().Equal(before);
        disk.Add(new('$', "FITS", 0, 0, new byte[392 * Sector])).StartSector.Should().Be(8);
        disk.Add(new('$', "ONE", 0, 0, [1])).StartSector.Should().Be(4);
        disk.FreeSectors.Should().Be(0);
    }

    /// <summary>
    ///  Changes move the entries they do not touch as raw bytes, as the DFS does: a name byte with bit 7 set and NUL
    ///  padding are kept, and *DELETE's freed slot takes the bytes past the last entry.
    /// </summary>
    [TestMethod]
    public void UntouchedEntriesKeepTheirBytes()
    {
        AcornDfsDisk disk = AcornDfsDisk.Create(40);
        disk.Add(new('$', "FIRST", 0, 0, [1]));
        disk.Add(new('$', "SECOND", 0, 0, [2]));
        byte[] image = disk.ToImage();

        // FIRST, now the second entry: bit 7 on a name character, and NUL padding.
        image[16] = (byte)('F' | 0x80);
        image[21] = 0;
        image[22] = 0;
        image.AsSpan(32, 8).Fill(0x5A);
        image.AsSpan(Sector + 32, 8).Fill(0xA5);
        disk = AcornDfsDisk.Read(image);
        disk.Add(new('$', "THIRD", 0, 0, [3])).StartSector.Should().Be(4);
        byte[] first = [0xC6, (byte)'I', (byte)'R', (byte)'S', (byte)'T', 0, 0, (byte)'$'];
        disk.ToImage().AsSpan(24, 8).ToArray().Should().Equal(first);

        // THIRD's removal moves SECOND and FIRST down, and the slot past them into FIRST's old place.
        disk.Remove('$', "THIRD").Should().BeTrue();
        image = disk.ToImage();
        image.AsSpan(16, 8).ToArray().Should().Equal(first);
        image[Sector + 5].Should().Be(16);
        image.AsSpan(24, 8).ToArray().Should().OnlyContain(value => value == 0x5A);
        image.AsSpan(Sector + 24, 8).ToArray().Should().OnlyContain(value => value == 0xA5);
        AcornDfsDisk.Read(image).Entries.Select(entry => entry.File.Name).Should().Equal("SECOND", "FIRST");
    }

    /// <summary>
    ///  Broken catalogues are refused when read.
    /// </summary>
    [TestMethod]
    public void BrokenCataloguesAreRefused()
    {
        byte[] image = AcornDfsDisk.Create(40).ToImage();
        FluentActions.Invoking(() => AcornDfsDisk.Read(image.AsSpan(0, Sector))).Should().Throw<InvalidDataException>();

        byte[] count = [.. image];
        count[Sector + 5] = 12;
        FluentActions.Invoking(() => AcornDfsDisk.Read(count)).Should().Throw<InvalidDataException>();

        byte[] outside = [.. image];
        outside[Sector + 5] = 8;
        outside[8] = (byte)'X';
        outside[15] = (byte)'$';
        outside[Sector + 13] = 2;
        outside[Sector + 15] = 0xFF;
        outside[Sector + 14] = 1;
        FluentActions.Invoking(() => AcornDfsDisk.Read(outside)).Should().Throw<InvalidDataException>();

        byte[] size = [.. image];
        size[Sector + 7] = 1;
        size[Sector + 6] = 0;
        FluentActions.Invoking(() => AcornDfsDisk.Read(size)).Should().Throw<InvalidDataException>();
    }

    /// <summary>
    ///  The Welcome disk reads as *CAT lists it, and writes back byte for byte.
    /// </summary>
    [TestMethod]
    public void WelcomeDiskReadsAndWritesBack()
    {
        byte[] welcome = BbcDiskTests.Welcome();
        AcornDfsDisk disk = AcornDfsDisk.Read(welcome);
        disk.Title.Should().Be("WELCOME-DISK");
        disk.BootOption.Should().Be(AcornBootOption.Exec);
        disk.Find('W', "WELCOME").Should().NotBeNull();
        disk.ToImage().AsSpan(0, welcome.Length).ToArray().Should().Equal(welcome);
    }

    /// <summary>
    ///  With SHIFT held as the machine starts, as a launch's <c>boot: true</c> holds it, DNFS *EXECs the writer's
    ///  !BOOT, whose *RUN loads and starts the program.
    /// </summary>
    [TestMethod]
    public void BootRunsTheProgram()
    {
        AcornDfsDisk disk = AcornDfsDisk.Create();
        disk.Title = "SDK TEST";
        disk.Add(new('$', "HELLO", 0x2000, 0x2000, s_hello));
        disk.AddBootFile("*RUN HELLO");

        BbcMachine machine = new(s_diskRoms.Value);
        machine.Drives[0].Insert(disk.ToDisk(), "sdk.ssd", "SSD");
        machine.Keyboard.HoldShift(BbcMachine.ShiftBreakCycles);
        machine.Run(TimeSpan.FromSeconds(6));
        string[] screen = machine.ReadTextScreen();
        screen.Should().Contain(line => line.TrimEnd() == "PROGRAM RAN OK", string.Join('\n', screen));
    }

    /// <summary>
    ///  DNFS's *CAT and *INFO show what the writer wrote: the title, the boot option, the lock, and addresses with
    ///  their high bits, the I/O processor's as &amp;FF, and the sequence number of six changes.
    /// </summary>
    [TestMethod]
    public void DnfsListsTheWritersFiles()
    {
        AcornDfsDisk disk = AcornDfsDisk.Create();
        disk.Title = "CATALOGUE";
        disk.Add(new('$', "HELLO", 0x2000, 0x2000, s_hello));
        disk.Add(new('B', "HIGH", 0xFFFF1900, 0xFFFF8023, new byte[0x10100], Locked: true));
        disk.Add(new('$', "SECOND", 0x12345, 0x2ABCD, [1, 2, 3]));
        disk.AddBootFile("*RUN HELLO");

        BbcMachine machine = new(s_diskRoms.Value);
        machine.Drives[0].Insert(disk.ToDisk(), "sdk.ssd", "SSD");
        BbcMachineTests.RunToPrompt(machine);
        string[] screen = BbcDiskTests.Command(machine, "*CAT\r*INFO *.*\r");
        string text = string.Join('\n', screen);
        screen.Should().Contain("CATALOGUE    (06)", text);
        screen.Should().Contain("Drive 0             Option 3 (EXEC)", text);
        screen.Should().Contain("  B.HIGH     L", text);
        screen.Should().Contain("$.!BOOT       000000 000000 00000B 105", text);
        screen.Should().Contain("$.SECOND      012345 02ABCD 000003 104", text);
        screen.Should().Contain("B.HIGH     L  FF1900 FF8023 010100 003", text);
        screen.Should().Contain("$.HELLO       002000 002000 00001F 002", text);
    }

    /// <summary>
    ///  DNFS saves a program onto a disk the writer made, after its files, and the writer reads both back.
    /// </summary>
    [TestMethod]
    public void DnfsSavesBesideTheWritersFiles()
    {
        AcornDfsDisk disk = AcornDfsDisk.Create();
        disk.Add(new('$', "HELLO", 0x2000, 0x2000, s_hello));

        BbcMachine machine = new(s_diskRoms.Value);
        machine.Drives[0].Insert(disk.ToDisk(), "sdk.ssd", "SSD");
        BbcMachineTests.RunToPrompt(machine);
        BbcDiskTests.Command(machine, "10 PRINT \"SAVED\"\rSAVE \"PROG\"\r*RUN HELLO\r");
        machine.ReadTextScreen().Should().Contain(line => line.TrimEnd() == "PROGRAM RAN OK");

        FloppyDisk saved = machine.Drives[0].Disk ?? throw new AssertFailedException("Drive 0 is empty.");
        AcornDfsDisk read = AcornDfsDisk.Read(new AcornDiskCodec().Encode(saved.Snapshot()).Bytes);
        var placed = read.Entries.Select(entry => (entry.File.FullName, entry.StartSector));
        placed.Should().Equal(("$.PROG", 3), ("$.HELLO", 2));
        AcornDfsEntry program = read.Find('$', "PROG") ?? throw new AssertFailedException("No PROG.");
        program.File.LoadAddress.Should().Be(0xFFFF1900);
        read.SequenceNumber.Should().Be(0x02, "the writer's one change and SAVE's");
    }

    /// <summary>
    ///  A UEF tape of a file reads back as the tape it was built from, and the MOS's tape loader *RUNs the file.
    /// </summary>
    [TestMethod]
    public void UefTapeRunsTheProgram()
    {
        AcornTapeFile[] files = [new("HELLO", 0x2000, 0x2000, s_hello)];
        byte[] uef = AcornTapeBuilder.BuildUef(files);
        UefFormat.IsUef(uef).Should().BeTrue();
        AcornTape tape = UefFormat.Read(uef);
        tape.HalfCycles.Should().Equal(AcornTapeBuilder.Build(files).HalfCycles);

        BbcMachine machine = new(s_tapeRoms.Value, diskInterface: false);
        BbcMachineTests.RunToPrompt(machine);
        machine.Cassette.Insert(tape, "hello.uef");
        machine.Cassette.Play();
        BbcMachineTests.Type(machine, "*RUN HELLO\r");
        machine.Run(TimeSpan.FromSeconds(15));
        string[] screen = machine.ReadTextScreen();
        screen.Should().Contain(line => line.TrimEnd() == "PROGRAM RAN OK", string.Join('\n', screen));
    }
}
