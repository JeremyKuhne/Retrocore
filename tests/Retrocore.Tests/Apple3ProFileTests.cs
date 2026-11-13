// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using Retrocore.Assembler;
using Retrocore.Machines.Apple2;
using Retrocore.Machines.Apple3;
using Retrocore.Media;

namespace Retrocore.Tests;

/// <summary>
///  Verifies the Apple III's ProFile card and drive by running Apple's own SOS driver, .PROFILE 1.30, built from the
///  SDK's source, on the emulated III with the SDK's boot ROM, whose <c>$F800</c> chain the driver's pseudo-DMA uses.
/// </summary>
/// <remarks>
///  <para>
///   SOS itself does not run: the driver sits at <c>$8000</c>, its request goes in SOS's driver parameters at
///   <c>$C0-$C9</c> of the kernel's zero page (<c>$1800</c>), and stubs stand in for the kernel entries it calls.
///   SYSERR records the error and stops. Buffers at every alignment exercise each of the driver's paths: the
///   pseudo-DMA alone, bytes moved one at a time around it, and the short last page whose bytes 0 and <c>$FE</c> it
///   keeps aside.
///  </para>
/// </remarks>
[TestClass]
public sealed class Apple3ProFileTests
{
    private const int Slot = 4;
    private const ushort DriverOrigin = 0x8000;
    private const ushort Caller = 0x1A20;
    private const ushort Done = Caller + 3;
    private const ushort Failed = 0x1A10;
    private const ushort ErrorCode = 0x1A00;
    private const ushort ParameterBase = 0x18C0;
    private const ushort BytesRead = 0x1A30;
    private const uint Blocks = 1024;

    private const byte ReadRequest = 0;
    private const byte WriteRequest = 1;
    private const byte StatusRequest = 2;
    private const byte InitializeRequest = 8;

    private static readonly Lazy<byte[]> s_rom = new(() =>
        Apple3RomSourceTests.Assemble().Sections[0].Bytes.ToArray());

    private static readonly Lazy<byte[]> s_driver = new(() => DriverCode(DriverOrigin));

    /// <summary>
    ///  The driver initializes, finds the ProFile and reads blocks into buffers at every kind of alignment, leaving
    ///  the bytes on either side alone.
    /// </summary>
    /// <param name="buffer">The buffer's address.</param>
    /// <param name="blocks">The blocks to read.</param>
    [TestMethod]
    [DataRow(0x2000, 2)]
    [DataRow(0x3011, 1)]
    [DataRow(0x3080, 1)]
    [DataRow(0x30F7, 1)]
    [DataRow(0x30FE, 1)]
    [DataRow(0x3042, 3)]
    [DataRow(0x30E1, 1)]
    [DataRow(0x3001, 2)]
    public void ReadsBlocks(int buffer, int blocks)
    {
        (Apple3Machine machine, MemoryBlockDevice image) = Machine();
        Initialize(machine);

        Fill(machine, (ushort)(buffer - 16), (blocks * 512) + 32, 0xA5);
        Request(machine, ReadRequest, (ushort)buffer, (ushort)(blocks * 512), block: 5).Should().Be(0);

        byte[] expected = new byte[blocks * 512];
        for (int i = 0; i < blocks; i++) { image.ReadBlock((uint)(5 + i), expected.AsSpan(i * 512, 512)); }
        Bytes(machine, (ushort)buffer, expected.Length).Should().Equal(expected);
        Bytes(machine, (ushort)(buffer - 16), 16).Should().AllBeEquivalentTo((byte)0xA5);
        Bytes(machine, (ushort)(buffer + expected.Length), 16).Should().AllBeEquivalentTo((byte)0xA5);
        Word(machine, BytesRead).Should().Be(blocks * 512, "the driver counts the bytes it read");
    }

