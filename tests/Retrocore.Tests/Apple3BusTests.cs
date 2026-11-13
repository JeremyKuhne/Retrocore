// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using Retrocore.Machines.Apple3;

namespace Retrocore.Tests;

/// <summary>
///  The Apple III's memory decoding, on a made-up ROM, so no dump is needed.
/// </summary>
[TestClass]
public class Apple3BusTests
{
    private const ushort Via0PortB = 0xFFD0;
    private const ushort Via0DdrB = 0xFFD2;
    private const ushort Via0DdrA = 0xFFD3;
    private const ushort Environment = 0xFFDF;
    private const ushort Via1DdrA = 0xFFE3;
    private const ushort Bank = 0xFFEF;

    // I/O on, the VIAs' page, and the ROM: what the boot ROM sets first, less 1 MHz and video.
    private const byte BaseEnvironment = Apple3Bus.IoEnable | Apple3Bus.RomEnable | 0x02;

    /// <summary>
    ///  At power-on the VIAs' ports are inputs, so every register reads all ones: the ROM and I/O are in, the stack
    ///  is page 1 and RAM is write-protected.
    /// </summary>
    [TestMethod]
    public void PowerOnMapsTheRomIoAndVias()
    {
        Apple3Bus bus = Bus();
        bus.Environment.Should().Be(0xFF);
        bus.ReadArea(0xF000).Should().Be(Apple3MemoryArea.Rom);
        bus.Read(0xFFFC).Should().Be(0x00);
        bus.Read(0xFFFD).Should().Be(0xF0);
        bus.ReadArea(0xC000).Should().Be(Apple3MemoryArea.Io);
        bus.ReadArea(0xFFD0).Should().Be(Apple3MemoryArea.Vias);
        bus.ReadArea(0xFFC0).Should().Be(Apple3MemoryArea.SystemBank, "$FFC0-$FFCF is always RAM");
        bus.IsSlow.Should().BeTrue();
    }

    /// <summary>
    ///  The zero-page register moves zero page, and the stack to the page with the low bit flipped; between $20 and
    ///  $9F both are in the switchable bank. The primary stack bit pins the stack to the system bank's page 1.
    /// </summary>
    [TestMethod]
    public void ZeroPageAndStackFollowTheZeroPageRegister()
    {
        Apple3Bus bus = Bus();
        SetEnvironment(bus, BaseEnvironment);
        SetBank(bus, 1);
        SetZeroPage(bus, 0x20);

        bus.Write(0x0012, 0xA5);
        bus.Ram[0x8000 + 0x0012].Should().Be(0xA5, "page $20 is the start of bank 1");
        bus.Write(0x01FF, 0x5A);
        bus.Ram[0x8000 + 0x01FF].Should().Be(0x5A, "the stack is page $21");

        SetZeroPage(bus, 0x03);
        int system = bus.Ram.Length - 0x8000;
        bus.Write(0x0012, 0x11);
        bus.Ram[system + 0x0312].Should().Be(0x11);
        bus.Write(0x0100, 0x22);
        bus.Ram[system + 0x0200].Should().Be(0x22, "the stack is page 2");

        SetEnvironment(bus, BaseEnvironment | Apple3Bus.PrimaryStack);
        bus.Write(0x0100, 0x33);
        bus.Ram[system + 0x0100].Should().Be(0x33);

        SetZeroPage(bus, 0xC0);
        bus.Write(0x0001, 0x44);
        bus.Ram[system + 0x4001].Should().Be(0x44, "page $C0 is in the system bank, as $C000 is");
    }

