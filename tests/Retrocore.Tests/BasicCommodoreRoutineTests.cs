// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using Retrocore.Machines.Commodore;

namespace Retrocore.Tests;

/// <summary>
///  Runs routines of Commodore's own files (Basic.md, F) in the shipped PET builds: BASIC 4's string links and clock
///  string, and BASIC 1's editor-ROM patches, and checks what their documentation says they take, return and keep.
/// </summary>
[TestClass]
public sealed class BasicCommodoreRoutineTests
{
    // Where a test's descriptor and string are placed.
    private const int Descriptor = 0x0400;
    private const int Text = 0x0500;

    private const byte KeptX = 0x5A;
    private const byte KeptY = 0xA5;

    /// <summary>
    ///  <c>FindStringLink</c> finds a nonempty string's link in string space, giving its address in <c>Pointer1</c>, the
    ///  length in X and Y = 2, with carry set.
    /// </summary>
    /// <param name="original">Whether to run the original chip.</param>
    [TestMethod]
    [DataRow(data: false)]
    [DataRow(data: true)]
    public void FindStringLinkFindsALiveStringsLink(bool original)
    {
        PetRoutineMachine machine = new(PetModel.Pet4032, original);
        SetStringsBottom(machine, 0x3000);
        WriteDescriptor(machine, length: 5, address: 0x3456);

        machine.Call("FindStringLink");

        machine.Carry.Should().BeTrue();
        machine.Word("Pointer1").Should().Be(0x3456 + 5);
        machine.Cpu.Registers.X.Should().Be(5);
        machine.Cpu.Registers.Y.Should().Be(2);
    }

    /// <summary>
    ///  <c>FindStringLink</c> gives carry clear, with the length in A, for an empty string (Y = 0), one in ROM or I/O and
    ///  one below <c>StringsBottom</c> (Y = 2).
    /// </summary>
    /// <param name="length">The string's length.</param>
    /// <param name="address">The string's address.</param>
    [TestMethod]
    [DataRow(0, 0x3456)]
    [DataRow(4, 0x9000)]
    [DataRow(4, 0x2FFF)]
    public void FindStringLinkFindsNoLinkOutsideStringSpace(int length, int address)
    {
        PetRoutineMachine machine = new(PetModel.Pet4032, original: false);
        SetStringsBottom(machine, 0x3000);
        WriteDescriptor(machine, length, address);

        machine.Call("FindStringLink");

        machine.Carry.Should().BeFalse();
        machine.Cpu.Registers.Accumulator.Should().Be((byte)length);
        machine.Cpu.Registers.Y.Should().Be(length == 0 ? (byte)0 : (byte)2);
    }

    /// <summary>
    ///  <c>FindStringLink</c> gives `DS$`'s characters no link. The original chip compares their address alone, so a
    ///  string at a released (empty) `DS$`'s address is not linked either; the revised chip's <c>TestStatusString</c>
    ///  links it.
    /// </summary>
    /// <param name="original">Whether to run the original chip.</param>
    /// <param name="statusLength">The disk status's length: zero once released.</param>
    /// <param name="linked">Whether a link is found.</param>
    [TestMethod]
    [DataRow(false, 40, false)]
    [DataRow(true, 40, false)]
    [DataRow(false, 0, true)]
    [DataRow(true, 0, false)]
    public void FindStringLinkSkipsTheDiskStatus(bool original, int statusLength, bool linked)
    {
        PetRoutineMachine machine = new(PetModel.Pet4032, original);
        SetStringsBottom(machine, 0x3000);
        int status = machine.Address("DiskStatusDescriptor");
        machine.Memory[status] = (byte)statusLength;
        machine.Memory[status + 1] = 0x56;
        machine.Memory[status + 2] = 0x34;
        WriteDescriptor(machine, length: 3, address: 0x3456);

        machine.Call("FindStringLink");

        machine.Carry.Should().Be(linked);
    }

    /// <summary>
    ///  BASIC 1's <c>GetDataLine</c> gives <c>DataLine</c> in A and Y for `READ` (negative set) and Y = $FF for `GET`.
    /// </summary>
    /// <param name="read">Whether the input is `READ`.</param>
    [TestMethod]
    [DataRow(data: true)]
    [DataRow(data: false)]
    public void GetDataLineGivesTheErrorsLine(bool read)
    {
        PetRoutineMachine machine = new(PetModel.Pet2001, original: false);
        int dataLine = machine.Address("DataLine");
        machine.Memory[dataLine] = 0x34;
        machine.Memory[dataLine + 1] = 0x12;

        // The negative flag is the caller's, from InputMode's load.
        machine.Call("GetDataLine", a: read ? 0x98 : 0x40, x: KeptX, y: KeptY, negative: read);

        if (read)
        {
            machine.Cpu.Registers.Accumulator.Should().Be(0x34);
            machine.Cpu.Registers.Y.Should().Be(0x12);
        }
        else
        {
            machine.Cpu.Registers.Y.Should().Be(0xFF);
        }

        machine.Cpu.Registers.X.Should().Be(KeptX);
    }

