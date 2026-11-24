// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using Retrocore.Assembler;
using Retrocore.Debug;
using Retrocore.Machines.Commodore;

namespace Retrocore.Tests;

/// <summary>
///  A PET BASIC build's image in flat memory, with the character reader in page zero and a caller in page 3, for
///  running one of its routines.
/// </summary>
internal sealed class PetRoutineMachine
{
    // A JSR to the routine, then a loop the routine returns to.
    private const ushort Caller = 0x0300;

    /// <summary>
    ///  The address a called routine returns to.
    /// </summary>
    public const ushort Returned = Caller + 3;

    private readonly AssemblyResult _build;
    private readonly RecordingBus _bus = new();

    /// <summary>
    ///  Loads a PET build from the inputs <see cref="BasicNames"/> gives.
    /// </summary>
    /// <param name="model">The PET model.</param>
    /// <param name="original">Whether BASIC 1 or 4 uses its original chip.</param>
    public PetRoutineMachine(PetModel model, bool original)
    {
        _build = PetSdkModules.AssembleBasic(Path.Join(BasicNames.Inputs, "Pet"), model, original);
        _build.Success.Should().BeTrue();
        _build.Sections[0].Bytes.Span.CopyTo(_bus.Memory);

        // The character reader runs from page zero, where the cold start copies it.
        int reader = Address("GetNextCharacter");
        int length = Address("RandomValue") - reader;
        Array.Copy(_bus.Memory, Address("CharacterReaderTemplate"), _bus.Memory, reader, length);
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
    ///  Gets whether carry is set.
    /// </summary>
    public bool Carry => Cpu.Registers.Status.HasFlag(StatusRegister.Carry);

    /// <summary>
    ///  Gets a definition's address, by its current or old name.
    /// </summary>
    /// <param name="name">The name.</param>
    /// <returns>The address.</returns>
    public int Address(string name) => checked((int)_build.Symbol(name));

    /// <summary>
    ///  Gets the two bytes at a definition, low byte first.
    /// </summary>
    /// <param name="name">The definition's name.</param>
    /// <returns>The word.</returns>
    public int Word(string name) => Memory[Address(name)] | (Memory[Address(name) + 1] << 8);

    /// <summary>
    ///  Calls a routine from page 3 and runs until it returns.
    /// </summary>
    /// <param name="routine">The routine's name.</param>
    /// <param name="a">The value in A.</param>
    /// <param name="x">The value in X.</param>
    /// <param name="y">The value in Y.</param>
    /// <param name="negative">Whether negative is set.</param>
    /// <param name="zero">Whether zero is set.</param>
    public void Call(string routine, int a = 0, int x = 0, int y = 0, bool negative = false, bool zero = false) =>
        CallUntil(routine, [], a, x, y, negative, zero);

    /// <summary>
    ///  Calls a routine from page 3 and runs until it returns or reaches one of the given addresses.
    /// </summary>
    /// <param name="routine">The routine's name.</param>
    /// <param name="stops">The addresses to stop at.</param>
    /// <param name="a">The value in A.</param>
    /// <param name="x">The value in X.</param>
    /// <param name="y">The value in Y.</param>
    /// <param name="negative">Whether negative is set.</param>
    /// <param name="zero">Whether zero is set.</param>
    /// <returns>The address reached: a stop, or <see cref="Returned"/>.</returns>
    public int CallUntil(
        string routine, int[] stops, int a = 0, int x = 0, int y = 0, bool negative = false, bool zero = false)
    {
        ushort target = checked((ushort)_build.Symbol(routine));
        Memory[Caller] = 0x20;
        Memory[Caller + 1] = (byte)target;
        Memory[Caller + 2] = (byte)(target >> 8);
        Memory[Returned] = 0x4C;
        Memory[Returned + 1] = Returned & 0xFF;
        Memory[Returned + 2] = Returned >> 8;
        StatusRegister status = StatusRegister.Unused;
        if (negative) { status |= StatusRegister.Negative; }
        if (zero) { status |= StatusRegister.Zero; }
        Cpu.Registers = new()
        {
            ProgramCounter = Caller,
            Accumulator = (byte)a,
            X = (byte)x,
            Y = (byte)y,
            StackPointer = 0xF0,
            Status = status
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
