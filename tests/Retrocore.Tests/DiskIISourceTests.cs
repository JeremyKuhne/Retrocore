// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using System.Security.Cryptography;
using Retrocore.Assembler;
using Retrocore.Debug;
using Retrocore.Machines.Apple2;
using Retrocore.Media;

namespace Retrocore.Tests;

/// <summary>
///  Verifies the SDK's sources for the Disk II controller's boot ROMs and sequencers.
/// </summary>
[TestClass]
public sealed class DiskIISourceTests
{
    private static readonly string s_inputs = Path.Join(AppContext.BaseDirectory, "Inputs");

    /// <summary>
    ///  Each source builds byte-identically to its chip, pinned by digest so no ROM is needed.
    /// </summary>
    /// <param name="file">The source.</param>
    /// <param name="origin">Its first address.</param>
    /// <param name="expectedHash">The SHA-256 of the chip.</param>
    [TestMethod]
    [DataRow("Boot16.asm", 0xC600, "DE1E3E035878BAB43D0AF8FE38F5839C527E9548647036598EE6FE7EC74D2A7D")]
    [DataRow("Sequencer16.asm", 0, "E5E30615040567C1E7A2D21599681F8DAC820EDBDCDA177B816A64D74B3A12F2")]
    [DataRow("Boot13.asm", 0xC600, "2D2599521FC5763D4E8C308C2EE7C5C4D5C93785B8FB9A4F7D0381DFD5EB60B6")]
    [DataRow("Sequencer13.asm", 0, "4234AED053C622B266014C4E06AB1CE9E0E085D94A28512AA4030462BE0A3CB9")]
    public void SourceMatchesTheChip(string file, int origin, string expectedHash)
    {
        AssemblyResult result = SdkModules.AssembleDiskII(SdkModules.DiskIIPath(file, s_inputs), origin);

        result.Diagnostics.Should().BeEmpty();
        result.Sections[0].Bytes.Length.Should().Be(SdkModules.DiskIIRomSize);
        Convert.ToHexString(SHA256.HashData(result.Sections[0].Bytes.Span)).Should().Be(expectedHash);
    }

    /// <summary>
    ///  With the chips in <c>%USERPROFILE%\Retrocore\disk2-roms</c> (or <c>RETROCORE_DISKII_ROMS</c>), under
    ///  their apple2.org.za names, each source also compares byte for byte, which names the first difference. The
    ///  341-0010 dump was read from the boot ROM's socket, so its bytes are first put back in the chip's order.
    /// </summary>
    /// <param name="file">The source.</param>
    /// <param name="origin">Its first address.</param>
    /// <param name="chip">The chip's file name.</param>
    /// <param name="bootSocket">Whether the dump was read from the boot ROM's socket.</param>
    [TestMethod]
    [DataRow("Boot16.asm", 0xC600, "Apple Disk II 16 Sector Interface Card ROM P5 - 341-0027.bin", false)]
    [DataRow("Sequencer16.asm", 0, "Apple Disk II 16 Sector Interface Card ROM P6 - 341-0028.bin", false)]
    [DataRow("Boot13.asm", 0xC600, "Apple Disk II 13 Sector Interface Card ROM P5 - 341-0009.bin", false)]
    [DataRow("Sequencer13.asm", 0, "Apple Disk II 13 Sector Interface Card ROM P6 - 341-0010.bin", true)]
    public void SourceMatchesTheDump(string file, int origin, string chip, bool bootSocket)
    {
        string directory = Environment.GetEnvironmentVariable("RETROCORE_DISKII_ROMS")
            ?? Path.Join(ExternalTestData.Root, "disk2-roms");

        string path = Path.Join(directory, chip);
        if (!File.Exists(path)) { Assert.Inconclusive($"The Disk II chip dump ({path}) is missing."); }

        byte[] expected = File.ReadAllBytes(path);
        if (bootSocket)
        {
            byte[] dump = expected;
            expected = [.. Enumerable.Range(0, dump.Length).Select(address => DiskIIFirmware.FromBootSocket(dump, address))];
        }

        ReadOnlySpan<byte> actual = SdkModules.AssembleDiskII(SdkModules.DiskIIPath(file, s_inputs), origin).Sections[0].Bytes.Span;
        int first = actual.CommonPrefixLength(expected);
        first.Should().Be(expected.Length, $"the first difference is at offset ${first:X2}");
    }

