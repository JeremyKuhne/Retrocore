// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using Retrocore.Machines.Apple2;

namespace Retrocore.Tests;

/// <summary>
///  Verifies the mouse card: its firmware's identification and routines, run on the emulated CPU, its interrupts and
///  BASIC's IN#/PR# interface.
/// </summary>
[TestClass]
public sealed class Apple2MouseTests
{
    private const ushort Caller = 0x2000;

    /// <summary>
    ///  The card's ROM page carries the bytes programs look for to find a mouse, in whatever slot it is in.
    /// </summary>
    /// <param name="slot">The card's slot.</param>
    [TestMethod]
    [DataRow(2)]
    [DataRow(4)]
    [DataRow(5)]
    public void FirmwareIdentifiesTheMouse(int slot)
    {
        Apple2Machine machine = Machine(Apple2Model.IIe, slot);
        ushort page = (ushort)(0xC000 | (slot << 8));
        machine.Bus.Peek((ushort)(page + 0x05)).Should().Be(0x38);
        machine.Bus.Peek((ushort)(page + 0x07)).Should().Be(0x18);
        machine.Bus.Peek((ushort)(page + 0x0B)).Should().Be(0x01);
        machine.Bus.Peek((ushort)(page + 0x0C)).Should().Be(0x20);
        machine.Bus.Peek((ushort)(page + 0xFB)).Should().Be(0xD6);
        machine.Bus.Peek((ushort)(page + 0x14)).Should().Be((byte)(MouseRom.READMOUSE & 255));
        machine.Bus.ReadArea(page).Should().Be(Apple2MemoryArea.Slot1Rom + (slot - 1));
        machine.Bus.PeekArea(Apple2MemoryArea.Slot1Rom + (slot - 1), (ushort)(page + 0xFB), out byte value).Should().BeTrue();
        value.Should().Be(0xD6);
        MouseRom.Bytes.Length.Should().Be(256);
    }

    /// <summary>
    ///  INITMOUSE, SETMOUSE and READMOUSE: the mouse follows the host only once on, and READMOUSE puts the position,
    ///  button and movement in the slot's screen holes. Y and the interrupt flag come back as they went in.
    /// </summary>
    /// <param name="model">The model, whose processor runs the firmware.</param>
    [TestMethod]
    [DataRow(Apple2Model.IIe)]
    [DataRow(Apple2Model.IIeEnhanced)]
    [DataRow(Apple2Model.IIPlus)]
    public void ReadMouseReportsPositionAndButton(Apple2Model model)
    {
        Apple2Machine machine = Machine(model, slot: 4);
        Apple2MouseCard mouse = machine.Bus.Mouse;
        Call(machine, MouseRom.INITMOUSE);
        mouse.Move(10, 10);
        mouse.X.Should().Be(0, "the mouse is off");

        ProcessorRegisters set = Call(machine, MouseRom.SETMOUSE, a: 1);
        set.Status.HasFlag(StatusRegister.Carry).Should().BeFalse();
        machine.Bus.Peek(0x07FC).Should().Be(1, "the mode hole");
        mouse.Move(300, 20);
        mouse.Button = true;

        ProcessorRegisters read = Call(machine, MouseRom.READMOUSE, y: 0x40);
        read.Y.Should().Be(0x40);
        read.Status.HasFlag(StatusRegister.Carry).Should().BeFalse();
        read.Status.HasFlag(StatusRegister.IRQBDisable).Should().BeFalse();
        Hole(machine, 0x0478, 4).Should().Be(300);
        Hole(machine, 0x04F8, 4).Should().Be(20);
        machine.Bus.Peek(0x077C).Should().Be(0xA0, "the button is down and the mouse moved");

        Call(machine, MouseRom.READMOUSE);
        machine.Bus.Peek(0x077C).Should().Be(0xC0, "the button was down at the last read too, and it has not moved");
    }

    /// <summary>
    ///  SETMOUSE refuses a mode above $0F with carry set.
    /// </summary>
    [TestMethod]
    public void SetMouseRejectsAnInvalidMode()
    {
        Apple2Machine machine = Machine(Apple2Model.IIe, slot: 4);
        Call(machine, MouseRom.SETMOUSE, a: 0x10).Status.HasFlag(StatusRegister.Carry).Should().BeTrue();
        machine.Bus.Mouse.Mode.Should().Be(0);
    }

