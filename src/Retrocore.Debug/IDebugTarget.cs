// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using System.Text.Json.Nodes;
using Retrocore.Assembler;
using Retrocore.Basic;
using Retrocore.Isa;
using Retrocore.Machines.Devices;

namespace Retrocore.Debug;

/// <summary>
///  A launched machine as the debugger sees it: memory, the CPU, the calls in progress, and the machine's own
///  views and requests.
/// </summary>
/// <remarks>
///  <para>
///   The session holds everything that is the same on every machine, such as breakpoints, source stepping,
///   cycle counts and contracts; a target holds what depends on the CPU or the machine.
///  </para>
/// </remarks>
internal interface IDebugTarget : IDebugMemory
{
    /// <summary>
    ///  Gets the name of the debugger's one thread, such as "IIe CPU".
    /// </summary>
    string ThreadName { get; }

    /// <summary>
    ///  Gets the CPU's name as <c>.cpu</c> gives it, for assembling a launched source.
    /// </summary>
    string Cpu { get; }

    /// <summary>
    ///  Gets the CPU's instruction set, for the disassembly view.
    /// </summary>
    InstructionSet InstructionSet { get; }

    /// <summary>
    ///  Gets whether the CPU has a separate I/O space, so a data breakpoint can watch its ports.
    /// </summary>
    bool HasPorts => false;

    /// <summary>
    ///  Gets the CPU's registers and flags by name.
    /// </summary>
    DebugRegisters Registers { get; }

    /// <summary>
    ///  Gets the bus cycle the last <see cref="StepCycle"/> ran, for data breakpoints.
    /// </summary>
    ProcessorCycle LastCycle { get; }

    /// <summary>
    ///  Gets the CPU's registers now.
    /// </summary>
    DebugFrame Frame { get; }

    /// <summary>
    ///  Gets or sets the program counter.
    /// </summary>
    ushort ProgramCounter { get; set; }

    /// <summary>
    ///  Gets whether the CPU is between instructions.
    /// </summary>
    bool IsInstructionBoundary { get; }

    /// <summary>
    ///  Gets whether an instruction has started and not finished, as opposed to an interrupt's response.
    /// </summary>
    bool InInstruction { get; }

    /// <summary>
    ///  Gets whether the CPU idles between instructions for as long as something outside it decides, such as a 6809
    ///  held by HALT or waiting in <c>SYNC</c>; it is then not at an instruction boundary until it goes on.
    /// </summary>
    bool IsIdle => false;

    /// <summary>
    ///  Gets whether a device holds the CPU part way through an instruction, as a Z80's WAIT line does, for as long
    ///  as the device decides. The instruction finishes once the device lets go.
    /// </summary>
    bool IsHeld => false;

    /// <summary>
    ///  Gets the cycles run since power-up.
    /// </summary>
    ulong CycleCount { get; }

    /// <summary>
    ///  Gets the machine's clock: the cycles it runs each second at its real speed.
    /// </summary>
    int ClockHertz { get; }

    /// <summary>
    ///  Gets whether running may outpace the machine's clock now, such as while a tape loads.
    /// </summary>
    bool Accelerated { get; }

    /// <summary>
    ///  Gets the calls in progress.
    /// </summary>
    IDebugCallStack CallStack { get; }

    /// <summary>
    ///  Gets where a launched program loads when the launch gives no address.
    /// </summary>
    int DefaultLoadAddress { get; }

    /// <summary>
    ///  Gets the memory area a launched program and its source map live in.
    /// </summary>
    Enum ProgramArea { get; }

    /// <summary>
    ///  Gets the name a routine's documentation uses for this machine's model in conditional sections.
    /// </summary>
    string ContractModel { get; }

    /// <summary>
    ///  Gets the registers a routine's <c>Uses:</c> section accounts for.
    /// </summary>
    IReadOnlyList<string> UsedRegisters { get; }

    /// <summary>
    ///  Gets the block of memory the variables view lists beside the registers, such as the 6502's zero page.
    /// </summary>
    (string Name, ushort Start, int Length) MemoryScope { get; }

