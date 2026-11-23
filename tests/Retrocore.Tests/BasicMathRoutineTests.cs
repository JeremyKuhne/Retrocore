// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information


namespace Retrocore.Tests;

/// <summary>
///  Runs the converted math package's routines in the shipped AppleSoft and PET BASIC 4 builds and checks what their
///  documentation says they do and return.
/// </summary>
[TestClass]
public sealed class BasicMathRoutineTests
{
    // Where a test puts a packed operand.
    private const ushort Operand = 0x0400;

    /// <summary>
    ///  Each binary operation that takes a packed operand at Y:A leaves the documented result in <c>Fac</c>; the
    ///  subtraction and division take the packed operand minus and divided by <c>Fac</c>.
    /// </summary>
    /// <param name="apple">Whether to run AppleSoft rather than PET BASIC 4.</param>
    /// <param name="routine">The routine.</param>
    /// <param name="fac">The value in <c>Fac</c>.</param>
    /// <param name="operand">The packed operand.</param>
    /// <param name="expected">The result.</param>
    [TestMethod]
    [DataRow(true, "Float::AddPacked", 1.5, 2.25, 3.75)]
    [DataRow(false, "Float::AddPacked", -1.5, 2.25, 0.75)]
    [DataRow(true, "Float::SubtractFromPacked", 4.0, 10.0, 6.0)]
    [DataRow(false, "Float::SubtractFromPacked", 4.0, 10.0, 6.0)]
    [DataRow(true, "Float::MultiplyPacked", 3.0, -2.5, -7.5)]
    [DataRow(false, "Float::MultiplyPacked", 3.0, -2.5, -7.5)]
    [DataRow(false, "Float::MultiplyPacked", 1.0, 1.0000000004656612873077392578125, 1.0000000004656612873077392578125)]
    [DataRow(true, "Float::DividePacked", 4.0, 10.0, 2.5)]
    [DataRow(false, "Float::DividePacked", -4.0, 10.0, -2.5)]
    public void PackedOperationsLeaveTheResultInFac(bool apple, string routine, double fac, double operand, double expected)
    {
        BasicMathMachine machine = new(apple);
        machine.SetFac(fac);
        machine.Pack(Operand, operand);
        machine.Call(routine, a: Operand & 0xFF, y: Operand >> 8);
        machine.Fac.Should().Be(expected);
    }

    /// <summary>
    ///  A zero multiplier byte that follows another zero byte reaches <c>Float::ShiftProductByte</c> with carry clear,
    ///  so the result bytes shift nine bits rather than eight, halving the partial product so far. With <c>Fac</c> =
    ///  1 + 2^-31 (mantissa bytes $80, $00, $00, $01) times 1, the low bit ends at half weight in
    ///  <c>FacExtension</c>: the unrounded mantissa reads 1, and rounding as the result is stored restores 1 + 2^-31.
    ///  The same product with the operands swapped, whose multiplier is zero below its top byte, is exact.
    /// </summary>
    /// <param name="apple">Whether to run AppleSoft rather than PET BASIC 4.</param>
    [TestMethod]
    [DataRow(data: true)]
    [DataRow(data: false)]
    public void MultiplicationHalvesThePartialProductAfterTwoZeroMultiplierBytes(bool apple)
    {
        const double OnePlus = 1.0000000004656612873077392578125;
        BasicMathMachine machine = new(apple);
        machine.SetFac(OnePlus);
        machine.Pack(Operand, 1.0);
        machine.Call("Float::MultiplyPacked", a: Operand & 0xFF, y: Operand >> 8);
        machine.Fac.Should().Be(1.0);
        machine.Memory[machine.Address("FacExtension")].Should().Be(0x80);

        machine.Call("Float::StoreFac", x: Operand & 0xFF, y: Operand >> 8);
        machine.Memory.AsSpan(Operand, 5).ToArray().Should().Equal(BasicMathMachine.Packed(OnePlus));

        machine.SetFac(1.0);
        machine.Pack(Operand, OnePlus);
        machine.Call("Float::MultiplyPacked", a: Operand & 0xFF, y: Operand >> 8);
        machine.Fac.Should().Be(OnePlus);
        machine.Memory[machine.Address("FacExtension")].Should().Be(0);
    }