    /// <summary>
    ///  The driver writes blocks from buffers at every kind of alignment, verified as its configuration asks, and they
    ///  read back, leaving the buffer as it was.
    /// </summary>
    /// <param name="buffer">The buffer's address.</param>
    /// <param name="blocks">The blocks to write.</param>
    [TestMethod]
    [DataRow(0x2000, 2)]
    [DataRow(0x3011, 1)]
    [DataRow(0x3080, 1)]
    [DataRow(0x30F7, 1)]
    [DataRow(0x3042, 3)]
    [DataRow(0x30E1, 1)]
    public void WritesBlocks(int buffer, int blocks)
    {
        (Apple3Machine machine, MemoryBlockDevice image) = Machine();
        Initialize(machine);

        byte[] data = new byte[blocks * 512];
        for (int i = 0; i < data.Length; i++) { data[i] = (byte)((i * 31) ^ (i >> 9) ^ 0x5A); }
        for (int i = 0; i < data.Length; i++) { Poke(machine, (ushort)(buffer + i), data[i]); }

        Request(machine, WriteRequest, (ushort)buffer, (ushort)data.Length, block: 100).Should().Be(0);
        Bytes(machine, (ushort)buffer, data.Length).Should().Equal(data, "the driver leaves the buffer as it was");

        byte[] written = new byte[data.Length];
        for (int i = 0; i < blocks; i++) { image.ReadBlock((uint)(100 + i), written.AsSpan(i * 512, 512)); }
        written.Should().Equal(data);

        ProFileDrive drive = Drive(machine);
        drive.Media.Should().NotBeNull();
        drive.Media.GetValueOrDefault().Changed.Should().BeTrue();
        drive.LastBlock.Should().Be(100 + blocks - 1);
    }

    /// <summary>
    ///  Status code 0 reports the ProFile online and not busy; code 1 the four status bytes of the last transfer, all
    ///  zero after a good one.
    /// </summary>
    [TestMethod]
    public void ReportsStatus()
    {
        (Apple3Machine machine, _) = Machine();
        Initialize(machine);
        Request(machine, ReadRequest, 0x2000, 512, block: 0).Should().Be(0);

        Poke(machine, 0x1A40, 0xEE);
        Status(machine, 0, 0x1A40).Should().Be(0);
        machine.Bus.Peek(0x1A40).Should().Be(0x00, "not busy, and the no-drive bit is clear");

        Fill(machine, 0x1A40, 4, 0xEE);
        Status(machine, 1, 0x1A40).Should().Be(0);
        Bytes(machine, 0x1A40, 4).Should().Equal(0, 0, 0, 0);
    }

    /// <summary>
    ///  A block past the device information block's count is a bad block number, and a slot with no ProFile cabled
    ///  answers no device.
    /// </summary>
    [TestMethod]
    public void ReportsErrors()
    {
        (Apple3Machine machine, _) = Machine();
        Initialize(machine);
        Request(machine, ReadRequest, 0x2000, 512, block: 0x2600).Should().Be(0x2D, "XBLKNUM");
        Request(machine, ReadRequest, 0x2000, 100, block: 0).Should().Be(0x2C, "XBYTECNT");

        Drive(machine).Eject();
        Request(machine, ReadRequest, 0x2000, 512, block: 0).Should().Be(0x28, "XNODRIVE");
    }

    /// <summary>
    ///  Without the card the slot's ports read nothing, and the card's own ports report the ProFile.
    /// </summary>
    [TestMethod]
    public void CardAnswersInItsSlot()
    {
        Apple3Machine machine = new(new Apple3Roms(s_rom.Value, new byte[256]));
        machine.Bus.Peek(0xC0C2).Should().Be(0xFF);
        Apple3ProFileCard card = machine.Bus.InstallProFile(Slot);
        machine.Bus.Peek(0xC0C2).Should().Be(0x81, "ready, but no ProFile cabled");
        card.Drive.Insert(new MemoryBlockDevice(new byte[512 * 4], isReadOnly: false), "test", "PO");
        machine.Bus.Peek(0xC0C2).Should().Be(0x80);
        machine.Devices.Should().Contain(card.Drive);

        machine.Bus.RemoveProFile(Slot);
        machine.Devices.Should().NotContain(card.Drive);
        machine.Bus.Peek(0xC0C2).Should().Be(0xFF);
    }

