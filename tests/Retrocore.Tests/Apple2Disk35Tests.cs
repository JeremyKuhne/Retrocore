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
///  Verifies the 3.5 disk controller: the source of Apple's card's EPROM, the emulator's firmware against it, booting,
///  and SmartPort and ProDOS calls run on the emulated CPU.
/// </summary>
[TestClass]
public sealed class Apple2Disk35Tests
{
    private const int Slot = 5;
    private const ushort Caller = 0x2000;
    private const ushort List = 0x2100;
    private const ushort Buffer = 0x3000;
    private static readonly string s_inputs = Path.Join(AppContext.BaseDirectory, "Inputs");
    private static readonly string s_source = Path.Join(s_inputs, "Disk35", "Disk35Controller.asm");
    private static readonly Lazy<Apple2Roms> s_roms = new(() => SdkModules.BuildRoms(Apple2Model.IIeEnhanced, s_inputs));
    private static readonly Lazy<byte[]> s_apple = new(Assemble);

    /// <summary>
    ///  The source builds byte-identically to the 341-0438-A EPROM, pinned by digest so no dump is needed.
    /// </summary>
    [TestMethod]
    public void SourceMatchesTheChip()
    {
        s_apple.Value.Length.Should().Be(0x8000);
        Convert.ToHexString(SHA256.HashData(s_apple.Value))
            .Should().Be("084587835C1D2C92F5708A9745FDD43BA32136FCDB861A12EE7D690DE22DC172");
    }

    /// <summary>
    ///  With the chip in <c>%USERPROFILE%\Retrocore\superdrive-roms</c> (or <c>RETROCORE_SUPERDRIVE_ROMS</c>), the source
    ///  also compares byte for byte, which names the first difference.
    /// </summary>
    [TestMethod]
    public void SourceMatchesTheDump()
    {
        string directory = Environment.GetEnvironmentVariable("RETROCORE_SUPERDRIVE_ROMS") ?? Path.Join(ExternalTestData.Root, "superdrive-roms");
        string path = Path.Join(directory, "341-0438-A.bin");
        if (!File.Exists(path))
        {
            Assert.Inconclusive($"The 3.5 controller's EPROM dump ({path}) is missing.");
        }


        byte[] expected = File.ReadAllBytes(path);
        int first = s_apple.Value.AsSpan().CommonPrefixLength(expected);
        first.Should().Be(expected.Length, $"the first difference is at ${0x8000 + first:X4}");
    }

    /// <summary>
    ///  The emulator's firmware has the identification bytes and entry offsets of the slot page Apple's card copies out
    ///  of its EPROM at $8100, so a program that finds Apple's card finds this one.
    /// </summary>
    [TestMethod]
    public void FirmwareIdentifiesAsApplesCard()
    {
        ReadOnlySpan<byte> apple = s_apple.Value.AsSpan(0x100, 0x100);
        ReadOnlySpan<byte> ours = Disk35Rom.Bytes;
        foreach (int offset in (ReadOnlySpan<int>)[0x01, 0x03, 0x05, 0x07, 0xFB, 0xFC, 0xFD, 0xFE, 0xFF])
        {
            ours[offset].Should().Be(apple[offset], $"$Cn{offset:X2} identifies the card");
        }

        (Disk35Rom.PRODOS & 0xFF).Should().Be(0x1C);
        (Disk35Rom.SMARTPORT & 0xFF).Should().Be(0x1F);
        (Disk35Rom.DIAG & 0xFF).Should().Be(0x0D);
    }

    /// <summary>
    ///  With slot 6 empty, the IIe's startup scan finds the card in slot 5 and boots drive 1's disk: block 0 runs at
    ///  $0801 with X = $50 and ProDOS's page zero set as for the read.
    /// </summary>
    [TestMethod]
    public void BootsThroughTheStartupScan()
    {
        Apple2Machine machine = Machine();
        machine.Bus.Disk35.Drives[0].Insert(BootDisk(Disk35Format.Gcr800), "boot", "PO");
        machine.Reset();
        for (int second = 0; second < 5 && machine.Bus.Peek(0x07) != 0xA5; second++)
        {
            machine.Run(BasicMachines.IIeClock);
        }

        machine.Bus.Peek(0x07).Should().Be(0xA5, "the boot block ran");
        machine.Bus.Peek(0x06).Should().Be(0x50, "the boot passes slot * 16 in X");
        machine.Bus.Peek(0x42).Should().Be(1);
        machine.Bus.Peek(0x43).Should().Be(0x50);
        machine.Bus.Peek(0x45).Should().Be(0x08);
    }

