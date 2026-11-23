// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Tests;

/// <summary>
///  Runs the converted interpreter files' routines (Basic.md, C) in the shipped AppleSoft and PET BASIC 4 builds and
///  checks what their documentation says they take and return.
/// </summary>
[TestClass]
public sealed class BasicInterpreterRoutineTests
{
    // Where a stub records the byte it was handed; clear of the caller BasicMathMachine writes at $0300.
    private const int Recorded = 0x0310;

    // The opcodes the stubs are written with.
    private const byte LdxImmediate = 0xA2;
    private const byte LdaImmediate = 0xA9;
    private const byte StaAbsolute = 0x8D;
    private const byte Rts = 0x60;

    // PRINT's token in each dialect.
    private const byte AppleSoftPrintToken = 0xBA;
    private const byte PetPrintToken = 0x99;

    /// <summary>
    ///  AppleSoft's <c>InputLine</c> reads a line through the Monitor's <c>GETLN</c> with no visible prompt, keeps at
    ///  most 239 characters, clears bit 7 of each and ends them with a zero; it returns zero in A and the address
    ///  before the buffer in X and Y.
    /// </summary>
    /// <param name="length">The length <c>GETLN</c> returns in X.</param>
    [TestMethod]
    [DataRow(0)]
    [DataRow(3)]
    [DataRow(239)]
    [DataRow(245)]
    public void InputLineClearsBitSevenAndEndsTheLine(int length)
    {
        BasicMathMachine machine = new(apple: true);
        int buffer = machine.Address("BUF");
        for (int index = 0; index < 250; index++)
        {
            machine.Memory[buffer + index] = (byte)(0xC1 + (index % 26));
        }

        int getLine = machine.Address("GETLN");
        machine.Memory[getLine] = LdxImmediate;
        machine.Memory[getLine + 1] = (byte)length;
        machine.Memory[getLine + 2] = Rts;

        machine.Call("InputLine", a: 0x55, x: 0x66, y: 0x77);

        int kept = Math.Min(length, 239);
        machine.Memory[machine.Address("PROMPT")].Should().Be(0x80, "the prompt prints as nothing");
        machine.Memory[buffer + kept].Should().Be(0);
        for (int index = 0; index < kept; index++)
        {
            machine.Memory[buffer + index].Should().Be((byte)(0x41 + (index % 26)));
        }

        machine.Cpu.Registers.Accumulator.Should().Be(0);
        machine.Cpu.Registers.X.Should().Be((byte)(buffer - 1));
        machine.Cpu.Registers.Y.Should().Be((byte)((buffer - 1) >> 8));
    }

    /// <summary>
    ///  <c>Tokenize</c> encodes the line at <c>TextPointer</c> in place, a reserved word as its token and the rest as
    ///  typed, ending it with a zero; it leaves <c>TextPointer</c> at the address before the buffer and Y at the
    ///  encoded line's length with its four-byte header (link and line number).
    /// </summary>
    /// <param name="apple">Whether to run AppleSoft rather than PET BASIC 4.</param>
    [TestMethod]
    [DataRow(data: true)]
    [DataRow(data: false)]
    public void TokenizeEncodesTheLineInPlace(bool apple)
    {
        BasicMathMachine machine = new(apple);
        int buffer = machine.Address(apple ? "BUF" : "InputBuffer");
        byte[] line = "PRINT1"u8.ToArray();
        line.CopyTo(machine.Memory, buffer);
        machine.Memory[buffer + line.Length] = 0;
        machine.Memory[buffer + line.Length + 1] = 0xEE;
        machine.Memory[buffer + line.Length + 2] = 0xEE;
        int textPointer = machine.Address("TextPointer");
        machine.Memory[textPointer] = (byte)buffer;
        machine.Memory[textPointer + 1] = (byte)(buffer >> 8);
        if (apple)
        {
            machine.Memory[machine.Address("RunOnly")] = 0;
        }

        machine.Call("Tokenize");

        byte print = apple ? AppleSoftPrintToken : PetPrintToken;
        byte[] encoded = [print, (byte)'1', 0];
        machine.Memory.AsSpan(buffer, encoded.Length).ToArray().Should().Equal(encoded);
        (machine.Memory[textPointer] | (machine.Memory[textPointer + 1] << 8)).Should().Be(buffer - 1);
        machine.Cpu.Registers.Y.Should().Be((byte)(4 + 3), "the header and the token, the digit and the zero");
    }