    /// <summary>
    ///  <c>Float::Compare</c> returns 1, 0 or $FF in A as <c>Fac</c> is greater than, equal to or less than the packed
    ///  operand.
    /// </summary>
    /// <param name="apple">Whether to run AppleSoft rather than PET BASIC 4.</param>
    /// <param name="fac">The value in <c>Fac</c>.</param>
    /// <param name="operand">The packed operand.</param>
    /// <param name="expected">The ordering byte.</param>
    [TestMethod]
    [DataRow(true, 2.0, 1.0, 0x01)]
    [DataRow(true, 1.0, 1.0, 0x00)]
    [DataRow(true, -1.0, 1.0, 0xFF)]
    [DataRow(false, 0.5, 0.25, 0x01)]
    [DataRow(false, -3.0, -3.0, 0x00)]
    [DataRow(false, -3.0, -2.0, 0xFF)]
    public void CompareReturnsTheOrderingInA(bool apple, double fac, double operand, int expected)
    {
        BasicMathMachine machine = new(apple);
        machine.SetFac(fac);
        machine.Pack(Operand, operand);
        machine.Call("Float::Compare", a: Operand & 0xFF, y: Operand >> 8);
        machine.Cpu.Registers.Accumulator.Should().Be((byte)expected);
    }

    /// <summary>
    ///  <c>Float::GetSign</c> returns $FF, 0 or 1 in A for a negative, zero or positive <c>Fac</c>.
    /// </summary>
    /// <param name="apple">Whether to run AppleSoft rather than PET BASIC 4.</param>
    /// <param name="fac">The value in <c>Fac</c>.</param>
    /// <param name="expected">The sign byte.</param>
    [TestMethod]
    [DataRow(true, -2.0, 0xFF)]
    [DataRow(true, 0.0, 0x00)]
    [DataRow(false, 3.0, 0x01)]
    [DataRow(false, -0.5, 0xFF)]
    public void GetSignReturnsTheSignInA(bool apple, double fac, int expected)
    {
        BasicMathMachine machine = new(apple);
        machine.SetFac(fac);
        machine.Call("Float::GetSign");
        machine.Cpu.Registers.Accumulator.Should().Be((byte)expected);
    }

    /// <summary>
    ///  <c>Float::LoadFac</c> unpacks Y:A into <c>Fac</c>, clears <c>FacExtension</c>, and returns the exponent in A
    ///  with zero set for a zero exponent.
    /// </summary>
    /// <param name="apple">Whether to run AppleSoft rather than PET BASIC 4.</param>
    /// <param name="value">The packed value.</param>
    [TestMethod]
    [DataRow(true, 0.0)]
    [DataRow(true, -6.25)]
    [DataRow(false, 0.0)]
    [DataRow(false, 1024.5)]
    public void LoadFacReturnsTheExponent(bool apple, double value)
    {
        BasicMathMachine machine = new(apple);
        machine.Pack(Operand, value);
        machine.Memory[machine.Address("FacExtension")] = 0x55;
        machine.Call("Float::LoadFac", a: Operand & 0xFF, y: Operand >> 8);

        machine.Fac.Should().Be(value);
        machine.Memory[machine.Address("FacExtension")].Should().Be(0);
        machine.Cpu.Registers.Accumulator.Should().Be(machine.Memory[Operand]);
        machine.Cpu.Registers.Status.HasFlag(StatusRegister.Zero).Should().Be(value == 0);
    }