    /// <summary>
    ///  A drive with no boot block goes on to the next slot when the scan brought the boot there, as Apple's card does:
    ///  with nothing else to boot, the IIe ends in BASIC.
    /// </summary>
    [TestMethod]
    public void AnEmptyDriveLetsTheScanGoOn()
    {
        Apple2Machine machine = Machine();
        machine.Reset();
        machine.Run(BasicMachines.IIeClock * 2);
        machine.Bus.Peek(0x0488).Should().NotBe((byte)'U' | 0x80, "the scan, not the card, decides what happens next");
    }

    /// <summary>
    ///  Called directly with the Monitor's slot pointer elsewhere, a failed boot says so, as Apple's card does.
    /// </summary>
    [TestMethod]
    public void AFailedBootSaysUnableToBoot()
    {
        Apple2Machine machine = Machine();
        machine.Bus.SetRam(auxiliary: false, 0x00, 0x00);
        machine.Bus.SetRam(auxiliary: false, 0x01, 0xC6);
        Run(machine, 0xC500, until: pc => pc == 0xE000);
        Text(machine, 0x0488, 14).Should().Be("UNABLE TO BOOT");
    }

    /// <summary>
    ///  STATUS answers as Apple's card does: for unit 0 the unit count and the controller's name; for each drive its
    ///  status (online and writable with an 800K disk) and its 1600 blocks, and the SuperDrive's device information
    ///  block, whose name is "DISK 3.5" with "HD" past its length, subtype $C1 and version $1010. A third unit is $11.
    /// </summary>
    [TestMethod]
    public void StatusDescribesTheDrives()
    {
        Apple2Machine machine = Machine();
        machine.Bus.Disk35.Drives[0].Insert(Disk35Disk.Blank(Disk35Format.Gcr800), "data", "PO");

        SmartPort(machine, command: 0, [3, 0, Buffer & 0xFF, Buffer >> 8, 0]).Accumulator.Should().Be(0);
        machine.Bus.Peek(Buffer).Should().Be(2, "two drives");
        SmartPort(machine, command: 0, [3, 0, Buffer & 0xFF, Buffer >> 8, 1]).X.Should().Be(31);
        Text(machine, Buffer + 1, 30).Should().Be("APPLE UNIVERSAL 3.5 CONTROLLER");

        ProcessorRegisters status = SmartPort(machine, command: 0, [3, 1, Buffer & 0xFF, Buffer >> 8, 0]);
        status.Accumulator.Should().Be(0);
        status.X.Should().Be(4, "four bytes");
        machine.Bus.Peek(Buffer).Should().Be(0xF8, "a block device, online, read, write and format");
        Word(machine, Buffer + 1).Should().Be(1600);

        SmartPort(machine, command: 0, [3, 1, Buffer & 0xFF, Buffer >> 8, 3]).X.Should().Be(25);
        Text(machine, Buffer + 5, machine.Bus.Peek(Buffer + 4)).Should().Be("DISK 3.5");
        Text(machine, Buffer + 5, 16).Should().Be("DISK 3.5HD      ");
        machine.Bus.Peek(Buffer + 21).Should().Be(0x01, "a 3.5-inch disk");
        machine.Bus.Peek(Buffer + 22).Should().Be(0xC1);
        Word(machine, Buffer + 23).Should().Be(0x1010);
        SmartPort(machine, command: 0, [3, 1, Buffer & 0xFF, Buffer >> 8, 1]).Accumulator.Should().Be(0x21, "no DCB");

        SmartPort(machine, command: 0, [3, 2, Buffer & 0xFF, Buffer >> 8, 0]).Accumulator.Should().Be(0);
        (machine.Bus.Peek(Buffer) & 0x10).Should().Be(0, "drive 2 is empty");
        SmartPort(machine, command: 0, [3, 3, Buffer & 0xFF, Buffer >> 8, 0]).Accumulator.Should().Be(0x11, "no third drive");
    }