    /// <summary>
    ///  CLAMPMOUSE takes each axis's bounds from slot 0's holes and holds the mouse within them; HOMEMOUSE goes to the
    ///  minimums, CLEARMOUSE to 0, 0 and POSMOUSE to the slot's holes.
    /// </summary>
    [TestMethod]
    public void ClampsAndPositions()
    {
        Apple2Machine machine = Machine(Apple2Model.IIeEnhanced, slot: 2);
        Apple2MouseCard mouse = machine.Bus.Mouse;
        Call(machine, MouseRom.SETMOUSE, a: 1);
        mouse.Move(500, 500);

        SetHole(machine, 0x0478, 0, 20);
        SetHole(machine, 0x04F8, 0, 279);
        Call(machine, MouseRom.CLAMPMOUSE, a: 0);
        SetHole(machine, 0x0478, 0, 10);
        SetHole(machine, 0x04F8, 0, 191);
        Call(machine, MouseRom.CLAMPMOUSE, a: 1);
        (mouse.X, mouse.Y).Should().Be((279, 191));

        mouse.Move(-1000, -1000);
        (mouse.X, mouse.Y).Should().Be((20, 10));
        mouse.Move(5, 5);
        Call(machine, MouseRom.HOMEMOUSE);
        (mouse.X, mouse.Y).Should().Be((20, 10));

        Call(machine, MouseRom.CLEARMOUSE);
        (mouse.X, mouse.Y).Should().Be((0, 0));
        Hole(machine, 0x0478, 2).Should().Be(0);

        SetHole(machine, 0x0478, 2, 123);
        SetHole(machine, 0x04F8, 2, 45);
        Call(machine, MouseRom.POSMOUSE);
        (mouse.X, mouse.Y).Should().Be((123, 45));
    }

    /// <summary>
    ///  With the VBL interrupt on, the card interrupts as vertical blanking starts; SERVEMOUSE claims it with carry
    ///  clear and sets bit 3 in the status hole, and once served, carry set says the next one is not the mouse's.
    /// </summary>
    [TestMethod]
    public void InterruptsAtVerticalBlank()
    {
        Apple2Machine machine = Machine(Apple2Model.IIe, slot: 4);
        Apple2MouseCard mouse = machine.Bus.Mouse;
        Call(machine, MouseRom.SETMOUSE, a: 0x09);
        mouse.InterruptRequested.Should().BeFalse();
        for (int i = 0; i < 65 * 262 && !mouse.InterruptRequested; i++) { machine.Bus.Tick(); }
        mouse.InterruptRequested.Should().BeTrue();
        machine.Bus.Scanline.Should().Be(192);

        Call(machine, MouseRom.SERVEMOUSE).Status.HasFlag(StatusRegister.Carry).Should().BeFalse();
        (machine.Bus.Peek(0x077C) & 0x0E).Should().Be(0x08);
        mouse.InterruptRequested.Should().BeFalse();
        Call(machine, MouseRom.SERVEMOUSE).Status.HasFlag(StatusRegister.Carry).Should().BeTrue();
    }

    /// <summary>
    ///  Movement and button interrupts come at vertical blanking only when the mouse moved or its button changed.
    /// </summary>
    [TestMethod]
    public void MovementAndButtonInterrupts()
    {
        Apple2Machine machine = Machine(Apple2Model.IIe, slot: 4);
        Apple2MouseCard mouse = machine.Bus.Mouse;
        Call(machine, MouseRom.SETMOUSE, a: 0x07);
        Frame(machine);
        mouse.InterruptRequested.Should().BeFalse("nothing happened");

        mouse.Move(1, 0);
        mouse.InterruptRequested.Should().BeFalse("the card waits for vertical blanking");
        Frame(machine);
        mouse.InterruptRequested.Should().BeTrue();
        Call(machine, MouseRom.SERVEMOUSE);
        (machine.Bus.Peek(0x077C) & 0x0E).Should().Be(0x02);

        mouse.Button = true;
        Frame(machine);
        Call(machine, MouseRom.SERVEMOUSE).Status.HasFlag(StatusRegister.Carry).Should().BeFalse();
        (machine.Bus.Peek(0x077C) & 0x0E).Should().Be(0x04);
    }