    /// <summary>
    ///  Gets the storage memory references can name directly, whatever the memory map, such as the IIe's
    ///  auxiliary RAM; none on a machine whose addresses each have one home.
    /// </summary>
    IReadOnlyList<DebugMemoryBank> Banks => [];

    /// <summary>
    ///  Gets the machine's BASIC, or null when it has none the debugger knows.
    /// </summary>
    BasicDialect? Basic => null;

    /// <summary>
    ///  Gets whether the debugger has the source of the BASIC this machine runs, or will load from its disk, which a
    ///  basic launch needs to find BASIC's prompt.
    /// </summary>
    bool HasBasicSource => BasicRom is not null;

    /// <summary>
    ///  Gets how long, in the machine's time, a basic launch waits for BASIC's prompt after power-on.
    /// </summary>
    double BasicBootSeconds => 10;

    /// <summary>
    ///  Gets whether a basic launch presses RETURN once a second on the way to BASIC's prompt, as the Model I's
    ///  MEMORY SIZE? needs.
    /// </summary>
    bool PressesReturnForPrompt => true;

    /// <summary>
    ///  Gets the BASIC ROM's statement dispatch and command loop, or null when the SDK's source of the running ROM
    ///  was not assembled.
    /// </summary>
    BasicRom? BasicRom => null;

    /// <summary>
    ///  Gets the number of the BASIC line running, or last run.
    /// </summary>
    int BasicCurrentLine => Basic is { } dialect
        ? Peek((ushort)dialect.Pointers.CurrentLine) | (Peek((ushort)(dialect.Pointers.CurrentLine + 1)) << 8)
        : 0;

    /// <summary>
    ///  Gets the statement that starts at an instruction: its line's number and the address of its first byte.
    /// </summary>
    /// <remarks>
    ///  <para>
    ///   The Microsoft BASICs start every statement at <see cref="Debug.BasicRom.Gone"/>. A BASIC that starts them in
    ///   more than one place, or only sometimes at one, says so here, as AppleSoft does under ProDOS's BASIC.SYSTEM,
    ///   which enters each statement past <c>GONE</c>.
    ///  </para>
    /// </remarks>
    /// <param name="pc">The instruction's address.</param>
    /// <returns>The statement, or null when none starts there.</returns>
    (int Line, int Address)? BasicStatementStart(ushort pc) =>
        BasicRom is { } rom && pc == rom.Gone ? (BasicCurrentLine, BasicTextPointer + 1) : null;

    /// <summary>
    ///  Gets the GOSUBs in progress, most recent first: the line each was in and the address before the place it
    ///  returns to; null when they are read from the CPU's stack by their tokens, as the Microsoft BASICs keep them.
    /// </summary>
    IReadOnlyList<(int Line, int TextPointer)>? BasicGosubs => null;

    /// <summary>
    ///  Gets the text pointer at the start of a statement, at <see cref="Debug.BasicRom.Gone"/>: the colon or line
    ///  start before the statement.
    /// </summary>
    int BasicTextPointer => 0;

    /// <summary>
    ///  Gets the address of BASIC's most recent stack entry, a FOR or GOSUB, as saved when the statement began.
    /// </summary>
    int BasicStack => 0;

    /// <summary>
    ///  Gets the address of BASIC's most recent stack entry from the stack pointer, which is right at
    ///  <see cref="Debug.BasicRom.Gone"/> even where the saved one is stale, as AppleSoft's is after a GOSUB.
    /// </summary>
    int BasicLiveStack => 0;

    /// <summary>
    ///  Gets the size of a FOR entry on BASIC's stack.
    /// </summary>
    int BasicForSize => 0;

    /// <summary>
    ///  Gets the size of a GOSUB entry on BASIC's stack, with anything left under it.
    /// </summary>
    int BasicGosubSize => 5;

    /// <summary>
    ///  Describes the error being reported, at <see cref="Debug.BasicRom.Error"/>.
    /// </summary>
    /// <returns>The error's code as BASIC gives it, its message, and whether an error handler will take it.</returns>
    (int Code, string Message, bool Handled) BasicError() => (0, "error", false);