    /// <summary>
    ///  The bank register picks the RAM at $2000-$9FFF; the rest stays the system bank, the last 32K. The all-ones
    ///  number, 7 (15 with 512K), is bank 0, as the RAM decode PROMs have it; on 128K, 3-6 wrap at three banks.
    /// </summary>
    /// <param name="ramKilobytes">The RAM size.</param>
    /// <param name="bank">The bank register's bank.</param>
    /// <param name="expected">The bank it selects.</param>
    [TestMethod]
    [DataRow(256, 0, 0)]
    [DataRow(256, 1, 1)]
    [DataRow(256, 6, 6)]
    [DataRow(256, 7, 0)]
    [DataRow(128, 2, 2)]
    [DataRow(128, 3, 0)]
    [DataRow(128, 7, 0)]
    [DataRow(512, 7, 7)]
    [DataRow(512, 14, 14)]
    [DataRow(512, 15, 0)]
    public void BankRegisterSelectsTheBankAt2000(int ramKilobytes, int bank, int expected)
    {
        Apple3Bus bus = Bus(ramKilobytes);
        SetEnvironment(bus, BaseEnvironment);
        SetBank(bus, bank);
        bus.Write(0x2000, 0x77);
        bus.Write(0x9FFF, 0x78);
        bus.Write(0xA000, 0x79);
        bus.Ram[(expected * 0x8000) + 0x0000].Should().Be(0x77);
        bus.Ram[(expected * 0x8000) + 0x7FFF].Should().Be(0x78);
        bus.Ram[bus.Ram.Length - 0x6000].Should().Be(0x79, "$A000 is the system bank's $2000");
        bus.ReadArea(0x2000).Should().Be(Apple3MemoryArea.Bank0 + expected);
    }

    /// <summary>
    ///  Clearing VIA 1 port A bit 6, the Apple II mode trap, hides the VIAs, so the mode cannot be left.
    /// </summary>
    [TestMethod]
    public void ClearingTheModeTrapHidesTheViasForGood()
    {
        Apple3Bus bus = Bus();
        SetEnvironment(bus, BaseEnvironment);
        SetBank(bus, 0);
        bus.AppleIIMode.Should().BeFalse();

        // Bank register bit 6 low: Apple II mode. $FFD0-$FFEF become RAM, so the VIAs cannot be written again.
        bus.Write(Bank, 0x00);
        bus.AppleIIMode.Should().BeTrue();
        bus.Write(Bank, 0x40);
        bus.AppleIIMode.Should().BeTrue("the bank register is no longer there to write");
        bus.Ram[bus.Ram.Length - 0x10000 + Bank].Should().Be(0x40, "the write went to the system bank's RAM");
    }

    /// <summary>
    ///  With write protection, RAM from $C000 up keeps its contents; RAM under the ROM takes writes only without it.
    /// </summary>
    [TestMethod]
    public void WriteProtectionCoversTheSystemBankFromC000()
    {
        Apple3Bus bus = Bus();
        SetEnvironment(bus, BaseEnvironment | Apple3Bus.WriteProtect);
        bus.Write(0xD000, 0x12);
        bus.Write(0xF000, 0x12);
        bus.Write(0xBFFF, 0x12);
        bus.Peek(0xD000).Should().Be(0xFF);
        bus.Peek(0xBFFF).Should().Be(0x12, "$A000-$BFFF is not protected");

        SetEnvironment(bus, BaseEnvironment);
        bus.Write(0xF000, 0x34);
        bus.Peek(0xF000).Should().Be(0xA9, "the ROM still answers reads");
        SetEnvironment(bus, Apple3Bus.IoEnable);
        bus.Peek(0xF000).Should().Be(0x34, "the RAM under the ROM took the write");
    }

    /// <summary>
    ///  With I/O off, $C000-$CFFF is RAM.
    /// </summary>
    [TestMethod]
    public void IoOffShowsRam()
    {
        Apple3Bus bus = Bus();
        SetEnvironment(bus, Apple3Bus.RomEnable);
        bus.ReadArea(0xC000).Should().Be(Apple3MemoryArea.SystemBank);
        bus.Write(0xC010, 0x42);
        bus.Read(0xC010).Should().Be(0x42);
    }