    /// <summary>
    ///  WRITEBLOCK and READBLOCK move 512 bytes, with X and Y the count; a write-protected disk refuses a write with
    ///  $2B, a block past the end is $2D, and the wrong parameter count is $04.
    /// </summary>
    [TestMethod]
    public void ReadsAndWritesBlocks()
    {
        Apple2Machine machine = Machine();
        Disk35Disk disk = Disk35Disk.Blank(Disk35Format.Mfm1440);
        machine.Bus.Disk35.Drives[1].Insert(disk, "data", "PO");
        Poke(machine, Buffer, [.. Enumerable.Range(0, 512).Select(i => (byte)i)]);

        ProcessorRegisters write = SmartPort(machine, command: 2, [3, 2, Buffer & 0xFF, Buffer >> 8, 0x3F, 0x0B, 0]);
        write.Accumulator.Should().Be(0);
        (write.X | (write.Y << 8)).Should().Be(512);
        write.Status.HasFlag(StatusRegister.Carry).Should().BeFalse();
        machine.Bus.Disk35.Drives[1].Media?.Changed.Should().BeTrue();

        Poke(machine, Buffer, new byte[512]);
        SmartPort(machine, command: 1, [3, 2, Buffer & 0xFF, Buffer >> 8, 0x3F, 0x0B, 0]).Accumulator.Should().Be(0);
        machine.Bus.Peek(Buffer + 0x1FF).Should().Be(0xFF);

        ProcessorRegisters past = SmartPort(machine, command: 1, [3, 2, Buffer & 0xFF, Buffer >> 8, 0x40, 0x0B, 0]);
        past.Accumulator.Should().Be(0x2D);
        past.Status.HasFlag(StatusRegister.Carry).Should().BeTrue();

        disk.IsReadOnly = true;
        SmartPort(machine, command: 2, [3, 2, Buffer & 0xFF, Buffer >> 8, 0, 0, 0]).Accumulator.Should().Be(0x2B);
        SmartPort(machine, command: 1, [2, 2, Buffer & 0xFF, Buffer >> 8, 0, 0, 0]).Accumulator.Should().Be(0x04);
        SmartPort(machine, command: 0x0C, [3, 2, Buffer & 0xFF, Buffer >> 8, 0]).Accumulator.Should().Be(0x01);
    }

    /// <summary>
    ///  An extended READBLOCK takes a four-byte list address and buffer and a four-byte block, and returns past the
    ///  five bytes after its JSR. As on Apple's card, the first extended call after a disk goes in says so with $2E,
    ///  and extended status shows it in bit 0 until then.
    /// </summary>
    [TestMethod]
    public void ExtendedCallsReadBlocks()
    {
        Apple2Machine machine = Machine();
        Disk35Disk disk = Disk35Disk.Blank(Disk35Format.Gcr800);
        byte[] block = new byte[512];
        block[7] = 0x77;
        disk.WriteBlock(1599, block);
        machine.Bus.Disk35.Drives[0].Insert(disk, "data", "PO");

        SmartPort(machine, command: 0x40, [3, 1, Buffer & 0xFF, Buffer >> 8, 0, 0, 0]).X.Should().Be(5);
        machine.Bus.Peek(Buffer).Should().Be(0xF9, "online, and the disk changed");
        int[] read = [3, 1, Buffer & 0xFF, Buffer >> 8, 0, 0, 0x3F, 0x06, 0, 0];
        SmartPort(machine, command: 0x41, read).Accumulator.Should().Be(0x2E, "the disk changed");
        SmartPort(machine, command: 0x41, read).Accumulator.Should().Be(0);
        machine.Bus.Peek(Buffer + 7).Should().Be(0x77);
    }

    /// <summary>
    ///  CONTROL code 4 ejects the disk; a code Apple's card does not take is $21, and a list of $400 bytes or more $22.
    /// </summary>
    [TestMethod]
    public void ControlEjects()
    {
        Apple2Machine machine = Machine();
        Apple2Disk35Drive drive = machine.Bus.Disk35.Drives[0];
        drive.Insert(Disk35Disk.Blank(Disk35Format.Gcr800), "data", "PO");
        machine.Bus.SetRam(auxiliary: false, Buffer, 0);
        machine.Bus.SetRam(auxiliary: false, Buffer + 1, 0);
        SmartPort(machine, command: 4, [3, 1, Buffer & 0xFF, Buffer >> 8, 4]).Accumulator.Should().Be(0);
        drive.Disk.Should().BeNull();
        drive.EjectedByProgram.Should().BeTrue();
        SmartPort(machine, command: 4, [3, 1, Buffer & 0xFF, Buffer >> 8, 1]).Accumulator.Should().Be(0x21);
        machine.Bus.SetRam(auxiliary: false, Buffer + 1, 4);
        SmartPort(machine, command: 4, [3, 1, Buffer & 0xFF, Buffer >> 8, 0]).Accumulator.Should().Be(0x22);
    }