    /// <summary>
    ///  BASIC 1's <c>ArrayHeaderSize</c> gives two bytes per dimension plus five, adding the shift's carry, with Y = 0,
    ///  and keeps X.
    /// </summary>
    /// <param name="dimensions">The dimension count.</param>
    /// <param name="size">The size.</param>
    [TestMethod]
    [DataRow(1, 7)]
    [DataRow(3, 11)]
    [DataRow(0x81, 8)]
    public void ArrayHeaderSizeGivesTheHeadersSize(int dimensions, int size)
    {
        PetRoutineMachine machine = new(PetModel.Pet2001, original: false);
        machine.Call("ArrayHeaderSize", a: dimensions, x: KeptX, y: KeptY);

        machine.Cpu.Registers.Accumulator.Should().Be((byte)size);
        machine.Cpu.Registers.Y.Should().Be(0);
        machine.Cpu.Registers.X.Should().Be(KeptX);
    }

    /// <summary>
    ///  BASIC 1's <c>AdvanceTerminalPosition</c> counts a column for the screen only, and after a wrap to zero restarts
    ///  from the editor's column.
    /// </summary>
    /// <param name="screen">Whether the output goes to the screen (zero set).</param>
    /// <param name="before">The column before.</param>
    /// <param name="after">The column after.</param>
    [TestMethod]
    [DataRow(true, 7, 8)]
    [DataRow(false, 7, 7)]
    [DataRow(true, 0xFF, 0x13)]
    public void AdvanceTerminalPositionCountsScreenOutput(bool screen, int before, int after)
    {
        PetRoutineMachine machine = new(PetModel.Pet2001, original: false);
        int position = machine.Address("TerminalPosition");
        machine.Memory[position] = (byte)before;
        machine.Memory[machine.Address("EditorCursorColumn")] = 0x12;

        machine.Call("AdvanceTerminalPosition", x: KeptX, y: KeptY, zero: screen);

        machine.Memory[position].Should().Be((byte)after);
        machine.Cpu.Registers.X.Should().Be(KeptX);
        machine.Cpu.Registers.Y.Should().Be(KeptY);
    }

    /// <summary>
    ///  BASIC 1's <c>CheckClockString</c> and <c>RouteNumericVariable</c> send `TI$`, `TI`, the other reserved variables
    ///  and ordinary ones each to its part of <c>LoadVariableValue</c>, or return.
    /// </summary>
    /// <param name="routine">The routine.</param>
    /// <param name="name">The name's first character.</param>
    /// <param name="reserved">Whether the value is in the reserved variables' area.</param>
    /// <param name="destination">Where it goes: a label, or empty for a return.</param>
    [TestMethod]
    [DataRow("CheckClockString", 'T', true, "LoadVariableValue::MatchClockString")]
    [DataRow("CheckClockString", 'S', true, "")]
    [DataRow("CheckClockString", 'T', false, "")]
    [DataRow("RouteNumericVariable", 'T', true, "LoadVariableValue::MatchClockNumber")]
    [DataRow("RouteNumericVariable", 'S', true, "LoadVariableValue::MatchStatus")]
    [DataRow("RouteNumericVariable", 'T', false, "LoadVariableValue::LoadFloat")]
    public void ClockPatchesRouteTheReservedVariables(string routine, char name, bool reserved, string destination)
    {
        PetRoutineMachine machine = new(PetModel.Pet2001, original: false);
        machine.Memory[machine.Address("FacMantissa4")] = reserved ? (byte)0xC0 : (byte)0x10;
        int[] stops = destination.Length == 0 ? [] : [machine.Address(destination)];

        int reached = machine.CallUntil(routine, stops, a: name, y: 'I');

        reached.Should().Be(destination.Length == 0 ? PetRoutineMachine.Returned : machine.Address(destination));
    }