    /// <summary>
    ///  The interrupt reaches the processor, which takes the IRQ vector.
    /// </summary>
    [TestMethod]
    public void InterruptReachesTheProcessor()
    {
        Apple2Machine machine = Machine(Apple2Model.IIe, slot: 4);
        Call(machine, MouseRom.SETMOUSE, a: 0x09);

        // A loop at $3000 with interrupts enabled, and an IRQ vector of $FA40 in the test's ROM.
        machine.Bus.SetRam(auxiliary: false, 0x3000, 0x4C);
        machine.Bus.SetRam(auxiliary: false, 0x3001, 0x00);
        machine.Bus.SetRam(auxiliary: false, 0x3002, 0x30);
        machine.Processor.Registers = machine.Processor.Registers with
        {
            ProgramCounter = 0x3000, Status = StatusRegister.Unused
        };

        bool interrupted = false;
        for (int i = 0; i < 20_000 && !interrupted; i++)
        {
            machine.StepInstruction();
            interrupted = machine.Processor.Registers.ProgramCounter == 0xFA40;
        }

        interrupted.Should().BeTrue();
    }

    /// <summary>
    ///  IN#n then INPUT: the first call through $Cn00 moves the input hook to $Cn05, and the card writes the line
    ///  "X,Y,B" into the input buffer and returns a return with X = its length, as Apple's card does, so GETLN echoes
    ///  nothing. B is 4 for a button up both now and at the last read, 2 for one pressed since, negative with a key.
    /// </summary>
    [TestMethod]
    public void BasicInputWritesTheLine()
    {
        Apple2Machine machine = Machine(Apple2Model.IIe, slot: 4);
        Apple2MouseCard mouse = machine.Bus.Mouse;
        machine.Bus.SetRam(auxiliary: false, 0x36, 0xF0);
        machine.Bus.SetRam(auxiliary: false, 0x37, 0xFD);
        machine.Bus.SetRam(auxiliary: false, 0x38, 0x00);
        machine.Bus.SetRam(auxiliary: false, 0x39, 0xC4);
        Call(machine, MouseRom.SETMOUSE, a: 1);
        mouse.Move(12, 345);

        ProcessorRegisters registers = Call(machine, 0xC400, a: 0xA0, x: 0x05, y: 0x22);
        machine.Bus.Peek(0x38).Should().Be(0x05, "the input hook now goes straight to $Cn05");
        (registers.Accumulator, registers.X, registers.Y).Should().Be(((byte)0x8D, (byte)0x11, (byte)0x22));
        InputLine(machine).Should().Be("+00012,+00345,+04\r");
        machine.Bus.Peek(0x07F8).Should().Be(0xC4, "BASIC's calls leave MSLOT naming the card");
        machine.Bus.Peek(0x07FC).Should().Be(0x81, "BASIC mode");

        mouse.Button = true;
        SetHole(machine, 0x0478, 4, -8);
        Call(machine, MouseRom.POSMOUSE);
        machine.Bus.QueueKey((byte)'A');
        Call(machine, 0xC405, a: 0xA0);
        InputLine(machine).Should().Be("-00008,+00345,-02\r", "the button went down, and a key is waiting");
        Call(machine, 0xC405, a: 0xA0);
        InputLine(machine).Should().Be("-00008,+00345,-01\r", "the button stayed down");
    }

    /// <summary>
    ///  With the mouse off, BASIC's line is 0, 0 and B 1, and the position holes are cleared, as on Apple's card.
    /// </summary>
    [TestMethod]
    public void BasicInputWithTheMouseOff()
    {
        Apple2Machine machine = Machine(Apple2Model.IIe, slot: 4);
        machine.Bus.SetRam(auxiliary: false, 0x0478 + 4, 99);
        Call(machine, 0xC405, a: 0xA0);
        InputLine(machine).Should().Be("+00000,+00000,+01\r");
        machine.Bus.Peek(0x0478 + 4).Should().Be(0);
    }