    /// <summary>
    ///  <c>Float::StoreFac</c> packs <c>Fac</c> at Y:X, rounding by <c>FacExtension</c>, and returns with Y = 0 and
    ///  <c>FacExtension</c> clear.
    /// </summary>
    /// <param name="apple">Whether to run AppleSoft rather than PET BASIC 4.</param>
    /// <param name="extension">The extension byte, whose bit 7 rounds the mantissa up.</param>
    [TestMethod]
    [DataRow(true, 0x00)]
    [DataRow(true, 0x80)]
    [DataRow(false, 0x7F)]
    [DataRow(false, 0x80)]
    public void StoreFacPacksAndRounds(bool apple, int extension)
    {
        BasicMathMachine machine = new(apple);
        machine.SetFac(3.75);
        machine.Memory[machine.Address("FacExtension")] = (byte)extension;
        machine.Call("Float::StoreFac", x: Operand & 0xFF, y: Operand >> 8);

        byte[] packed = BasicMathMachine.Packed(3.75);
        if (extension >= 0x80) { packed[4]++; }
        machine.Memory.AsSpan(Operand, 5).ToArray().Should().Equal(packed);
        machine.Cpu.Registers.Y.Should().Be(0);
        machine.Memory[machine.Address("FacExtension")].Should().Be(0);
    }

    /// <summary>
    ///  <c>Float::ToLongInteger</c> leaves the greatest integer not above <c>Fac</c> as a signed four-byte integer in
    ///  <c>FacMantissa1</c> through <c>FacMantissa4</c>, high byte first: a negative value's complemented mantissa is
    ///  shifted with its sign, which rounds it down.
    /// </summary>
    /// <param name="apple">Whether to run AppleSoft rather than PET BASIC 4.</param>
    /// <param name="fac">The value in <c>Fac</c>.</param>
    /// <param name="expected">The integer.</param>
    [TestMethod]
    [DataRow(true, 1234.75, 1234)]
    [DataRow(false, 65535.5, 65535)]
    [DataRow(false, 0.75, 0)]
    [DataRow(true, -1.5, -2)]
    [DataRow(false, -1234.75, -1235)]
    [DataRow(false, -2.0, -2)]
    public void ToLongIntegerLeavesTheIntegerInTheMantissa(bool apple, double fac, int expected)
    {
        BasicMathMachine machine = new(apple);
        machine.SetFac(fac);
        machine.Call("Float::ToLongInteger");
        machine.BigEndian(machine.Address("FacMantissa1")).Should().Be((uint)expected);
    }

    /// <summary>
    ///  <c>Float::ShiftRight</c> shifts four bytes right by the negative count in A, keeping the high byte's sign, and
    ///  returns the shifted-out bits in A, above the old <c>FacExtension</c>'s, with carry clear. A count of eight or
    ///  more moves whole bytes first, filling from <c>ShiftFill</c>, the low byte into <c>FacExtension</c>.
    /// </summary>
    /// <param name="apple">Whether to run AppleSoft rather than PET BASIC 4.</param>
    /// <param name="count">The negative shift count.</param>
    /// <param name="high">The high byte before the shift.</param>
    /// <param name="low">The low byte before the shift.</param>
    /// <param name="shiftedHigh">The high byte after.</param>
    /// <param name="bits">The byte returned in A.</param>
    [TestMethod]
    [DataRow(true, -1, 0x80, 0x01, 0xC0, 0x80)]
    [DataRow(false, -2, 0x40, 0x03, 0x10, 0xC0)]
    [DataRow(false, -1, 0x7E, 0x00, 0x3F, 0x00)]
    [DataRow(true, -9, 0x12, 0x78, 0x00, 0x3C)]
    public void ShiftRightKeepsTheSignAndReturnsTheLowBits(bool apple, int count, int high, int low, int shiftedHigh, int bits)
    {
        BasicMathMachine machine = new(apple);
        int exponent = machine.Address("ArgExponent");
        machine.Memory[exponent + 1] = (byte)high;
        machine.Memory[exponent + 2] = 0;
        machine.Memory[exponent + 3] = 0;
        machine.Memory[exponent + 4] = (byte)low;
        machine.Memory[machine.Address("FacExtension")] = 0;
        machine.Memory[machine.Address("ShiftFill")] = 0;
        machine.Call("Float::ShiftRight", a: count & 0xFF, x: exponent, carry: false);

        machine.Memory[exponent + 1].Should().Be((byte)shiftedHigh);
        machine.Cpu.Registers.Accumulator.Should().Be((byte)bits);
        machine.Cpu.Registers.Status.HasFlag(StatusRegister.Carry).Should().BeFalse();
    }