    /// <summary>
    ///  Moves BASIC to another statement, at <see cref="Debug.BasicRom.Gone"/>: sets the current line and the text
    ///  pointer the statement fetch continues from. A statement start past <c>GONE</c> moves back to it.
    /// </summary>
    /// <param name="line">The line number.</param>
    /// <param name="textPointer">The address before the statement's first byte.</param>
    void SetBasicStatement(int line, int textPointer) => throw new NotSupportedException("This machine has no BASIC.");

    /// <summary>
    ///  Tests whether an address reads the machine's ROM now, rather than RAM.
    /// </summary>
    /// <param name="address">The address.</param>
    /// <returns>Whether it is ROM.</returns>
    bool InRom(ushort address) => false;

    /// <summary>
    ///  Puts BASIC at its prompt, as after an error or a typed line: resets its stack and flags, marks direct
    ///  mode, and continues at the command loop. The CPU must be between instructions.
    /// </summary>
    /// <param name="rom">The ROM's addresses.</param>
    void EnterBasicPrompt(BasicRom rom) => throw new NotSupportedException("This machine has no BASIC.");

    /// <summary>
    ///  Gets the address a register's value points at, for the memory view the Variables view opens from it.
    /// </summary>
    /// <param name="register">The register.</param>
    /// <param name="value">Its value.</param>
    /// <returns>The address, or null when the register does not hold one.</returns>
    int? PointsTo(IsaRegister register, long value) => register.Bits >= 16 ? (int)(value & 0xFFFF) : null;

    /// <summary>
    ///  Runs one cycle and tracks the calls it makes and returns from.
    /// </summary>
    /// <returns>Whether the cycle fetched an opcode, which starts an instruction.</returns>
    /// <exception cref="InvalidOperationException">The CPU stopped.</exception>
    bool StepCycle();

    /// <summary>
    ///  Gets the call an instruction makes, for call cycle counts and contract checks.
    /// </summary>
    /// <param name="address">The instruction's address.</param>
    /// <returns>The routine it calls and the instruction's length, or null when it is not a call.</returns>
    (ushort Target, int Length)? CallAt(ushort address);

    /// <summary>
    ///  Describes the trap an instruction would take, such as the 6502's BRK, for the BRK filter to stop at.
    /// </summary>
    /// <param name="address">The instruction's address.</param>
    /// <returns>The stop's description, or null when it does not trap.</returns>
    string? Trap(ushort address);

    /// <summary>
    ///  Names the operating system call an instruction makes, such as an Apple III program's BRK into SOS.
    /// </summary>
    /// <param name="address">The instruction's address.</param>
    /// <returns>The call's name and number, or null when it makes none.</returns>
    (string Name, byte Number)? SystemCall(ushort address) => null;

    /// <summary>
    ///  Describes the operating system call an instruction makes with its main parameters, for a log message's
    ///  <c>{sos}</c>.
    /// </summary>
    /// <param name="address">The instruction's address.</param>
    /// <returns>The description, or null when it makes none.</returns>
    string? DescribeSystemCall(ushort address) => null;

    /// <summary>
    ///  Gets whether the machine has a video beam that scanline breakpoints can stop on.
    /// </summary>
    bool HasBeam => false;

    /// <summary>
    ///  Sets the beam positions scanline breakpoints stop at, replacing any before.
    /// </summary>
    /// <param name="positions">Each a cycle within the video frame: the scanline times 65, plus the column.</param>
    void SetBeamBreaks(IReadOnlyCollection<int> positions)
    {
    }

    /// <summary>
    ///  Gets the beam position a scanline breakpoint stops at before the next cycle.
    /// </summary>
    /// <returns>The position, as a cycle within the video frame, or null.</returns>
    int? CycleBreak() => null;

    /// <summary>
    ///  Writes memory for the debugger.
    /// </summary>
    /// <param name="address">The address.</param>
    /// <param name="value">The value.</param>
    void Poke(ushort address, byte value);

