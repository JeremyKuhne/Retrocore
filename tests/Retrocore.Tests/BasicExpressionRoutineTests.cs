// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Tests;

/// <summary>
///  Runs the converted expression, variable and string modules' routines (Basic.md, B2) in the shipped AppleSoft and
///  PET BASIC 4 builds and checks what their documentation says they take, return and keep.
/// </summary>
[TestClass]
public sealed class BasicExpressionRoutineTests
{
    // Where a test puts its text and its strings.
    private const int Text = 0x0900;
    private const int Source = 0x0A10;
    private const int Destination = 0x0AF8;

    // The value a routine that keeps X must hand back.
    private const int KeptX = 0x5A;

    /// <summary>
    ///  <c>Strings::CopyBytes</c> copies A bytes from <c>Pointer1</c> to <c>NewString</c>, across a page boundary,
    ///  and advances <c>NewString</c> past them; it returns the new low byte in A and zero in Y, and keeps X.
    ///  <c>Strings::CopyFrom</c> takes the source in X and Y, leaves it in <c>Pointer1</c> and keeps X too.
    /// </summary>
    /// <param name="apple">Whether to run AppleSoft rather than PET BASIC 4.</param>
    /// <param name="from">Whether to enter at <c>CopyFrom</c>, with the source in X and Y.</param>
    /// <param name="length">The number of bytes.</param>
    [TestMethod]
    [DataRow(true, false, 0)]
    [DataRow(true, false, 1)]
    [DataRow(true, false, 20)]
    [DataRow(true, true, 20)]
    [DataRow(false, false, 0)]
    [DataRow(false, false, 20)]
    [DataRow(false, true, 20)]
    public void CopyBytesAdvancesTheDestinationAndKeepsX(bool apple, bool from, int length)
    {
        BasicMathMachine machine = new(apple);
        for (int index = 0; index < 32; index++)
        {
            machine.Memory[Source + index] = (byte)(0x41 + index);
            machine.Memory[Destination + index] = 0xEE;
        }

        SetWord(machine, "NewString", Destination);
        if (from)
        {
            SetWord(machine, "Pointer1", 0);
            machine.Call("Strings::CopyFrom", a: length, x: Source & 0xFF, y: Source >> 8);
            machine.Cpu.Registers.X.Should().Be(Source & 0xFF, "CopyFrom keeps X, the source's low byte");
        }
        else
        {
            SetWord(machine, "Pointer1", Source);
            machine.Call("Strings::CopyBytes", a: length, x: KeptX, y: 0x77);
            machine.Cpu.Registers.X.Should().Be(KeptX);
        }

        Word(machine, "Pointer1").Should().Be(Source);
        Word(machine, "NewString").Should().Be(Destination + length);
        machine.Cpu.Registers.Accumulator.Should().Be((byte)(Destination + length));
        machine.Cpu.Registers.Y.Should().Be(0);
        for (int index = 0; index < 32; index++)
        {
            machine.Memory[Destination + index].Should().Be(index < length ? (byte)(0x41 + index) : (byte)0xEE);
        }
    }

    /// <summary>
    ///  <c>Strings::ReleaseTemporary</c> pops the descriptor in A and Y only when it is the latest temporary: it then
    ///  sets zero, returns zero in Y, makes the descriptor's low byte <c>NextTemporary</c> and lowers
    ///  <c>LastTemporary</c>'s low byte by a descriptor. Any other descriptor clears zero and changes nothing. X is kept
    ///  either way.
    /// </summary>
    /// <param name="apple">Whether to run AppleSoft rather than PET BASIC 4.</param>
    /// <param name="descriptor">The descriptor to release.</param>
    /// <param name="match">Whether it is the latest temporary.</param>
    [TestMethod]
    [DataRow(true, 0x0019, true)]
    [DataRow(true, 0x0016, false)]
    [DataRow(true, 0x0119, false)]
    [DataRow(false, 0x0019, true)]
    [DataRow(false, 0x0016, false)]
    public void ReleaseTemporaryPopsOnlyTheLatest(bool apple, int descriptor, bool match)
    {
        BasicMathMachine machine = new(apple);
        const int Latest = 0x0019;
        SetWord(machine, "LastTemporary", Latest);
        machine.Memory[machine.Address("NextTemporary")] = Latest + 3;

        machine.Call("Strings::ReleaseTemporary", a: descriptor & 0xFF, x: KeptX, y: descriptor >> 8);

        machine.Cpu.Registers.Status.HasFlag(StatusRegister.Zero).Should().Be(match);
        machine.Cpu.Registers.X.Should().Be(KeptX);
        if (match)
        {
            machine.Cpu.Registers.Y.Should().Be(0);
            machine.Memory[machine.Address("NextTemporary")].Should().Be(Latest);
            Word(machine, "LastTemporary").Should().Be(Latest - 3);
        }
        else
        {
            machine.Memory[machine.Address("NextTemporary")].Should().Be(Latest + 3);
            Word(machine, "LastTemporary").Should().Be(Latest);
        }
    }