    private static (Apple3Machine Machine, MemoryBlockDevice Image) Machine()
    {
        Apple3Machine machine = new(new Apple3Roms(s_rom.Value, new byte[256]));

        // The reset sequence runs to the reset vector's target, where the registers can be set.
        while (!machine.Processor.IsInstructionBoundary) { machine.StepCycle(); }
        byte[] bytes = new byte[Blocks * 512];
        for (int i = 0; i < bytes.Length; i++) { bytes[i] = (byte)((i >> 9) * 7 + (i * 13) + (i >> 4)); }
        MemoryBlockDevice image = new(bytes, isReadOnly: false);
        machine.Bus.InstallProFile(Slot).Drive.Insert(image, "test.po", "PO");

        Apple3Bus bus = machine.Bus;

        // I/O, the primary stack and the ROM; the kernel's zero page; bank 0 at $2000. As the boot ROM leaves it, only
        // the bank register's low four bits are outputs, so the VIAs stay in view whatever bank the driver writes.
        bus.Write(0xFFDF, 0x47);
        bus.Write(0xFFD3, 0xFF);
        bus.Write(0xFFD0, 0x18);
        bus.Write(0xFFD2, 0xFF);
        bus.Write(0xFFEF, 0x40);
        bus.Write(0xFFE3, 0x0F);

        // The kernel's zero page and its extension page: no X-bytes, so every pointer is an ordinary address.
        Fill(machine, 0x1400, 0x100, 0);
        Fill(machine, 0x1800, 0x100, 0);

        byte[] driver = s_driver.Value;
        for (int i = 0; i < driver.Length; i++) { Poke(machine, (ushort)(DriverOrigin + i), driver[i]); }

        // The kernel entries the driver calls: ALLOCSIR, DEALCSIR and SELC800 succeed; SYSERR records A and stops.
        Poke(machine, 0x1913, 0x18, 0x60);
        Poke(machine, 0x1916, 0x18, 0x60);
        Poke(machine, 0x1922, 0x18, 0x60);
        Poke(machine, 0x1928, 0x8D, ErrorCode & 0xFF, ErrorCode >> 8, 0x4C, Failed & 0xFF, Failed >> 8);
        Poke(machine, Failed, 0x4C, Failed & 0xFF, Failed >> 8);
        ushort main = (ushort)(driver[2] | (driver[3] << 8));
        Poke(machine, Caller, 0x20, (byte)main, (byte)(main >> 8), 0x4C, Done & 0xFF, Done >> 8);
        return (machine, image);
    }

    private static ProFileDrive Drive(Apple3Machine machine) =>
        machine.Bus.ProFileIn(Slot)?.Drive ?? throw new InvalidOperationException("The slot has no ProFile card.");

    private static void Initialize(Apple3Machine machine) =>
        Request(machine, InitializeRequest, 0, 0, 0).Should().Be(0);

    private static byte Status(Apple3Machine machine, byte code, ushort list)
    {
        Poke(machine, ParameterBase, StatusRequest, 0, code, (byte)list, (byte)(list >> 8));
        return Run(machine);
    }

    // Makes a request and runs the driver; returns 0, or the error it gave SYSERR.
    private static byte Request(Apple3Machine machine, byte request, ushort buffer, ushort bytes, ushort block)
    {
        Poke(
            machine,
            ParameterBase,
            request,
            0,
            (byte)buffer,
            (byte)(buffer >> 8),
            (byte)bytes,
            (byte)(bytes >> 8),
            (byte)block,
            (byte)(block >> 8),
            BytesRead & 0xFF,
            BytesRead >> 8);

        return Run(machine);
    }

    private static byte Run(Apple3Machine machine)
    {
        Poke(machine, ErrorCode, 0);
        machine.Processor.Registers = new()
        {
            ProgramCounter = Caller,
            StackPointer = 0xFF,
            Status = StatusRegister.Unused | StatusRegister.IRQBDisable
        };

        for (int i = 0; i < 2_000_000; i++)
        {
            machine.StepInstruction().Status.Should().Be(ProcessorExecutionStatus.InstructionComplete);
            ushort pc = machine.Processor.Registers.ProgramCounter;
            if (pc == Done) { return 0; }
            if (pc == Failed) { return machine.Bus.Peek(ErrorCode); }
        }

        throw new InvalidOperationException("The driver did not return.");
    }

    private static byte[] DriverCode(int origin)
    {
        AssemblyResult result = SosDriverSourceTests.Assemble("Profile", "", origin);
        result.Diagnostics.Should().BeEmpty();
        ReadOnlySpan<byte> bytes = result.Sections[0].Bytes.Span;

        // The comment record comes first; the code, which counts from the device information block, follows it.
        int start = 4 + (bytes[2] | (bytes[3] << 8));
        return bytes[start..].ToArray();
    }

    private static void Poke(Apple3Machine machine, ushort address, params ReadOnlySpan<byte> values)
    {
        for (int i = 0; i < values.Length; i++)
        {
            machine.Bus.Ram[machine.Bus.RamOffset((ushort)(address + i))] = values[i];
        }
    }

    private static void Fill(Apple3Machine machine, ushort address, int count, byte value)
    {
        for (int i = 0; i < count; i++) { Poke(machine, (ushort)(address + i), value); }
    }

    private static byte[] Bytes(Apple3Machine machine, ushort address, int count)
    {
        byte[] bytes = new byte[count];
        for (int i = 0; i < count; i++) { bytes[i] = machine.Bus.Ram[machine.Bus.RamOffset((ushort)(address + i))]; }
        return bytes;
    }

    private static int Word(Apple3Machine machine, ushort address) =>
        machine.Bus.Peek(address) | (machine.Bus.Peek((ushort)(address + 1)) << 8);
}