    /// <summary>
    ///  A IIe built entirely from the SDK, with its 16-sector Disk II, boots a disk: the boot scan finds slot six,
    ///  the boot ROM seeks to track 0 and reads sector 0 into $0800, and runs it with X = $60.
    /// </summary>
    [TestMethod]
    public void BuiltDiskIIBootsADisk()
    {
        // A DOS-order image whose boot sector stores X and a mark, then waits.
        byte[] image = new byte[35 * 16 * 256];
        byte[] boot =
        [
            0x01,                   // one sector to read
            0x86, 0x06,             // stx $06
            0xA9, 0xA5,             // lda #$A5
            0x85, 0x07,             // sta $07
            0x4C, 0x07, 0x08        // jmp $0807
        ];

        boot.CopyTo(image, 0);
        Apple2Machine machine = new(Apple2Model.IIeEnhanced, SdkModules.BuildRoms(Apple2Model.IIeEnhanced, s_inputs));
        machine.Bus.DiskII.SetFirmware(SdkModules.BuildDiskII(sectors: 16, s_inputs));
        machine.Drives[0].Insert(SectorDiskConverter.Convert(image, proDosOrder: false), "boot", "DSK");

        machine.Bus.Peek(0xC6FF).Should().Be(0x00, "the 16-sector boot ROM is in slot six");
        for (int second = 0; second < 5 && machine.Bus.Peek(0x07) != 0xA5; second++)
        {
            machine.Run(BasicMachines.IIeClock);
        }

        machine.Bus.Peek(0x07).Should().Be(0xA5, "the boot sector ran");
        machine.Bus.Peek(0x06).Should().Be(0x60, "the boot ROM passes slot * 16 in X");
    }

    /// <summary>
    ///  With the DOS 3.2 System Master in <c>%USERPROFILE%\Retrocore\iie-disks</c>, a IIe built from the SDK, with
    ///  its 13-sector Disk II, boots it to AppleSoft's prompt: the 13-sector sequencer reads 5-and-3 nibbles, and
    ///  the boot ROM hands the boot sector to $0301.
    /// </summary>
    [TestMethod]
    public void Built13SectorDiskIIBootsDos32()
    {
        string path = Path.Join(ExternalTestData.Root, "iie-disks", "DOS 3.2 System Master.woz");
        if (!File.Exists(path)) { Assert.Inconclusive($"The DOS 3.2 System Master ({path}) is missing."); }

        Apple2Machine machine = new(Apple2Model.IIeEnhanced, SdkModules.BuildRoms(Apple2Model.IIeEnhanced, s_inputs));
        machine.Bus.DiskII.SetFirmware(SdkModules.BuildDiskII(sectors: 13, s_inputs));
        machine.Drives[0].Insert(WozDisk.Load(File.ReadAllBytes(path)), "DOS 3.2", "WOZ");
        for (int second = 0; second < 15 && !HasPrompt(machine); second++)
        {
            machine.Run(BasicMachines.IIeClock);
        }

        machine.Bus.Peek(0xC6FF).Should().Be(0xFF, "the 13-sector boot ROM is in slot six");
        machine.Bus.Peek(0x0300).Should().Be(0x99, "the boot sector was read");
        HasPrompt(machine).Should().BeTrue("DOS 3.2 loaded and AppleSoft is waiting at its prompt");
    }

    // A line of the text screen starts with AppleSoft's ] prompt.
    private static bool HasPrompt(Apple2Machine machine) =>
        Enumerable.Range(0, 24).Any(row => machine.Bus.Peek((ushort)(0x0400 + (row % 8 * 128) + (row / 8 * 40))) == 0xDD);

    /// <summary>
    ///  The boot ROM debugs at its own lines while it is the one in slot six.
    /// </summary>
    [TestMethod]
    public void BootRomDebugsAtItsLines()
    {
        Apple2Machine machine = new(Apple2Model.IIeEnhanced, SdkModules.BuildRoms(Apple2Model.IIeEnhanced, s_inputs));
        machine.Bus.DiskII.SetFirmware(SdkModules.BuildDiskII(sectors: 16, s_inputs));
        DebugInfo debug = new();
        SdkModules.AddTo(debug, Apple2Model.IIeEnhanced, s_inputs);

        string boot = SdkModules.DiskIIPath("Boot.asm", s_inputs);
        debug.Resolve("READ").Should().Be(0xC65C);
        DebugPosition? position = debug.Position(new Apple2TestMemory(machine.Bus), 0xC65C);
        SourceLine line = position?.Chain[0] ?? throw new AssertFailedException("No source for READ.");
        line.Path.Should().Be(Path.GetFullPath(boot));
        File.ReadAllLines(boot)[line.Line - 2].Should().Be("READ:");
    }
}