    /// <summary>
    ///  <c>Variables::MultiplyUnsigned</c> returns <c>LinearIndex</c> times A:<c>Addend</c> in X (low) and A and Y
    ///  (high), leaving <c>LinearIndex</c> zero, and takes the OUT OF MEMORY jump on a product past 16 bits.
    /// </summary>
    /// <param name="apple">Whether to run AppleSoft rather than PET BASIC 4.</param>
    /// <param name="multiplicand">The value in <c>LinearIndex</c>.</param>
    /// <param name="multiplier">The value in A and <c>Addend</c>.</param>
    [TestMethod]
    [DataRow(true, 300, 200)]
    [DataRow(true, 0, 1234)]
    [DataRow(true, 65535, 1)]
    [DataRow(true, 300, 300)]
    [DataRow(true, 32768, 2)]
    [DataRow(false, 11, 5)]
    [DataRow(false, 256, 256)]
    public void MultiplyUnsignedReturnsTheProductOrRunsOutOfMemory(bool apple, int multiplicand, int multiplier)
    {
        BasicMathMachine machine = new(apple);
        SetWord(machine, "LinearIndex", multiplicand);
        machine.Memory[machine.Address("Addend")] = (byte)multiplier;
        int error = machine.Address("Variables::ElementAddress::ToOutOfMemoryError");

        int reached = machine.CallUntil("Variables::MultiplyUnsigned", [error], a: multiplier >> 8);

        int product = multiplicand * multiplier;
        if (product > 0xFFFF)
        {
            reached.Should().Be(error);
            return;
        }

        reached.Should().NotBe(error);
        machine.Cpu.Registers.X.Should().Be((byte)product);
        machine.Cpu.Registers.Accumulator.Should().Be((byte)(product >> 8));
        machine.Cpu.Registers.Y.Should().Be((byte)(product >> 8));
        Word(machine, "LinearIndex").Should().Be(0);
    }