    /// <summary>
    ///  A zero-page read while zero page is in pages $18-$1F latches the X-byte at its address XOR $0C00; with bit 7
    ///  set, accesses above $00FF go to the bank pair it names until the next opcode fetch.
    /// </summary>
    [TestMethod]
    public void XByteRedirectsAccessesUntilTheNextFetch()
    {
        Apple3Bus bus = Bus();
        SetEnvironment(bus, BaseEnvironment);
        SetBank(bus, 0);
        SetZeroPage(bus, 0x1A);
        int system = bus.Ram.Length - 0x8000;
        bus.Ram[system + 0x1621] = 0x81;     // the X-byte beside the pointer's high byte, $1A21
        bus.Ram[0x8000 + 0x3005] = 0x5A;     // bank pair 1, offset $3005
        bus.Ram[0x3005 - 0x2000] = 0xA5;     // bank 0, as $3005 normally reads

        bus.ReadOpcode(0xF000);
        bus.Read(0x0020);
        bus.Read(0x0021);
        bus.ExtendedBank.Should().Be(0x81);
        bus.Read(0x3005).Should().Be(0x5A);
        bus.Write(0x3006, 0x66);
        bus.Ram[0x8000 + 0x3006].Should().Be(0x66);

        bus.ReadOpcode(0xF000);
        bus.ExtendedBank.Should().Be(0);
        bus.Read(0x3005).Should().Be(0xA5);

        // Bit 7 clear is no redirection.
        bus.Ram[system + 0x1621] = 0x01;
        bus.Read(0x0021);
        bus.ExtendedBank.Should().Be(0);
        bus.Read(0x3005).Should().Be(0xA5);
    }

    /// <summary>
    ///  X-byte $8F reaches the system bank as the CPU sees it, including the RAM under the VIAs, and bank 0 at $2000.
    ///  With three bank lines, $87 is the same bank 7 and the same view.
    /// </summary>
    /// <param name="xByte">The X-byte.</param>
    [TestMethod]
    [DataRow(0x8F)]
    [DataRow(0x87)]
    public void XByteBank7ReachesTheRamUnderTheVias(int xByte)
    {
        Apple3Bus bus = Bus();
        SetEnvironment(bus, BaseEnvironment);
        SetZeroPage(bus, 0x18);
        int system = bus.Ram.Length - 0x8000;
        bus.Ram[system + 0x1410] = (byte)xByte;  // X-byte for $1810
        bus.Ram[system + 0x7FD0] = 0x3C;         // the RAM under VIA 0
        bus.Ram[0x0000] = 0x5A;                  // bank 0's first byte

        bus.Read(0x0010);
        bus.Read(0xFFD0).Should().Be(0x3C);
        bus.Read(0x2000).Should().Be(0x5A);
        bus.Read(0x1000).Should().Be(bus.Ram[system + 0x1000]);
    }

    /// <summary>
    ///  Through an X-byte naming bank N, $8000 and up is bank N + 1; past the last switchable bank, that is bank 0,
    ///  never the system bank.
    /// </summary>
    [TestMethod]
    public void XByteLastBankPairsWithBank0()
    {
        Apple3Bus bus = Bus(ramKilobytes: 128);
        SetEnvironment(bus, BaseEnvironment);
        SetZeroPage(bus, 0x18);
        int system = bus.Ram.Length - 0x8000;
        bus.Ram[system + 0x1410] = 0x82;
        bus.Ram[(2 * 0x8000) + 0x1000] = 0x22;   // bank 2
        bus.Ram[0x1000] = 0x00;                  // bank 0

        bus.Read(0x0010);
        bus.Read(0x1000).Should().Be(0x22);
        bus.Read(0x9000).Should().Be(0x00);
        bus.Ram[system + 0x1000] = 0x33;
        bus.Read(0x9000).Should().Be(0x00, "the system bank is not bank 3");
    }