    /// <summary>
    ///  Command $0A takes the format from the buffer, as many bytes as its count says: the kind (0, or even and below
    ///  $0D), a 0, then an interleave below $0D. A count of 0 is the disk's own format.
    /// </summary>
    [TestMethod]
    public void SetFormatReadsItsBuffer()
    {
        Apple2Machine machine = Machine();
        machine.Bus.Disk35.Drives[0].Insert(Disk35Disk.Blank(Disk35Format.Gcr800), "data", "PO");
        byte SetFormat(byte[] payload)
        {
            Poke(machine, Buffer, payload);
            return SmartPort(machine, command: 0x0A, [3, 1, Buffer & 0xFF, Buffer >> 8, payload.Length]).Accumulator;
        }

        SetFormat([]).Should().Be(0);
        SetFormat([0x02]).Should().Be(0, "a one-byte buffer holds the kind");
        SetFormat([0x04, 0x00, 0x0C]).Should().Be(0);
        SetFormat([0x03]).Should().Be(0x21, "an odd kind");
        SetFormat([0x0E]).Should().Be(0x21, "a kind past $0C");
        SetFormat([0x04, 0x01]).Should().Be(0x21, "the second byte must be 0");
        SetFormat([0x04, 0x00, 0x0D]).Should().Be(0x21, "an interleave of 13");
    }

    /// <summary>
    ///  CONTROL $00 looks at the disk again, as Apple's checks it: $2F with no disk, and a disk that went in since
    ///  taken, with $2E for an extended call.
    /// </summary>
    [TestMethod]
    public void ControlResetChecksTheDisk()
    {
        Apple2Machine machine = Machine();
        Poke(machine, Buffer, [0, 0]);
        int[] reset = [3, 1, Buffer & 0xFF, Buffer >> 8, 0];
        SmartPort(machine, command: 4, reset).Accumulator.Should().Be(0x2F, "no disk");

        machine.Bus.Disk35.Drives[0].Insert(Disk35Disk.Blank(Disk35Format.Gcr800), "data", "PO");
        SmartPort(machine, command: 0x44, [3, 1, Buffer & 0xFF, Buffer >> 8, 0, 0, 0]).Accumulator.Should().Be(0x2E);
        SmartPort(machine, command: 0x44, [3, 1, Buffer & 0xFF, Buffer >> 8, 0, 0, 0]).Accumulator.Should().Be(0);
        SmartPort(machine, command: 4, reset).Accumulator.Should().Be(0);
    }

    /// <summary>
    ///  ProDOS's calls: this slot's drive 2 is unit $D0; status gives the block count in X and Y, and $2B for a
    ///  write-protected disk; an empty drive is $2F; a unit ProDOS mapped to slot 2 is SmartPort's unit 3, which is
    ///  not there ($28).
    /// </summary>
    [TestMethod]
    public void ProDOSCallsMapUnitsAndErrors()
    {
        Apple2Machine machine = Machine();
        Disk35Disk disk = Disk35Disk.Blank(Disk35Format.Gcr800);
        machine.Bus.Disk35.Drives[1].Insert(disk, "data", "PO");

        ProcessorRegisters status = ProDOS(machine, command: 0, unit: 0xD0);
        status.Accumulator.Should().Be(0);
        (status.X | (status.Y << 8)).Should().Be(1600);

        disk.IsReadOnly = true;
        ProDOS(machine, command: 0, unit: 0xD0).Accumulator.Should().Be(0x2B);
        ProDOS(machine, command: 1, unit: 0xD0).Accumulator.Should().Be(0);
        ProDOS(machine, command: 2, unit: 0xD0).Accumulator.Should().Be(0x2B);
        ProDOS(machine, command: 1, unit: 0x50).Accumulator.Should().Be(0x2F, "drive 1 is empty");
        ProDOS(machine, command: 1, unit: 0x20).Accumulator.Should().Be(0x28, "slot 2 stands for unit 3");
        ProDOS(machine, command: 4, unit: 0x50).Accumulator.Should().Be(0x01);
    }

    /// <summary>
    ///  ProDOS 8 boots from A2DeskTop's 800K disk in drive 1 and finds both drives in its device list: $50 and $D0, each
    ///  with ProDOS's device code in its low nibble.
    /// </summary>
    [TestMethod]
    public void BootsProDOSFromAn800KDisk()
    {
        string path = Path.Join(ExternalTestData.Root, "disks", "a2desktop", "A2DeskTop-1.5-en_800k.po");
        if (!File.Exists(path)) { Assert.Inconclusive($"A2DeskTop's 800K disk ({path}) is missing."); }

        Apple2Machine machine = Machine();
        machine.Bus.Disk35.Drives[0].Insert(Disk35Disk.Load(File.ReadAllBytes(path), writeProtected: true), path, "PO");
        machine.Bus.Disk35.Drives[1].Insert(Disk35Disk.Blank(Disk35Format.Gcr800), "blank", "PO");
        machine.Reset();
        for (int tenth = 0; tenth < 50 && !DeviceList(machine).Contains((byte)0xD0); tenth++)
        {
            machine.Run(BasicMachines.IIeClock / 10);
        }

        DeviceList(machine).Should().Contain((byte[])[0x50, 0xD0]);
    }