    /// <summary>
    ///  Reads memory through an Apple III extended address, as an indirect access through zero page with that X-byte
    ///  would; a machine without extended addressing reads the address as mapped now.
    /// </summary>
    /// <param name="xByte">The X-byte; without bit 7, the address as mapped now.</param>
    /// <param name="address">The address.</param>
    /// <returns>The value.</returns>
    byte PeekFar(byte xByte, ushort address) => Peek(address);

    /// <summary>
    ///  Writes memory through an Apple III extended address.
    /// </summary>
    /// <param name="xByte">The X-byte; without bit 7, the address as mapped now.</param>
    /// <param name="address">The address.</param>
    /// <param name="value">The value.</param>
    void PokeFar(byte xByte, ushort address, byte value) => Poke(address, value);

    /// <summary>
    ///  Copies a program into RAM.
    /// </summary>
    /// <param name="address">The load address.</param>
    /// <param name="bytes">The program.</param>
    /// <exception cref="ArgumentException">The program does not fit in RAM.</exception>
    void Load(int address, ReadOnlySpan<byte> bytes);

    /// <summary>
    ///  Adds the modules for the SDK's sources of the machine's ROMs.
    /// </summary>
    /// <param name="debug">The session's modules.</param>
    /// <param name="directory">The SDK ROM source directory, or null for the copy beside the debug host.</param>
    void AddSdkModules(DebugInfo debug, string? directory);

    /// <summary>
    ///  Adds modules for code the machine has loaded since the last call, such as the drivers an operating system
    ///  relocates as it boots. The session calls it while running and at each stop, so it must be cheap when
    ///  nothing has changed.
    /// </summary>
    /// <param name="debug">The session's modules.</param>
    /// <returns>Whether it added any, so that source breakpoints bind again.</returns>
    bool AddLoadedModules(DebugInfo debug) => false;

    /// <summary>
    ///  Gets Apple Pascal's p-machine on a machine that can run it, or null.
    /// </summary>
    PascalRuntime? Pascal => null;

    /// <summary>
    ///  Gets whether a launched source's single-statement macros debug as their call line.
    /// </summary>
    /// <param name="dialect">The source's dialect.</param>
    /// <returns>Whether to collapse them.</returns>
    bool CollapsesMacros(AssemblyDialect? dialect) => dialect == AssemblyDialect.Macro10;

    /// <summary>
    ///  Gets the machine's installed hardware, in the order the Retro Devices view lists it: built-in parts, then
    ///  each slot or option, empty ones included, with the devices on each.
    /// </summary>
    /// <returns>The rows.</returns>
    IReadOnlyList<HardwareRow> Hardware();

    /// <summary>
    ///  Gets the display frame the panel draws, without the video's pixels: text rows, the video's size and the
    ///  machine's status. Its <c>video</c> object takes the pixels from <see cref="RenderVideo"/>.
    /// </summary>
    /// <param name="running">Whether the machine is running.</param>
    /// <returns>The frame's state.</returns>
    JsonObject DisplayState(bool running);

    /// <summary>
    ///  Gets the monitors the video can be shown on, from <see cref="DebugScreens"/>, the default first.
    /// </summary>
    IReadOnlyList<string> Screens { get; }

    /// <summary>
    ///  Gets or sets the monitor the video is shown on, one of <see cref="Screens"/>.
    /// </summary>
    /// <exception cref="ArgumentException">The machine has no such monitor.</exception>
    string Screen { get; set; }

    /// <summary>
    ///  Renders the video as the beam drew it, into a buffer the target keeps.
    /// </summary>
    /// <returns>The RGBA pixels, valid until the next call.</returns>
    ReadOnlySpan<byte> RenderVideo();

    /// <summary>
    ///  Gets the whole display frame, its pixels included as base64, for a request.
    /// </summary>
    /// <param name="running">Whether the machine is running.</param>
    /// <returns>The frame.</returns>
    JsonObject DisplayFrame(bool running)
    {
        JsonObject frame = DisplayState(running);
        if (frame["video"] is JsonObject video) { video["pixels"] = Convert.ToBase64String(RenderVideo()); }
        return frame;
    }