    /// <summary>
    ///  The processor tells the bus its opcode fetches, so <c>LDA ($20),Y</c> reads through the X-byte, and the next
    ///  instruction does not.
    /// </summary>
    [TestMethod]
    public void IndirectLoadReadsThroughTheXByte()
    {
        byte[] program =
        [
            0xA9, 0xFF, 0x8D, 0xD2, 0xFF,   // LDA #$FF; STA $FFD2  (zero-page register outputs)
            0xA9, 0x1A, 0x8D, 0xD0, 0xFF,   // LDA #$1A; STA $FFD0  (zero page = $1A00)
            0xA0, 0x00,                     // LDY #0
            0xB1, 0x20,                     // LDA ($20),Y
            0x8D, 0x00, 0x03,               // STA $0300
            0xAD, 0x00, 0x30,               // LDA $3000
            0x8D, 0x01, 0x03,               // STA $0301
            0x02                            // JAM
        ];

        Apple3Machine machine = new(Roms(program));
        Apple3Bus bus = machine.Bus;
        int system = bus.Ram.Length - 0x8000;
        bus.Ram[system + 0x1A20] = 0x00;
        bus.Ram[system + 0x1A21] = 0x30;
        bus.Ram[system + 0x1621] = 0x81;
        bus.Ram[0x8000 + 0x3000] = 0x5A;     // bank pair 1
        bus.Ram[0x1000] = 0xA5;              // the power-on bank register reads 7: bank 0 at $2000

        machine.Run(cycles: 200);
        bus.Ram[system + 0x0300].Should().Be(0x5A);
        bus.Ram[system + 0x0301].Should().Be(0xA5);
    }

    /// <summary>
    ///  A key sets the strobe at $C000; $C010 clears it, and the next comes a typist's beat later. $C008 reports the
    ///  modifiers, active low but for SHIFT, which a typed capital holds.
    /// </summary>
    [TestMethod]
    public void KeyboardStrobeAndModifiers()
    {
        Apple3Bus bus = Bus();
        bus.QueueKey((byte)'a');
        bus.QueueKey((byte)' ');
        bus.QueueKey((byte)'A');
        bus.Read(0xC000).Should().Be(0xC1, "the keyboard sends letters as capitals");
        bus.Read(0xC008).Should().Be(0x7D, "strobe, no modifiers");
        bus.Read(0xC010);
        bus.Read(0xC000).Should().Be(0x41, "the next key waits");
        bus.Advance(300_000_000);
        bus.Read(0xC000).Should().Be(0xA0, "space is the III's $A0");
        bus.Read(0xC008).Should().Be(0xFD, "bit 7 marks the III's special codes");
        bus.Write(0xC010, 0);
        bus.Read(0xC000).Should().Be(0x20);
        bus.Advance(300_000_000);
        bus.Read(0xC000).Should().Be(0xC1);
        bus.Read(0xC008).Should().Be(0x7F, "a capital comes with SHIFT");
        bus.Read(0xC010);

        bus.Modifiers = Apple3Modifiers.Shift | Apple3Modifiers.Control | Apple3Modifiers.OpenApple;
        bus.Read(0xC008).Should().Be(0x6A, "the last key, a letter, leaves bit 7 clear");
    }

    /// <summary>
    ///  A control character comes with CONTROL held, from which SOS makes it, as it makes a capital from SHIFT; RETURN,
    ///  ESCAPE and the arrows have keys of their own and do not.
    /// </summary>
    [TestMethod]
    public void ControlCharacterHoldsControl()
    {
        Apple3Bus bus = Bus();
        bus.QueueKey(0x03);
        bus.QueueKey((byte)'\r');
        bus.Read(0xC000).Should().Be(0x83);
        bus.Read(0xC008).Should().Be(0x79, "CONTROL reads low");
        bus.Read(0xC010);
        bus.Read(0xC008).Should().Be(0x7C, "CONTROL goes with the key");
        bus.Advance(300_000_000);
        bus.Read(0xC000).Should().Be(0x8D);
        bus.Read(0xC008).Should().Be(0x7D, "RETURN has its own key");
    }

    /// <summary>
    ///  The ACIA's registers read their reset values with nothing attached, as the boot ROM checks.
    /// </summary>
    [TestMethod]
    public void AciaReadsItsResetValues()
    {
        Apple3Bus bus = Bus();
        (((0x9F & bus.Read(0xC0F1)) + bus.Read(0xC0F2) + bus.Read(0xC0F3)) & 0xFF).Should().Be(0x10);
    }

