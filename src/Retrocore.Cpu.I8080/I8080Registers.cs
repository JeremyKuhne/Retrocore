// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Cpu.I8080;

/// <summary>
///  The 8080's and 8085's registers, and the interrupt state instructions see.
/// </summary>
public struct I8080Registers
{
    /// <summary>
    ///  Gets or sets the accumulator.
    /// </summary>
    public byte A { get; set; }

    /// <summary>
    ///  Gets or sets the flags, the low byte of PSW.
    /// </summary>
    public byte F { get; set; }

    /// <summary>
    ///  Gets or sets B.
    /// </summary>
    public byte B { get; set; }

    /// <summary>
    ///  Gets or sets C.
    /// </summary>
    public byte C { get; set; }

    /// <summary>
    ///  Gets or sets D.
    /// </summary>
    public byte D { get; set; }

    /// <summary>
    ///  Gets or sets E.
    /// </summary>
    public byte E { get; set; }

    /// <summary>
    ///  Gets or sets H.
    /// </summary>
    public byte H { get; set; }

    /// <summary>
    ///  Gets or sets L.
    /// </summary>
    public byte L { get; set; }

    /// <summary>
    ///  Gets or sets the stack pointer.
    /// </summary>
    public ushort SP { get; set; }

    /// <summary>
    ///  Gets or sets the program counter.
    /// </summary>
    public ushort PC { get; set; }

    /// <summary>
    ///  Gets or sets INTE (the 8085's IE): whether maskable interrupts are taken.
    /// </summary>
    public bool InterruptEnable { get; set; }

    /// <summary>
    ///  Gets or sets whether the last instruction was <c>EI</c>, which holds off interrupts for one instruction.
    /// </summary>
    public bool AfterEnable { get; set; }

    /// <summary>
    ///  Gets or sets the 8085's interrupt masks, which <c>SIM</c> sets: bit 0 masks RST 5.5, bit 1 RST 6.5 and bit 2
    ///  RST 7.5. Reset sets all three.
    /// </summary>
    public byte InterruptMask { get; set; }

    /// <summary>
    ///  Gets or sets the 8085's SOD output, which <c>SIM</c> sets.
    /// </summary>
    public bool SerialOutput { get; set; }

    /// <summary>
    ///  Gets or sets the pair B and C.
    /// </summary>
    public ushort BC
    {
        readonly get => (ushort)((B << 8) | C);
        set => (B, C) = ((byte)(value >> 8), (byte)value);
    }

    /// <summary>
    ///  Gets or sets the pair D and E.
    /// </summary>
    public ushort DE
    {
        readonly get => (ushort)((D << 8) | E);
        set => (D, E) = ((byte)(value >> 8), (byte)value);
    }

    /// <summary>
    ///  Gets or sets the pair H and L.
    /// </summary>
    public ushort HL
    {
        readonly get => (ushort)((H << 8) | L);
        set => (H, L) = ((byte)(value >> 8), (byte)value);
    }

    /// <summary>
    ///  Gets or sets the program status word: A and the flags.
    /// </summary>
    public ushort PSW
    {
        readonly get => (ushort)((A << 8) | F);
        set => (A, F) = ((byte)(value >> 8), (byte)value);
    }
}
