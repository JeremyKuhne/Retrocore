// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using Retrocore.Assembler;

namespace Retrocore.Tests;

/// <summary>
///  A BASIC build's image in flat memory for running its math routines, with a caller in page 3 and <c>Fac</c>'s
///  value in and out.
/// </summary>
internal sealed class BasicMathMachine
{
    // A JSR to the routine, then a loop the routine returns to.
    private const ushort Caller = 0x0300;
    private const ushort Returned = Caller + 3;

    private readonly AssemblyResult _build;
    private readonly RecordingBus _bus = new();

    /// <summary>
    ///  Loads the enhanced IIe's AppleSoft or PET BASIC 4.
    /// </summary>
    /// <param name="apple">Whether to load AppleSoft.</param>
    public BasicMathMachine(bool apple)
    {
        _build = BasicNames.AssembleMath(apple);
        _build.Success.Should().BeTrue();
        _build.Sections[0].Bytes.Span.CopyTo(_bus.Memory);
        Cpu = new(_bus);
    }

    /// <summary>
    ///  Gets the processor.
    /// </summary>
    public Processor<RecordingBus> Cpu { get; }

    /// <summary>
    ///  Gets the memory.
    /// </summary>
    public byte[] Memory => _bus.Memory;

    /// <summary>
    ///  Gets a definition's address, by its current or old name.
    /// </summary>
    /// <param name="name">The name.</param>
    /// <returns>The address.</returns>
    public int Address(string name) => checked((int)_build.Symbol(name));

    /// <summary>
    ///  Gets four bytes as an integer, high byte first.
    /// </summary>
    /// <param name="address">The first byte's address.</param>
    /// <returns>The integer.</returns>
    public uint BigEndian(int address) =>
        System.Buffers.Binary.BinaryPrimitives.ReadUInt32BigEndian(Memory.AsSpan(address, 4));

    /// <summary>
    ///  Gets <c>Fac</c>'s value: the unpacked mantissa as a fraction, scaled by the exponent, with the sign byte's
    ///  bit 7.
    /// </summary>
    public double Fac
    {
        get
        {
            int exponent = Memory[Address("FacExponent")];
            if (exponent == 0) { return 0; }
            double magnitude = Math.ScaleB(BigEndian(Address("FacMantissa1")) / 4294967296.0, exponent - 128);
            return (Memory[Address("FacSign")] & 0x80) != 0 ? -magnitude : magnitude;
        }
    }

    /// <summary>
    ///  Sets <c>Fac</c> to a value, with a clear extension.
    /// </summary>
    /// <param name="value">The value, which the format must hold exactly.</param>
    public void SetFac(double value)
    {
        byte[] packed = Packed(value);
        Memory[Address("FacExponent")] = packed[0];
        int mantissa = Address("FacMantissa1");
        Memory[mantissa] = (byte)(packed[1] | 0x80);
        Memory[mantissa + 1] = packed[2];
        Memory[mantissa + 2] = packed[3];
        Memory[mantissa + 3] = packed[4];
        Memory[Address("FacSign")] = (byte)(packed[1] & 0x80);
        Memory[Address("FacExtension")] = 0;
    }

    /// <summary>
    ///  Stores a value in the five-byte format.
    /// </summary>
    /// <param name="address">Where to store it.</param>
    /// <param name="value">The value, which the format must hold exactly.</param>
    public void Pack(int address, double value) => Packed(value).CopyTo(Memory, address);

    /// <summary>
    ///  Gets a value in Microsoft's five-byte format: the exponent biased by $80, then the mantissa, whose top
    ///  bit is the sign.
    /// </summary>
    /// <param name="value">The value, which the format must hold exactly.</param>
    /// <returns>The five bytes.</returns>
    public static byte[] Packed(double value)
    {
        if (value == 0) { return new byte[5]; }
        int exponent = Math.ILogB(Math.Abs(value)) + 1;
        exponent.Should().BeInRange(-127, 127, $"{value} must be in the format's range");
        double scaled = Math.ScaleB(Math.Abs(value), 32 - exponent);
        scaled.Should().Be(Math.Floor(scaled), $"{value} must fit the format's 32-bit mantissa exactly");
        uint fraction = checked((uint)scaled);
        fraction.Should().BeGreaterThanOrEqualTo(0x80000000u);
        return
        [
            (byte)(exponent + 128),
            (byte)(((fraction >> 24) & 0x7F) | (value < 0 ? 0x80u : 0)),
            (byte)(fraction >> 16),
            (byte)(fraction >> 8),
            (byte)fraction
        ];
    }

    /// <summary>
    ///  Calls a routine from page 3 and runs until it returns there.
    /// </summary>
    /// <param name="routine">The routine's name.</param>
    /// <param name="a">The value in A.</param>
    /// <param name="x">The value in X.</param>
    /// <param name="y">The value in Y.</param>
    /// <param name="carry">Whether carry is set.</param>
    /// <param name="negative">
    ///  Whether negative is set, for a routine that tests the flag its caller's load left.
    /// </param>
    public void Call(string routine, int a = 0, int x = 0, int y = 0, bool carry = false, bool negative = false) =>
        CallUntil(routine, [], a, x, y, carry, negative);

    /// <summary>
    ///  Calls a routine from page 3 and runs until it returns there or reaches one of the given addresses.
    /// </summary>
    /// <param name="routine">The routine's name.</param>
    /// <param name="stops">The addresses to stop at.</param>
    /// <param name="a">The value in A.</param>
    /// <param name="x">The value in X.</param>
    /// <param name="y">The value in Y.</param>
    /// <param name="carry">Whether carry is set.</param>
    /// <param name="negative">Whether negative is set.</param>
    /// <returns>The address reached: a stop, or the caller's return.</returns>
    public int CallUntil(
        string routine, int[] stops, int a = 0, int x = 0, int y = 0, bool carry = false, bool negative = false)
    {
        ushort target = checked((ushort)_build.Symbol(routine));
        Memory[Caller] = 0x20;
        Memory[Caller + 1] = (byte)target;
        Memory[Caller + 2] = (byte)(target >> 8);
        Memory[Returned] = 0x4C;
        Memory[Returned + 1] = Returned & 0xFF;
        Memory[Returned + 2] = (byte)(Returned >> 8);
        Cpu.Registers = new()
        {
            ProgramCounter = Caller,
            Accumulator = (byte)a,
            X = (byte)x,
            Y = (byte)y,
            StackPointer = 0xF0,
            Status = StatusRegister.Unused
                | (carry ? StatusRegister.Carry : 0)
                | (negative ? StatusRegister.Negative : 0)
        };

        for (int instruction = 0; instruction < 200_000; instruction++)
        {
            Cpu.StepInstruction();
            int counter = Cpu.Registers.ProgramCounter;
            if (counter == Returned || stops.Contains(counter)) { return counter; }
        }

        throw new AssertFailedException($"{routine} did not return.");
    }
}
