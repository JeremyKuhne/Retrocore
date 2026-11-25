// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using System.Text;

namespace Retrocore.Tests;

/// <summary>
///  Runs BASIC 4's machine-language monitor's routines (Basic.md, F) in the shipped PET BASIC 4 build, with the
///  kernal's character input and output stubbed, and checks what their documentation says they take, return and
///  keep.
/// </summary>
[TestClass]
public sealed class BasicMonitorRoutineTests
{
    // Where the input stub reads its characters from, and the index of the next one.
    private const int InputText = 0x0700;
    private const int InputIndex = 0x06F0;

    // Where the output stub records the characters it is handed, and their count.
    private const int OutputText = 0x0780;
    private const int OutputCount = 0x06F1;

    // Where the stubs keep X.
    private const int SavedX = 0x06F2;

    private const byte KeptX = 0x5A;
    private const byte KeptY = 0xA5;

    /// <summary>
    ///  <c>Monitor::HexDigit</c> gives a nibble's hexadecimal digit, with carry set for 0 to 9, and keeps X and Y.
    /// </summary>
    /// <param name="nibble">The nibble.</param>
    [TestMethod]
    [DataRow(0x0)]
    [DataRow(0x9)]
    [DataRow(0xA)]
    [DataRow(0xF)]
    public void HexDigitGivesTheDigit(int nibble)
    {
        BasicMathMachine machine = Machine();
        machine.Call("Monitor::HexDigit", a: nibble, x: KeptX, y: KeptY, carry: true);

        machine.Cpu.Registers.Accumulator.Should().Be((byte)"0123456789ABCDEF"[nibble]);
        machine.Cpu.Registers.Status.HasFlag(StatusRegister.Carry).Should().Be(nibble < 10);
        AssertKept(machine);
    }

    /// <summary>
    ///  <c>Monitor::HexValue</c> gives a digit's value with carry clear, and keeps X and Y.
    /// </summary>
    /// <param name="digit">The digit.</param>
    [TestMethod]
    [DataRow('0')]
    [DataRow('9')]
    [DataRow('A')]
    [DataRow('F')]
    public void HexValueGivesTheValue(char digit)
    {
        BasicMathMachine machine = Machine();
        machine.Call("Monitor::HexValue", a: digit, x: KeptX, y: KeptY, carry: true);

        machine.Cpu.Registers.Accumulator.Should().Be((byte)Convert.ToInt32(digit.ToString(), 16));
        machine.Cpu.Registers.Status.HasFlag(StatusRegister.Carry).Should().BeFalse();
        AssertKept(machine);
    }

    /// <summary>
    ///  <c>Monitor::NextAddress</c> advances <c>MonitorAddress</c>, counts a wrap past $FFFF in
    ///  <c>MonitorAddressWrapped</c>, and keeps A, X and Y.
    /// </summary>
    /// <param name="address">The address before.</param>
    [TestMethod]
    [DataRow(0x12FE)]
    [DataRow(0x12FF)]
    [DataRow(0xFFFF)]
    public void NextAddressAdvancesAndCountsTheWrap(int address)
    {
        BasicMathMachine machine = Machine();
        int monitorAddress = machine.Address("MonitorAddress");
        int wrapped = machine.Address("MonitorAddressWrapped");
        machine.Memory[monitorAddress] = (byte)address;
        machine.Memory[monitorAddress + 1] = (byte)(address >> 8);
        machine.Memory[wrapped] = 0;

        machine.Call("Monitor::NextAddress", a: 0x3C, x: KeptX, y: KeptY);

        Word(machine, monitorAddress).Should().Be((address + 1) & 0xFFFF);
        machine.Memory[wrapped].Should().Be(address == 0xFFFF ? (byte)1 : (byte)0);
        machine.Cpu.Registers.Accumulator.Should().Be(0x3C);
        AssertKept(machine);
    }

