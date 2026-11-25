// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Tests;

/// <summary>
///  Runs AppleSoft's own converted routines (Basic.md, E) in the enhanced IIe's AppleSoft and checks what their
///  documentation says they take and return.
/// </summary>
[TestClass]
public sealed class BasicAppleRoutineTests
{
    // The first high-resolution page's high byte.
    private const int Page1 = 0x20;

    // The soft switch whose bit 7 is set with 80 columns.
    private const int Rd80Vid = 0xC01F;

    /// <summary>
    ///  <c>HighRes::Position</c> sets <c>GBASL</c>/<c>GBASH</c> to the row's address in the interleaved page, Y and
    ///  <c>HighResByteIndex</c> to the column's byte, <c>COLOR</c> to the pixel's mask with bit 7 set, and
    ///  <c>HighResX</c>/<c>HighResY</c> to the point; an alternating color is flipped for an odd byte.
    /// </summary>
    /// <param name="row">The row.</param>
    /// <param name="column">The column.</param>
    [TestMethod]
    [DataRow(0, 0)]
    [DataRow(1, 6)]
    [DataRow(9, 7)]
    [DataRow(70, 255)]
    [DataRow(191, 279)]
    public void PositionComputesTheInterleavedAddressAndMask(int row, int column)
    {
        BasicMathMachine machine = new(apple: true);
        machine.Memory[machine.Address("HighResPage")] = Page1;
        machine.Memory[machine.Address("HighResColor")] = 0x2A;

        machine.Call("HighRes::Position", a: row, x: column & 0xFF, y: column >> 8);

        int address = (Page1 << 8) + ((row & 7) << 10) + (((row >> 3) & 7) << 7) + ((row >> 6) * 40);
        int byteIndex = column / 7;
        Word(machine, "GBASL").Should().Be(address);
        machine.Memory[machine.Address("HighResByteIndex")].Should().Be((byte)byteIndex);
        machine.Cpu.Registers.Y.Should().Be((byte)byteIndex);
        machine.Memory[machine.Address("COLOR")].Should().Be((byte)(0x80 | (1 << (column % 7))));
        Word(machine, "HighResX").Should().Be(column);
        machine.Memory[machine.Address("HighResY")].Should().Be((byte)row);
        machine.Memory[machine.Address("HighResColorByte")].Should().Be(byteIndex % 2 == 0 ? (byte)0x2A : (byte)0x55);
    }

    /// <summary>
    ///  <c>HighRes::FindCoordinates</c> rebuilds the point <c>HighRes::Position</c> set from the address, byte and
    ///  mask.
    /// </summary>
    /// <param name="row">The row.</param>
    /// <param name="column">The column.</param>
    [TestMethod]
    [DataRow(0, 0)]
    [DataRow(9, 13)]
    [DataRow(100, 200)]
    [DataRow(191, 279)]
    public void FindCoordinatesInvertsPosition(int row, int column)
    {
        BasicMathMachine machine = new(apple: true);
        machine.Memory[machine.Address("HighResPage")] = Page1;
        machine.Call("HighRes::Position", a: row, x: column & 0xFF, y: column >> 8);
        Word(machine, "HighResX", 0xFFFF);
        machine.Memory[machine.Address("HighResY")] = 0xFF;

        machine.Call("HighRes::FindCoordinates");

        Word(machine, "HighResX").Should().Be(column);
        machine.Memory[machine.Address("HighResY")].Should().Be((byte)row);
    }

    /// <summary>
    ///  <c>HighRes::StepHorizontal</c> moves the mask one pixel right within a byte, takes the next byte's first pixel
    ///  past the last, wraps from byte 39 to 0 rather than stopping, and moves left from a byte's first pixel to the
    ///  previous byte's last, wrapping from 0 to 39; a new byte flips an alternating color to keep it in phase.
    /// </summary>
    /// <param name="mask">The pixel mask in <c>COLOR</c>.</param>
    /// <param name="byteIndex">The byte, in Y.</param>
    /// <param name="left">Whether to step left (negative set).</param>
    /// <param name="expectedMask">The mask after the step.</param>
    /// <param name="expectedByte">The byte after the step.</param>
    [TestMethod]
    [DataRow(0x81, 5, false, 0x82, 5)]
    [DataRow(0xC0, 5, false, 0x81, 6)]
    [DataRow(0xC0, 39, false, 0x81, 0)]
    [DataRow(0x82, 5, true, 0x81, 5)]
    [DataRow(0x81, 5, true, 0xC0, 4)]
    [DataRow(0x81, 0, true, 0xC0, 39)]
    public void StepHorizontalCrossesBytesAndWrapsWithinTheRow(
        int mask, int byteIndex, bool left, int expectedMask, int expectedByte)
    {
        BasicMathMachine machine = new(apple: true);
        machine.Memory[machine.Address("COLOR")] = (byte)mask;
        machine.Memory[machine.Address("HighResByteIndex")] = (byte)byteIndex;
        machine.Memory[machine.Address("HighResColorByte")] = 0x2A;

        // A contradicts the flag, since the direction is the flag the caller's load left, not A.
        machine.Call("HighRes::StepHorizontal", a: left ? 0x00 : 0x80, y: byteIndex, negative: left);

        bool newByte = expectedByte != byteIndex;
        machine.Memory[machine.Address("COLOR")].Should().Be((byte)expectedMask);
        machine.Cpu.Registers.Y.Should().Be((byte)expectedByte);
        machine.Memory[machine.Address("HighResByteIndex")].Should().Be((byte)expectedByte);
        machine.Memory[machine.Address("HighResColorByte")].Should().Be(
            newByte ? (byte)0x55 : (byte)0x2A, "an alternating color flips for the next byte");
    }