    /// <summary>
    ///  Each build's <c>Strings::ReserveSpace</c> takes the space below <c>StringsBottom</c> when the new bottom is at
    ///  or above <c>ArraysEnd</c>, returning the length in A and the address in X, Y and <c>NewString</c>. AppleSoft's
    ///  unlinked allocator takes just the characters; BASIC 4's takes two bytes more, writes a link of the length and
    ///  $FF above them, and returns at once for a zero length with X = 0 and Y unchanged. One byte short of the room,
    ///  both collect garbage.
    /// </summary>
    /// <param name="apple">Whether to run AppleSoft rather than PET BASIC 4.</param>
    /// <param name="length">The number of characters.</param>
    /// <param name="spare">The bytes between <c>ArraysEnd</c> and the space a request needs.</param>
    [TestMethod]
    [DataRow(true, 10, 100)]
    [DataRow(true, 10, 0)]
    [DataRow(true, 10, -1)]
    [DataRow(true, 0, 5)]
    [DataRow(false, 10, 100)]
    [DataRow(false, 10, 0)]
    [DataRow(false, 10, -1)]
    [DataRow(false, 0, 5)]
    public void ReserveSpaceTakesTheRoomOrCollects(bool apple, int length, int spare)
    {
        BasicMathMachine machine = new(apple);
        const int Bottom = 0x3000;
        int link = apple ? 0 : 2;
        int needed = length == 0 ? 0 : length + link;
        SetWord(machine, "StringsBottom", Bottom);
        SetWord(machine, "ArraysEnd", Bottom - needed - spare);
        SetWord(machine, "NewString", 0x1234);
        machine.Memory[machine.Address("CollectionState")] = 0;
        int collect = machine.Address("Strings::CollectGarbage");

        int reached = machine.CallUntil("Strings::ReserveSpace", [collect], a: length, x: 0x99, y: 0x66);

        if (spare < 0)
        {
            reached.Should().Be(collect, "a request without room collects garbage");
            return;
        }

        reached.Should().NotBe(collect);
        if (!apple && length == 0)
        {
            machine.Cpu.Registers.X.Should().Be(0);
            machine.Cpu.Registers.Y.Should().Be(0x66);
            Word(machine, "StringsBottom").Should().Be(Bottom);
            Word(machine, "NewString").Should().Be(0x1234);
            return;
        }

        int address = Bottom - needed;
        machine.Cpu.Registers.Accumulator.Should().Be((byte)length);
        machine.Cpu.Registers.X.Should().Be((byte)address);
        machine.Cpu.Registers.Y.Should().Be((byte)(address >> 8));
        Word(machine, "NewString").Should().Be(address);
        Word(machine, "StringsBottom").Should().Be(address);
        if (!apple)
        {
            machine.Memory[address + length].Should().Be((byte)length, "the link's first byte is the length");
            machine.Memory[address + length + 1].Should().Be(0xFF, "the link marks the string as garbage");
        }
    }

    /// <summary>
    ///  <c>EvaluateByte</c> returns a numeric expression's value in X and the character after it in A, with
    ///  <c>TextPointer</c> on that character; a value past 255 is an ILLEGAL QUANTITY error.
    /// </summary>
    /// <param name="apple">Whether to run AppleSoft rather than PET BASIC 4.</param>
    /// <param name="text">The expression, with each build's multiply token ($CA, $AC), and what follows it.</param>
    /// <param name="value">The value, or -1 for the error.</param>
    [TestMethod]
    [DataRow(true, "200:", 200)]
    [DataRow(true, "7,", 7)]
    [DataRow(true, "255\0", 255)]
    [DataRow(true, "256:", -1)]
    [DataRow(true, "2\u00CA3:", 6)]
    [DataRow(false, "2\u00AC3:", 6)]
    [DataRow(false, "300:", -1)]
    public void EvaluateByteReturnsTheValueAndTheNextCharacter(bool apple, string text, int value)
    {
        BasicMathMachine machine = new(apple);
        InstallCharacterReader(machine);
        for (int index = 0; index < text.Length; index++)
        {
            machine.Memory[Text + index] = (byte)text[index];
        }

        SetWord(machine, "TextPointer", Text);
        int error = machine.Address("IllegalQuantityError");

        int reached = machine.CallUntil("EvaluateByte", [error], a: text[0]);

        if (value < 0)
        {
            reached.Should().Be(error);
            return;
        }

        reached.Should().NotBe(error);
        int end = text.IndexOfAny([':', ',', '\0']);
        machine.Cpu.Registers.X.Should().Be((byte)value);
        machine.Cpu.Registers.Accumulator.Should().Be((byte)text[end]);
        Word(machine, "TextPointer").Should().Be(Text + end);
    }

    // Copies the character reader's template where startup copies it, as the build's own copy loop does.
    private static void InstallCharacterReader(BasicMathMachine machine)
    {
        int template = machine.Address("CharacterReaderTemplate");
        int reader = machine.Address("GetNextCharacter");
        machine.Memory.AsSpan(template, 24).CopyTo(machine.Memory.AsSpan(reader));
    }

    private static void SetWord(BasicMathMachine machine, string name, int value)
    {
        int address = machine.Address(name);
        machine.Memory[address] = (byte)value;
        machine.Memory[address + 1] = (byte)(value >> 8);
    }

    private static int Word(BasicMathMachine machine, string name)
    {
        int address = machine.Address(name);
        return machine.Memory[address] | (machine.Memory[address + 1] << 8);
    }
}