    /// <summary>
    ///  AppleSoft's <c>CheckStop</c> returns at once with the keyboard's byte in A, without reading the key, unless the
    ///  keyboard holds Control-C; then it reads the key through <c>InputCharacter</c>.
    /// </summary>
    /// <param name="key">The keyboard's byte.</param>
    [TestMethod]
    [DataRow(0x41)]
    [DataRow(0xC1)]
    [DataRow(0x83)]
    public void CheckStopReadsOnlyControlC(int key)
    {
        BasicMathMachine machine = new(apple: true);
        int keyboard = machine.Address("KBD");
        machine.Memory[keyboard] = (byte)key;
        int input = machine.Address("InputCharacter");

        int reached = machine.CallUntil("CheckStop", [input]);

        if (key == 0x83)
        {
            reached.Should().Be(input);
        }
        else
        {
            reached.Should().NotBe(input);
            machine.Cpu.Registers.Accumulator.Should().Be((byte)key);
        }
    }

    /// <summary>
    ///  AppleSoft's <c>PrintCharacter</c> sends the character with bit 7 set to <c>OUTCH</c>, with <c>FlashMask</c>
    ///  applied to a printable one only, and returns what the Monitor hands back with bit 7 clear.
    /// </summary>
    /// <param name="character">The character to print.</param>
    /// <param name="sent">The byte the Monitor receives.</param>
    [TestMethod]
    [DataRow(0x41, 0xE1)]
    [DataRow(0x0D, 0x8D)]
    public void AppleSoftPrintCharacterSetsBitSevenAndTheMask(int character, int sent)
    {
        BasicMathMachine machine = new(apple: true);
        machine.Memory[machine.Address("FlashMask")] = 0x20;
        machine.Memory[machine.Address("OutputDelay")] = 0;
        int output = machine.Address("OUTCH");
        machine.Memory[output] = StaAbsolute;
        machine.Memory[output + 1] = Recorded & 0xFF;
        machine.Memory[output + 2] = Recorded >> 8;
        machine.Memory[output + 3] = Rts;
        machine.Memory[machine.Address("MWAIT")] = Rts;

        machine.Call("PrintCharacter", a: character);

        machine.Memory[Recorded].Should().Be((byte)sent);
        machine.Cpu.Registers.Accumulator.Should().Be((byte)(sent & 0x7F));
    }

    /// <summary>
    ///  BASIC 4's <c>PrintCharacter</c> sends the character through <c>KernalCharacterOut</c> and returns the
    ///  kernal's A, with zero set when it is zero.
    /// </summary>
    /// <param name="returned">The A the kernal returns.</param>
    [TestMethod]
    [DataRow(0x00)]
    [DataRow(0x41)]
    [DataRow(0x80)]
    public void PetPrintCharacterReturnsTheKernalsResult(int returned)
    {
        BasicMathMachine machine = new(apple: false);
        int output = machine.Address("KernalCharacterOut");
        machine.Memory[output] = StaAbsolute;
        machine.Memory[output + 1] = Recorded & 0xFF;
        machine.Memory[output + 2] = Recorded >> 8;
        machine.Memory[output + 3] = LdaImmediate;
        machine.Memory[output + 4] = (byte)returned;
        machine.Memory[output + 5] = Rts;

        machine.Call("PrintCharacter", a: 0x5A);

        machine.Memory[Recorded].Should().Be(0x5A);
        machine.Cpu.Registers.Accumulator.Should().Be((byte)returned);
        machine.Cpu.Registers.Status.HasFlag(StatusRegister.Zero).Should().Be(returned == 0);
        machine.Cpu.Registers.Status.HasFlag(StatusRegister.Negative).Should().Be(returned >= 0x80);
    }
}