    /// <summary>
    ///  <c>AssignClockString</c> sets <c>JiffyClock</c> to `TI$`'s time in sixtieths of a second, taking any byte
    ///  from `0` up as a digit counted from `0`.
    /// </summary>
    /// <param name="model">The PET model.</param>
    /// <param name="time">The string.</param>
    /// <param name="ticks">The clock's value.</param>
    [TestMethod]
    [DataRow(PetModel.Pet2001, "000001", 60)]
    [DataRow(PetModel.Pet2001Basic2, "010000", 216000)]
    [DataRow(PetModel.Pet4032, "123456", 12 * 216000 + 34 * 3600 + 56 * 60)]
    [DataRow(PetModel.Pet4032, "999999", 99 * 216000 + 99 * 3600 + 99 * 60)]
    [DataRow(PetModel.Pet2001, "1A0000", 27 * 216000)]
    [DataRow(PetModel.Pet4032, "00:000", 100 * 3600)]
    public void AssignClockStringSetsTheClock(PetModel model, string time, int ticks)
    {
        PetRoutineMachine machine = new(model, original: false);
        SetClockString(machine, time);

        int error = machine.Address("IllegalQuantityError");
        machine.CallUntil("AssignClockString", [error]).Should().Be(PetRoutineMachine.Returned);

        int clock = machine.Address("JiffyClock");
        int value = (machine.Memory[clock] << 16) | (machine.Memory[clock + 1] << 8) | machine.Memory[clock + 2];
        value.Should().Be(ticks & 0xFFFFFF);
    }

    /// <summary>
    ///  <c>AssignClockString</c> reports ILLEGAL QUANTITY for a string that is not six characters, or has one below `0`.
    /// </summary>
    /// <param name="model">The PET model.</param>
    /// <param name="time">The string.</param>
    [TestMethod]
    [DataRow(PetModel.Pet2001, "12345")]
    [DataRow(PetModel.Pet2001, "12-456")]
    [DataRow(PetModel.Pet4032, "1234567")]
    [DataRow(PetModel.Pet4032, "12345/")]
    public void AssignClockStringRejectsABadString(PetModel model, string time)
    {
        PetRoutineMachine machine = new(model, original: false);
        SetClockString(machine, time);
        int error = machine.Address("IllegalQuantityError");

        machine.CallUntil("AssignClockString", [error]).Should().Be(error);
    }

    /// <summary>
    ///  <c>AssignClockString</c> passes an assignment to any variable but `TI$` on to <c>StoreString</c>.
    /// </summary>
    [TestMethod]
    public void AssignClockStringPassesOtherVariablesOn()
    {
        PetRoutineMachine machine = new(PetModel.Pet4032, original: false);
        SetClockString(machine, "123456");
        machine.Memory[machine.Address("AssignedVariable") + 1] = 0x20;
        int store = machine.Address("StoreString");

        machine.CallUntil("AssignClockString", [store]).Should().Be(store);
    }

    // Puts a string in a descriptor for the clock assignment, with TI$'s reserved address as the destination.
    private static void SetClockString(PetRoutineMachine machine, string time)
    {
        WriteDescriptor(machine, time.Length, Text);
        System.Text.Encoding.ASCII.GetBytes(time).CopyTo(machine.Memory, Text);
        int variable = machine.Address("AssignedVariable");
        machine.Memory[variable] = 0x00;
        machine.Memory[variable + 1] = (byte)(machine.Address("ZeroValue") >> 8);

        // No temporary descriptors are in use, so the release leaves the string alone.
        machine.Memory[machine.Address("NextTemporary")] = (byte)machine.Address("TemporaryDescriptors");
        SetStringsBottom(machine, 0x7000);
        machine.Memory[machine.Address("FacMantissa3")] = Descriptor & 0xFF;
        machine.Memory[machine.Address("FacMantissa4")] = Descriptor >> 8;
    }

    private static void WriteDescriptor(PetRoutineMachine machine, int length, int address)
    {
        machine.Memory[Descriptor] = (byte)length;
        machine.Memory[Descriptor + 1] = (byte)address;
        machine.Memory[Descriptor + 2] = (byte)(address >> 8);
        int pointer = machine.Address("Pointer1");
        machine.Memory[pointer] = Descriptor & 0xFF;
        machine.Memory[pointer + 1] = Descriptor >> 8;
    }

    private static void SetStringsBottom(PetRoutineMachine machine, int address)
    {
        int bottom = machine.Address("StringsBottom");
        machine.Memory[bottom] = (byte)address;
        machine.Memory[bottom + 1] = (byte)(address >> 8);
    }
}