    /// <summary>
    ///  A bit shift returns the old <c>FacExtension</c> shifted right below the bits shifted out; a shift of eight or
    ///  more first moves whole bytes down, filling the top from <c>ShiftFill</c> and moving the low byte into
    ///  <c>FacExtension</c>, which then takes the place of the old extension.
    /// </summary>
    /// <param name="apple">Whether to run AppleSoft rather than PET BASIC 4.</param>
    /// <param name="count">The negative shift count.</param>
    /// <param name="fill">The byte in <c>ShiftFill</c>.</param>
    /// <param name="expected">The four bytes after the shift, high first, then A, then <c>FacExtension</c>.</param>
    [TestMethod]
    [DataRow(true, -1, 0x00, new int[] { 0xC0, 0x09, 0x1A, 0x2B, 0x4D, 0x9A })]
    [DataRow(false, -9, 0xFF, new int[] { 0xFF, 0x89, 0x1A, 0x2B, 0x3C, 0x78 })]
    [DataRow(true, -16, 0x00, new int[] { 0x00, 0x00, 0x12, 0x34, 0x56, 0x56 })]
    public void ShiftRightMovesEveryByte(bool apple, int count, int fill, int[] expected)
    {
        BasicMathMachine machine = new(apple);
        int exponent = machine.Address("ArgExponent");
        byte[] bytes = [0x80, 0x12, 0x34, 0x56];
        if (count != -1) { bytes = [0x12, 0x34, 0x56, 0x78]; }
        bytes.CopyTo(machine.Memory, exponent + 1);
        machine.Memory[machine.Address("FacExtension")] = 0x9A;
        machine.Memory[machine.Address("ShiftFill")] = (byte)fill;
        machine.Call("Float::ShiftRight", a: count & 0xFF, x: exponent, carry: false);

        int[] actual =
        [
            .. machine.Memory.AsSpan(exponent + 1, 4).ToArray().Select(value => (int)value),
            machine.Cpu.Registers.Accumulator,
            machine.Memory[machine.Address("FacExtension")]
        ];

        actual.Should().Equal(expected);
        machine.Cpu.Registers.Status.HasFlag(StatusRegister.Carry).Should().BeFalse();
    }

    /// <summary>
    ///  <c>Float::FormatFac</c> writes a zero-terminated decimal string at <c>NumberBuffer</c> and returns its address
    ///  in Y:A; AppleSoft omits the positive sign's space and PET BASIC writes it.
    /// </summary>
    /// <param name="apple">Whether to run AppleSoft rather than PET BASIC 4.</param>
    /// <param name="fac">The value in <c>Fac</c>.</param>
    /// <param name="expected">The text.</param>
    [TestMethod]
    [DataRow(true, 3.75, "3.75")]
    [DataRow(false, 3.75, " 3.75")]
    [DataRow(true, -7.5, "-7.5")]
    [DataRow(false, 1e10, " 1E+10")]
    [DataRow(true, 0.0, "0")]
    public void FormatFacReturnsTheText(bool apple, double fac, string expected)
    {
        BasicMathMachine machine = new(apple);
        machine.SetFac(fac);
        machine.Call("Float::FormatFac");

        int buffer = machine.Address("NumberBuffer");
        machine.Cpu.Registers.Accumulator.Should().Be((byte)buffer);
        machine.Cpu.Registers.Y.Should().Be((byte)(buffer >> 8));
        int end = Array.IndexOf(machine.Memory, (byte)0, buffer);
        System.Text.Encoding.ASCII.GetString(machine.Memory, buffer, end - buffer).Should().Be(expected);
    }
}