    /// <summary>
    ///  A slot's card answers its I/O at <c>$C080 + slot * 16</c> and its ROM page while I/O is on; a read of the page
    ///  selects its expansion ROM at <c>$C800</c>, and <c>$CFFF</c> deselects it. With I/O off, RAM is there.
    /// </summary>
    [TestMethod]
    public void SlotsDecodeTheirIoAndRom()
    {
        Apple3Bus bus = Bus();
        SetEnvironment(bus, BaseEnvironment);
        Apple3TestCard card = new(slot: 2);
        bus.InstallCard(card);

        bus.Read(0xC0A3).Should().Be(0x23);
        bus.Write(0xC0A5, 0x77);
        card.Written.Should().Be((5, 0x77));
        bus.Read(0xC0B3).Should().Be(0xFF, "slot 3 is empty");

        bus.Read(0xC810).Should().Be(0xFF, "no expansion ROM is selected");
        bus.Read(0xC245).Should().Be(0x45);
        bus.Read(0xC810).Should().Be(0xE0);
        bus.Read(0xCFFF);
        bus.Read(0xC810).Should().Be(0xFF);

        SetEnvironment(bus, BaseEnvironment & ~Apple3Bus.IoEnable);
        bus.Read(0xC245).Should().Be(bus.Ram[bus.Ram.Length - 0x8000 + 0x4245]);
        bus.RemoveCard(2);
        bus.Card(2).Should().BeNull();
    }

    /// <summary>
    ///  A card's DMA sees memory as the 6502 does, through the zero-page register, but neither starts nor follows
    ///  extended addressing.
    /// </summary>
    [TestMethod]
    public void DmaIgnoresExtendedAddressing()
    {
        Apple3Bus bus = Bus();
        SetEnvironment(bus, BaseEnvironment);
        SetBank(bus, 0);
        SetZeroPage(bus, 0x1A);
        int system = bus.Ram.Length - 0x8000;
        bus.Ram[system + 0x1621] = 0x81;
        bus.Ram[system + 0x1A21] = 0x33;
        bus.Ram[0x3005 - 0x2000] = 0xA5;

        bus.ReadOpcode(0xF000);
        bus.DmaRead(0x0021).Should().Be(0x33, "zero page is page $1A");
        bus.ExtendedBank.Should().Be(0);

        bus.Read(0x0021);
        bus.ExtendedBank.Should().Be(0x81);
        bus.DmaRead(0x3005).Should().Be(0xA5);
        bus.ExtendedBank.Should().Be(0x81, "the 6502's latch stays for its instruction");
    }

    private static Apple3Bus Bus(int ramKilobytes = 256) => new(Roms([0xA9]), ramKilobytes);

    // A ROM with the program at $F000 and every vector pointing there.
    private static Apple3Roms Roms(byte[] program)
    {
        byte[] rom = new byte[0x1000];
        program.CopyTo(rom, 0);
        rom[0xFFA] = rom[0xFFC] = rom[0xFFE] = 0x00;
        rom[0xFFB] = rom[0xFFD] = rom[0xFFF] = 0xF0;
        return new(rom, new byte[256]);
    }

    private static void SetEnvironment(Apple3Bus bus, int value)
    {
        bus.Write(Environment, (byte)value);
        bus.Write(Via0DdrA, 0xFF);
    }

    private static void SetZeroPage(Apple3Bus bus, byte page)
    {
        bus.Write(Via0PortB, page);
        bus.Write(Via0DdrB, 0xFF);
    }

    // Bit 6 keeps the VIAs in view. As the ROM does, the value goes in before the port becomes an output, or for
    // a moment bit 6 would be clear and the VIAs out of reach.
    private static void SetBank(Apple3Bus bus, int bank)
    {
        bus.Write(Bank, (byte)(0x40 | bank));
        bus.Write(Via1DdrA, 0xFF);
    }
}