    // ProDOS's device list, $BF32 for $BF31 + 1 entries, each its slot and drive alone.
    private static byte[] DeviceList(Apple2Machine machine)
    {
        int count = machine.Bus.Peek(0xBF31) + 1;
        return count > 14 ? [] : [.. Enumerable.Range(0, count).Select(i => (byte)(machine.Bus.Peek((ushort)(0xBF32 + i)) & 0xF0))];
    }

    private static Apple2Machine Machine()
    {
        Apple2Machine machine = new(Apple2Model.IIeEnhanced, s_roms.Value);
        machine.Run(cycles: 7);
        machine.Bus.InstallDisk35(Slot);
        return machine;
    }

    // A disk whose block 0 stores X and a mark, then waits.
    private static Disk35Disk BootDisk(Disk35Format format)
    {
        Disk35Disk disk = Disk35Disk.Blank(format);
        byte[] block = new byte[512];
        byte[] boot =
        [
            0x01,                   // a ProDOS boot block
            0x86, 0x06,             // stx $06
            0xA9, 0xA5,             // lda #$A5
            0x85, 0x07,             // sta $07
            0x4C, 0x07, 0x08        // jmp $0807
        ];

        boot.CopyTo(block, 0);
        disk.WriteBlock(0, block);
        return disk;
    }

    // Calls the SmartPort entry with the command and a parameter list, and returns the registers.
    private static ProcessorRegisters SmartPort(Apple2Machine machine, byte command, int[] list)
    {
        // An extended call's list address takes four bytes.
        int length = (command & 0x40) != 0 ? 8 : 6;
        byte[] call = [0x20, 0x1F, 0xC0 | Slot, command, List & 0xFF, List >> 8, 0, 0];
        call = call[..length];
        Poke(machine, Caller, call);
        Poke(machine, List, [.. list.Select(value => (byte)value)]);
        return Run(machine, Caller, until: pc => pc == Caller + call.Length);
    }

    // Calls the ProDOS entry with a command and unit for block 0 at the buffer.
    private static ProcessorRegisters ProDOS(Apple2Machine machine, byte command, byte unit)
    {
        byte[] page = [command, unit, Buffer & 0xFF, Buffer >> 8, 0, 0];
        Poke(machine, 0x42, page);
        byte[] call = [0x20, 0x1C, 0xC0 | Slot];
        Poke(machine, Caller, call);
        return Run(machine, Caller, until: pc => pc == Caller + call.Length);
    }

    private static void Poke(Apple2Machine machine, ushort address, byte[] bytes)
    {
        for (int i = 0; i < bytes.Length; i++)
        {
            machine.Bus.SetRam(auxiliary: false, (ushort)(address + i), bytes[i]);
        }
    }

    private static ProcessorRegisters Run(Apple2Machine machine, ushort start, Func<ushort, bool> until)
    {
        machine.Processor.Registers = new()
        {
            ProgramCounter = start,
            StackPointer = 0xF0,
            Status = StatusRegister.Unused
        };

        for (int i = 0; i < 100_000; i++)
        {
            machine.StepInstruction().Status.Should().Be(ProcessorExecutionStatus.InstructionComplete);
            if (until(machine.Processor.Registers.ProgramCounter)) { return machine.Processor.Registers; }
        }

        throw new InvalidOperationException($"The call from ${start:X4} did not return.");
    }

    private static int Word(Apple2Machine machine, int address) =>
        machine.Bus.Peek((ushort)address) | (machine.Bus.Peek((ushort)(address + 1)) << 8);

    private static string Text(Apple2Machine machine, int address, int length) =>
        new([.. Enumerable.Range(0, length).Select(i => (char)(machine.Bus.Peek((ushort)(address + i)) & 0x7F))]);

    private static byte[] Assemble()
    {
        AssemblyOptions options = new(ProcessorVariant.Wdc65C02, origin: 0x8000, 0x8000)
        {
            SourceResolver = new FileAssemblySourceResolver()
        };

        AssemblyResult result = new Assembler.Assembler().Assemble(new AssemblySource(File.ReadAllText(s_source), s_source), options);
        result.Diagnostics.Should().BeEmpty();
        return result.Sections[0].Bytes.ToArray();
    }
}