    /// <summary>
    ///  PR#n then PRINT CHR$(1): the first call through $Cn00 moves the output hook to $Cn07, and the character turns
    ///  the mouse on. Any character's low bit turns it on or off, as on Apple's card, but a return changes nothing; A,
    ///  X and Y come back as they went in.
    /// </summary>
    [TestMethod]
    public void BasicOutputSetsTheMode()
    {
        Apple2Machine machine = Machine(Apple2Model.IIe, slot: 4);
        machine.Bus.SetRam(auxiliary: false, 0x36, 0x00);
        machine.Bus.SetRam(auxiliary: false, 0x37, 0xC4);
        machine.Bus.SetRam(auxiliary: false, 0x38, 0x1B);
        machine.Bus.SetRam(auxiliary: false, 0x39, 0xFD);

        ProcessorRegisters registers = Call(machine, 0xC400, a: 0x81, x: 0x33, y: 0x44);
        (registers.Accumulator, registers.X, registers.Y).Should().Be(((byte)0x81, (byte)0x33, (byte)0x44));
        machine.Bus.Peek(0x36).Should().Be(0x07);
        machine.Bus.Mouse.Mode.Should().Be(0x81);

        Call(machine, 0xC407, a: 0x8D);
        machine.Bus.Mouse.IsOn.Should().BeTrue("a return changes nothing");
        Call(machine, 0xC407, a: 0xC2).Accumulator.Should().Be(0xC2);
        machine.Bus.Mouse.IsOn.Should().BeFalse("B's low bit is 0");
        Call(machine, 0xC407, a: 0xC1);
        machine.Bus.Mouse.IsOn.Should().BeTrue("A's is 1");
    }

    /// <summary>
    ///  The mouse routines work with the language card's RAM over the Monitor, where $FF58 is not an RTS, as Apple's
    ///  do: SERVEMOUSE finds the slot through an RTS it puts at $06 and then restores, and the others take X = $Cn.
    /// </summary>
    [TestMethod]
    public void RoutinesNeedNotTheMonitor()
    {
        Apple2Machine machine = Machine(Apple2Model.IIe, slot: 4);
        machine.Bus.SetRam(auxiliary: false, 0x06, 0x5A);
        Call(machine, MouseRom.SETMOUSE, a: 0x09);
        Frame(machine);

        // Reading $C080 twice reads language-card RAM, all zeros, at $D000-$FFFF.
        machine.Bus.Read(0xC080);
        machine.Bus.Peek(0xFF58).Should().Be(0);
        machine.Bus.Mouse.Move(0, 0);
        Call(machine, MouseRom.SERVEMOUSE).Status.HasFlag(StatusRegister.Carry).Should().BeFalse();
        machine.Bus.Peek(0x06).Should().Be(0x5A, "SERVEMOUSE puts $06 back");
        Call(machine, MouseRom.READMOUSE).Status.HasFlag(StatusRegister.Carry).Should().BeFalse();
    }

    /// <summary>
    ///  READMOUSE leaves the holes alone while the mouse is off, as Apple's firmware does.
    /// </summary>
    [TestMethod]
    public void ReadMouseWhileOffChangesNothing()
    {
        Apple2Machine machine = Machine(Apple2Model.IIe, slot: 4);
        machine.Bus.SetRam(auxiliary: false, 0x0478 + 4, 77);
        Call(machine, MouseRom.READMOUSE);
        machine.Bus.Peek(0x0478 + 4).Should().Be(77);
    }

    /// <summary>
    ///  The Pascal entries answer error 3 with carry set, and the factory's entries at $Cn1A-$Cn1F do nothing, as on
    ///  Apple's card.
    /// </summary>
    [TestMethod]
    public void PascalAndFactoryEntries()
    {
        Apple2Machine machine = Machine(Apple2Model.IIe, slot: 4);
        for (int entry = 0x0D; entry <= 0x10; entry++)
        {
            ProcessorRegisters registers = Call(machine, (ushort)(0xC400 | machine.Bus.Peek((ushort)(0xC400 + entry))));
            registers.X.Should().Be(3);
            registers.Status.HasFlag(StatusRegister.Carry).Should().BeTrue();
        }

        for (int entry = 0x1A; entry <= 0x1F; entry++)
        {
            Call(machine, (ushort)(0xC400 | machine.Bus.Peek((ushort)(0xC400 + entry)))).Status.HasFlag(StatusRegister.Carry)
                .Should().BeTrue();
        }
    }