    /// <summary>
    ///  <c>Monitor::SwapAddresses</c> exchanges <c>MonitorAddress</c> and <c>MonitorEndAddress</c>, returns X = 0 with
    ///  zero set, and keeps Y.
    /// </summary>
    [TestMethod]
    public void SwapAddressesExchangesThem()
    {
        BasicMathMachine machine = Machine();
        int start = machine.Address("MonitorAddress");
        int end = machine.Address("MonitorEndAddress");
        machine.Memory[start] = 0x34;
        machine.Memory[start + 1] = 0x12;
        machine.Memory[end] = 0x78;
        machine.Memory[end + 1] = 0x56;

        machine.Call("Monitor::SwapAddresses", x: KeptX, y: KeptY);

        Word(machine, start).Should().Be(0x5678);
        Word(machine, end).Should().Be(0x1234);
        machine.Cpu.Registers.X.Should().Be(0);
        machine.Cpu.Registers.Status.HasFlag(StatusRegister.Zero).Should().BeTrue();
        machine.Cpu.Registers.Y.Should().Be(KeptY);
    }

    /// <summary>
    ///  <c>Monitor::SelectRegisters</c> points <c>MonitorAddress</c> at <c>SavedStatus</c>, returns A = 5 with zero
    ///  clear, and keeps X and Y; <c>Monitor::SetProgramCounter</c> copies <c>MonitorAddress</c> to the saved program
    ///  counter, returns its high byte in A, and keeps X and Y.
    /// </summary>
    [TestMethod]
    public void SelectRegistersAndSetProgramCounter()
    {
        BasicMathMachine machine = Machine();
        int monitorAddress = machine.Address("MonitorAddress");
        machine.Call("Monitor::SelectRegisters", x: KeptX, y: KeptY);

        Word(machine, monitorAddress).Should().Be(machine.Address("SavedStatus"));
        machine.Cpu.Registers.Accumulator.Should().Be(5);
        machine.Cpu.Registers.Status.HasFlag(StatusRegister.Zero).Should().BeFalse();
        AssertKept(machine);

        machine.Memory[monitorAddress] = 0xCD;
        machine.Memory[monitorAddress + 1] = 0xAB;
        machine.Call("Monitor::SetProgramCounter", x: KeptX, y: KeptY);

        machine.Memory[machine.Address("ProgramCounter")].Should().Be(0xCD);
        machine.Memory[machine.Address("ProgramCounterHigh")].Should().Be(0xAB);
        machine.Cpu.Registers.Accumulator.Should().Be(0xAB);
        AssertKept(machine);
    }

    /// <summary>
    ///  <c>Monitor::ReadByte</c> reads two digits, or a space and one digit, with carry set, and a blank field of two
    ///  spaces with carry clear and A a space; <c>MonitorHexByte</c> holds the high digit times 16.
    /// </summary>
    /// <param name="text">The characters read.</param>
    /// <param name="value">The value expected, or -1 for a blank field.</param>
    /// <param name="high">The high digit's byte expected in <c>MonitorHexByte</c>.</param>
    [TestMethod]
    [DataRow("3F", 0x3F, 0x30)]
    [DataRow("A0", 0xA0, 0xA0)]
    [DataRow(" 7", 0x07, 0x00)]
    [DataRow("  ", -1, 0x00)]
    public void ReadByteReadsAField(string text, int value, int high)
    {
        BasicMathMachine machine = Machine(text);
        machine.Call("Monitor::ReadByte", carry: value < 0);

        machine.Cpu.Registers.Status.HasFlag(StatusRegister.Carry).Should().Be(value >= 0);
        machine.Cpu.Registers.Accumulator.Should().Be(value < 0 ? (byte)' ' : (byte)value);
        machine.Memory[machine.Address("MonitorHexByte")].Should().Be((byte)high);
        machine.Memory[InputIndex].Should().Be((byte)text.Length);
    }

    /// <summary>
    ///  <c>Monitor::ReadAddress</c> reads a high and a low field into <c>MonitorAddress</c>, leaving a blank field's
    ///  byte as it was, with carry set only when the low byte was given.
    /// </summary>
    /// <param name="text">The characters read.</param>
    /// <param name="expected">The address expected.</param>
    /// <param name="carry">Whether carry is expected set.</param>
    [TestMethod]
    [DataRow("C000", 0xC000, true)]
    [DataRow("  12", 0x9912, true)]
    [DataRow("C0  ", 0xC088, false)]
    public void ReadAddressReadsTwoFields(string text, int expected, bool carry)
    {
        BasicMathMachine machine = Machine(text);
        int monitorAddress = machine.Address("MonitorAddress");
        machine.Memory[monitorAddress] = 0x88;
        machine.Memory[monitorAddress + 1] = 0x99;

        // Carry starts opposite to the expected result, so leaving it alone fails.
        machine.Call("Monitor::ReadAddress", carry: !carry);

        Word(machine, monitorAddress).Should().Be(expected);
        machine.Cpu.Registers.Status.HasFlag(StatusRegister.Carry).Should().Be(carry);
    }

