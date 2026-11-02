// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Cpu.Z80;

/// <summary>
///  The Z80's registers and the internal state that later instructions see, such as MEMPTR and Q.
/// </summary>
public struct Z80Registers
{
    /// <summary>
    ///  Gets or sets the accumulator.
    /// </summary>
    public byte A { get; set; }

    /// <summary>
    ///  Gets or sets the flags.
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
    ///  Gets or sets the alternate AF'.
    /// </summary>
    public ushort AlternateAF { get; set; }

    /// <summary>
    ///  Gets or sets the alternate BC'.
    /// </summary>
    public ushort AlternateBC { get; set; }

    /// <summary>
    ///  Gets or sets the alternate DE'.
    /// </summary>
    public ushort AlternateDE { get; set; }

    /// <summary>
    ///  Gets or sets the alternate HL'.
    /// </summary>
    public ushort AlternateHL { get; set; }

    /// <summary>
    ///  Gets or sets IX.
    /// </summary>
    public ushort IX { get; set; }

    /// <summary>
    ///  Gets or sets IY.
    /// </summary>
    public ushort IY { get; set; }

    /// <summary>
    ///  Gets or sets the stack pointer.
    /// </summary>
    public ushort SP { get; set; }

    /// <summary>
    ///  Gets or sets the program counter.
    /// </summary>
    public ushort PC { get; set; }

    /// <summary>
    ///  Gets or sets the interrupt vector base.
    /// </summary>
    public byte I { get; set; }

    /// <summary>
    ///  Gets or sets the memory refresh counter; each opcode fetch increments its low seven bits.
    /// </summary>
    public byte R { get; set; }

    /// <summary>
    ///  Gets or sets MEMPTR (WZ), the internal address register whose high byte shows in some undocumented flags.
    /// </summary>
    public ushort WZ { get; set; }

    /// <summary>
    ///  Gets or sets Q: the flags the last instruction wrote, or zero when it wrote none. <c>SCF</c> and
    ///  <c>CCF</c> take their undocumented flags from it.
    /// </summary>
    public byte Q { get; set; }

    /// <summary>
    ///  Gets or sets the maskable interrupt enable flip-flop.
    /// </summary>
    public bool Iff1 { get; set; }

    /// <summary>
    ///  Gets or sets the flip-flop that keeps IFF1 during a non-maskable interrupt.
    /// </summary>
    public bool Iff2 { get; set; }

    /// <summary>
    ///  Gets or sets the interrupt mode, 0-2.
    /// </summary>
    public byte InterruptMode { get; set; }

    /// <summary>
    ///  Gets or sets whether the last instruction was <c>EI</c>, which holds off a maskable interrupt for one
    ///  more instruction.
    /// </summary>
    public bool AfterEnable { get; set; }

    /// <summary>
    ///  Gets or sets whether the last instruction was <c>LD A,I</c> or <c>LD A,R</c>; an interrupt accepted
    ///  right after it clears the parity flag those set from IFF2.
    /// </summary>
    public bool AfterLoadInterrupt { get; set; }

    /// <summary>
    ///  Gets or sets BC.
    /// </summary>
    public ushort BC
    {
        readonly get => (ushort)((B << 8) | C);
        set
        {
            B = (byte)(value >> 8);
            C = (byte)value;
        }
    }

    /// <summary>
    ///  Gets or sets DE.
    /// </summary>
    public ushort DE
    {
        readonly get => (ushort)((D << 8) | E);
        set
        {
            D = (byte)(value >> 8);
            E = (byte)value;
        }
    }

    /// <summary>
    ///  Gets or sets HL.
    /// </summary>
    public ushort HL
    {
        readonly get => (ushort)((H << 8) | L);
        set
        {
            H = (byte)(value >> 8);
            L = (byte)value;
        }
    }

    /// <summary>
    ///  Gets or sets AF.
    /// </summary>
    public ushort AF
    {
        readonly get => (ushort)((A << 8) | F);
        set
        {
            A = (byte)(value >> 8);
            F = (byte)value;
        }
    }
}