    /// <summary>
    ///  The enhanced IIe's <c>UppercaseCharacter</c> clears bits 5 and 7 of a character at or above <c>a</c>, folding
    ///  $7B-$7F to $5B-$5F and clearing bit 7 from $80 up, and leaves anything below <c>a</c> unchanged.
    /// </summary>
    /// <param name="character">The character.</param>
    /// <param name="expected">The result.</param>
    [TestMethod]
    [DataRow(0x61, 0x41)]
    [DataRow(0x7A, 0x5A)]
    [DataRow(0x7B, 0x5B)]
    [DataRow(0x7F, 0x5F)]
    [DataRow(0x60, 0x60)]
    [DataRow(0x41, 0x41)]
    [DataRow(0x31, 0x31)]
    [DataRow(0xE1, 0x41)]
    [DataRow(0xC1, 0x41)]
    public void UppercaseCharacterClearsBitFiveFromLowercaseA(int character, int expected)
    {
        BasicMathMachine machine = new(apple: true);

        machine.Call("UppercaseCharacter", a: character);

        machine.Cpu.Registers.Accumulator.Should().Be((byte)expected);
    }

    /// <summary>
    ///  The enhanced IIe's <c>DistanceToColumn</c> returns X less <c>TerminalPosition</c> with 40 columns, carry set
    ///  where there is no borrow; with 80 columns it subtracts <c>OURCH</c> with the caller's carry.
    /// </summary>
    /// <param name="eighty">Whether 80 columns are on.</param>
    /// <param name="target">The target column, in X.</param>
    /// <param name="column">The output column.</param>
    /// <param name="carry">The caller's carry.</param>
    [TestMethod]
    [DataRow(false, 10, 3, false)]
    [DataRow(false, 3, 10, true)]
    [DataRow(true, 50, 20, true)]
    [DataRow(true, 50, 20, false)]
    [DataRow(true, 20, 50, true)]
    public void DistanceToColumnSubtractsTheOutputColumn(bool eighty, int target, int column, bool carry)
    {
        BasicMathMachine machine = new(apple: true);
        machine.Memory[Rd80Vid] = eighty ? (byte)0x80 : (byte)0x00;
        machine.Memory[machine.Address(eighty ? "OURCH" : "TerminalPosition")] = (byte)column;

        machine.Call("DistanceToColumn", x: target, carry: carry);

        int borrow = eighty && !carry ? 1 : 0;
        int difference = target - column - borrow;
        machine.Cpu.Registers.Accumulator.Should().Be((byte)difference);
        machine.Cpu.Registers.Status.HasFlag(StatusRegister.Carry).Should().Be(difference >= 0);
    }

    /// <summary>
    ///  The enhanced IIe's <c>CompareCommaColumn</c> returns the column in A and carry set at or past the limit (33, or
    ///  73 with 80 columns); with 80 columns negative is set below 73, and with 40 columns it is clear.
    /// </summary>
    /// <param name="eighty">Whether 80 columns are on.</param>
    /// <param name="column">The output column.</param>
    [TestMethod]
    [DataRow(false, 10)]
    [DataRow(false, 33)]
    [DataRow(false, 39)]
    [DataRow(true, 10)]
    [DataRow(true, 72)]
    [DataRow(true, 73)]
    public void CompareCommaColumnReportsTheLimit(bool eighty, int column)
    {
        BasicMathMachine machine = new(apple: true);
        machine.Memory[Rd80Vid] = eighty ? (byte)0x80 : (byte)0x00;
        machine.Memory[machine.Address(eighty ? "OURCH" : "TerminalPosition")] = (byte)column;

        machine.Call("CompareCommaColumn");

        int limit = eighty ? 73 : 33;
        machine.Cpu.Registers.Accumulator.Should().Be((byte)column);
        machine.Cpu.Registers.Status.HasFlag(StatusRegister.Carry).Should().Be(column >= limit);
        machine.Cpu.Registers.Status.HasFlag(StatusRegister.Negative).Should().Be(eighty && column < limit);
    }

    private static int Word(BasicMathMachine machine, string name)
    {
        int address = machine.Address(name);
        return machine.Memory[address] | (machine.Memory[address + 1] << 8);
    }

    private static void Word(BasicMathMachine machine, string name, int value)
    {
        int address = machine.Address(name);
        machine.Memory[address] = (byte)value;
        machine.Memory[address + 1] = (byte)(value >> 8);
    }
}