    /// <summary>
    ///  <c>Monitor::ReadCharacter</c> returns a character with zero clear, but at a carriage return goes to
    ///  <c>Monitor::Prompt</c> instead of returning.
    /// </summary>
    [TestMethod]
    public void ReadCharacterAbandonsTheCommandAtTheLinesEnd()
    {
        BasicMathMachine machine = Machine("M\r");
        int prompt = machine.Address("Monitor::Prompt");
        machine.CallUntil("Monitor::ReadCharacter", [prompt]).Should().NotBe(prompt);
        machine.Cpu.Registers.Accumulator.Should().Be((byte)'M');
        machine.Cpu.Registers.Status.HasFlag(StatusRegister.Zero).Should().BeFalse();

        machine.CallUntil("Monitor::ReadCharacter", [prompt]).Should().Be(prompt);
    }

    /// <summary>
    ///  <c>Monitor::PrintByte</c> prints a byte as two hexadecimal digits, and <c>Monitor::PrintAddress</c> prints
    ///  <c>MonitorAddress</c> as four, high byte first.
    /// </summary>
    [TestMethod]
    public void PrintByteAndPrintAddressPrintHexadecimal()
    {
        BasicMathMachine machine = Machine();
        machine.Call("Monitor::PrintByte", a: 0x3C);
        Output(machine).Should().Be("3C");

        int monitorAddress = machine.Address("MonitorAddress");
        machine.Memory[monitorAddress] = 0xEF;
        machine.Memory[monitorAddress + 1] = 0xBE;
        machine.Memory[OutputCount] = 0;
        machine.Call("Monitor::PrintAddress");
        Output(machine).Should().Be("BEEF");
        Word(machine, monitorAddress).Should().Be(0xBEEF, "printing does not move the address");
    }

    // PET BASIC 4 with the kernal's character input reading the given text and its character output recorded.
    private static BasicMathMachine Machine(string text = "")
    {
        BasicMathMachine machine = new(apple: false);
        Encoding.ASCII.GetBytes(text).CopyTo(machine.Memory, InputText);
        machine.Memory[InputIndex] = 0;
        machine.Memory[OutputCount] = 0;

        // stx SavedX; ldx InputIndex; lda InputText,x; inc InputIndex; ldx SavedX; rts
        byte[] input =
        [
            0x8E, SavedX & 0xFF, SavedX >> 8, 0xAE, InputIndex & 0xFF, InputIndex >> 8,
            0xBD, InputText & 0xFF, InputText >> 8, 0xEE, InputIndex & 0xFF, InputIndex >> 8,
            0xAE, SavedX & 0xFF, SavedX >> 8, 0x60
        ];

        // stx SavedX; ldx OutputCount; sta OutputText,x; inc OutputCount; ldx SavedX; rts
        byte[] output =
        [
            0x8E, SavedX & 0xFF, SavedX >> 8, 0xAE, OutputCount & 0xFF, OutputCount >> 8,
            0x9D, OutputText & 0xFF, OutputText >> 8, 0xEE, OutputCount & 0xFF, OutputCount >> 8,
            0xAE, SavedX & 0xFF, SavedX >> 8, 0x60
        ];

        input.CopyTo(machine.Memory, machine.Address("KernalInputCharacter"));
        output.CopyTo(machine.Memory, machine.Address("KernalOutputCharacter"));
        return machine;
    }

    private static string Output(BasicMathMachine machine) =>
        Encoding.ASCII.GetString(machine.Memory, OutputText, machine.Memory[OutputCount]);

    private static int Word(BasicMathMachine machine, int address) =>
        machine.Memory[address] | (machine.Memory[address + 1] << 8);

    private static void AssertKept(BasicMathMachine machine)
    {
        machine.Cpu.Registers.X.Should().Be(KeptX);
        machine.Cpu.Registers.Y.Should().Be(KeptY);
    }
}