    /// <summary>
    ///  The card takes its slot from the others, and comes out again.
    /// </summary>
    [TestMethod]
    public void InstallsAndRemoves()
    {
        Apple2Machine machine = Machine(Apple2Model.IIe, slot: 4);
        machine.Bus.IsSlotFree(4).Should().BeFalse();
        Action mockingboard = machine.Bus.InstallMockingboard;
        mockingboard.Should().Throw<InvalidOperationException>();
        Action second = () => machine.Bus.InstallMouse(2);
        second.Should().Throw<InvalidOperationException>();

        Call(machine, MouseRom.SETMOUSE, a: 0x09);
        Frame(machine);
        machine.Bus.Mouse.InterruptRequested.Should().BeTrue();
        machine.Bus.RemoveMouse();
        machine.Bus.Mouse.InterruptRequested.Should().BeFalse();
        machine.Bus.MouseSlot.Should().Be(0);
        machine.Bus.IsSlotFree(4).Should().BeTrue();
        machine.Bus.Peek(0xC405).Should().Be(0xFF, "the slot is empty");
    }

    private static Apple2Machine Machine(Apple2Model model, int slot)
    {
        byte[] system = new byte[16384];
        system[0xFF58 - 0xC000] = 0x60;    // IORTS, an RTS
        system[0xFFFE - 0xC000] = 0x40;    // the IRQ vector: $FA40
        system[0xFFFF - 0xC000] = 0xFA;
        Apple2Machine machine = new(model, new Apple2Roms(system, new byte[4096]));
        machine.Run(cycles: 7);
        machine.Bus.InstallMouse(slot);
        return machine;
    }

    // Calls a routine as its documentation asks, with X = $Cn and Y = $n0 unless a test gives others, and returns the
    // registers it comes back with.
    private static ProcessorRegisters Call(Apple2Machine machine, ushort routine, byte a = 0, byte? x = null, byte? y = null)
    {
        int slot = machine.Bus.MouseSlot;
        if (routine >> 8 == 0xC4) { routine = (ushort)((routine & 0xFF) | ((0xC0 | slot) << 8)); }
        machine.Bus.SetRam(auxiliary: false, Caller, 0x20);
        machine.Bus.SetRam(auxiliary: false, Caller + 1, (byte)routine);
        machine.Bus.SetRam(auxiliary: false, Caller + 2, (byte)(routine >> 8));
        machine.Processor.Registers = new()
        {
            ProgramCounter = Caller,
            StackPointer = 0xF0,
            Accumulator = a,
            X = x ?? (byte)(0xC0 | slot),
            Y = y ?? (byte)(slot << 4),
            // SERVEMOUSE is called from the interrupt handler, with interrupts off.
            Status = StatusRegister.Unused | (routine == MouseServe(slot) ? StatusRegister.IRQBDisable : 0)
        };

        for (int i = 0; i < 200; i++)
        {
            machine.StepInstruction().Status.Should().Be(ProcessorExecutionStatus.InstructionComplete);
            if (machine.Processor.Registers.ProgramCounter == Caller + 3)
            {
                machine.Processor.Registers.StackPointer.Should().Be(0xF0);
                return machine.Processor.Registers;
            }
        }

        throw new InvalidOperationException($"${routine:X4} did not return.");
    }

    private static ushort MouseServe(int slot) => (ushort)((MouseRom.SERVEMOUSE & 0xFF) | ((0xC0 | slot) << 8));

    private static string InputLine(Apple2Machine machine)
    {
        Span<char> line = stackalloc char[0x12];
        for (int i = 0; i < line.Length; i++)
        {
            line[i] = (char)(machine.Bus.Peek((ushort)(0x0200 + i)) & 127);
        }

        return new string(line);
    }

    private static void Frame(Apple2Machine machine)
    {
        for (int i = 0; i < 65 * 262; i++) { machine.Bus.Tick(); }
    }

    private static int Hole(Apple2Machine machine, ushort low, int slot) =>
        (short)(machine.Bus.Peek((ushort)(low + slot)) | (machine.Bus.Peek((ushort)(low + slot + 0x100)) << 8));

    private static void SetHole(Apple2Machine machine, ushort low, int slot, int value)
    {
        machine.Bus.SetRam(auxiliary: false, (ushort)(low + slot), (byte)value);
        machine.Bus.SetRam(auxiliary: false, (ushort)(low + slot + 0x100), (byte)(value >> 8));
    }
}