    /// <summary>
    ///  Takes the audio the machine made since the last call, for the panel to play while running.
    /// </summary>
    /// <returns>
    ///  The <c>rate</c>, <c>channels</c> and base64 16-bit PCM <c>samples</c>, or null when sound is off or nothing
    ///  has collected.
    /// </returns>
    JsonObject? TakeAudio() => null;

    /// <summary>
    ///  Types a key.
    /// </summary>
    /// <param name="code">The ASCII code, 0-127.</param>
    /// <returns>Whether the keyboard has a key for it; a character it has none for is left out.</returns>
    bool Key(int code);

    /// <summary>
    ///  Gets how far apart pasted keys go, in the machine's cycles: between keys, and after a RETURN; null to queue
    ///  them all at once, as the machine's keyboard holds them until a program takes each.
    /// </summary>
    /// <remarks>
    ///  <para>
    ///   A program that keeps its own type-ahead, as Apple Pascal's Editor does, can lose keys that come faster than
    ///   it empties it, such as while it scrolls after a line.
    ///  </para>
    /// </remarks>
    (ulong Key, ulong Line)? TypingPace => null;

    /// <summary>
    ///  Presses the machine's reset: CONTROL-RESET on the IIe, the reset button on the Model I.
    /// </summary>
    void Reset();

    /// <summary>
    ///  Gets whether a reset pressed since has just reached its handler's first instruction, once: the IIe's reset
    ///  vector, or the Model I's non-maskable interrupt at <c>$0066</c>.
    /// </summary>
    /// <returns>True once, at that instruction.</returns>
    bool TakeResetStop() => false;

    /// <summary>
    ///  Gets the machine's own requests, by DAP command.
    /// </summary>
    IReadOnlyDictionary<string, Func<JsonObject, JsonObject>> Requests { get; }

    /// <summary>
    ///  Gets the machine's own events, sent on each stop and with each running frame.
    /// </summary>
    /// <returns>Each event's name and body.</returns>
    IEnumerable<(string Event, JsonObject Body)> StatusEvents();

    /// <summary>
    ///  Gets the machine's installed devices, such as its floppy and tape drives.
    /// </summary>
    IReadOnlyList<IDevice> Devices { get; }

    /// <summary>
    ///  Carries out a <c>retro/device</c> action on one of <see cref="Devices"/>.
    /// </summary>
    /// <param name="device">The device.</param>
    /// <param name="action"><c>insert</c>, <c>eject</c>, <c>record</c>, <c>writeProtect</c> or <c>save</c>.</param>
    /// <param name="args">
    ///  The request: <c>path</c> for insert and record, and for save when not the media's own image;
    ///  <c>writeProtected</c> for writeProtect.
    /// </param>
    /// <exception cref="ArgumentException">
    ///  The device does not support the action, or an argument is missing.
    /// </exception>
    void DeviceAction(IDevice device, string action, JsonObject args);

    /// <summary>
    ///  Changes a row of the installed hardware, such as putting a card in a free slot or taking one out.
    /// </summary>
    /// <param name="id">The row, such as <c>slot5</c>.</param>
    /// <param name="action">What to do: an action the row lists.</param>
    /// <param name="args">The request's arguments, such as the card to add.</param>
    /// <exception cref="ArgumentException">The row does not take the action, or an argument is wrong.</exception>
    void HardwareAction(string id, string action, JsonObject args) =>
        throw new ArgumentException($"The {id} hardware cannot be changed while the machine runs.");

    /// <summary>
    ///  Gets the cards in the machine's slots, for a later launch to restore, such as <c>{ "4": "mockingboard" }</c>.
    /// </summary>
    /// <returns>Each slot's card, <c>empty</c> for none, or null for a machine without slots.</returns>
    JsonObject? Cards() => null;

    /// <summary>
    ///  Puts the cards a saved <see cref="Cards"/> lists into their slots, replacing what the launch put there.
    /// </summary>
    /// <param name="cards">The saved cards.</param>
    /// <returns>What could not be restored, one message each.</returns>
    IEnumerable<string> RestoreCards(JsonObject cards) => [];
}
