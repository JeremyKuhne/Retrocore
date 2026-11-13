// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Cpu.M6809;

/// <summary>
///  The MC6809 programmer-visible registers.
/// </summary>
public struct M6809Registers
{
    /// <summary>
    ///  Gets or sets accumulator A.
    /// </summary>
    public byte A { readonly get; set; }

    /// <summary>
    ///  Gets or sets accumulator B.
    /// </summary>
    public byte B { readonly get; set; }

    /// <summary>
    ///  Gets or sets index register X.
    /// </summary>
    public ushort X { readonly get; set; }

    /// <summary>
    ///  Gets or sets index register Y.
    /// </summary>
    public ushort Y { readonly get; set; }

    /// <summary>
    ///  Gets or sets user stack pointer U.
    /// </summary>
    public ushort U { readonly get; set; }

    /// <summary>
    ///  Gets or sets system stack pointer S.
    /// </summary>
    public ushort S { readonly get; set; }

    /// <summary>
    ///  Gets or sets program counter PC.
    /// </summary>
    public ushort PC { readonly get; set; }

    /// <summary>
    ///  Gets or sets direct-page register DP.
    /// </summary>
    public byte DP { readonly get; set; }

    /// <summary>
    ///  Gets or sets condition-code register CC.
    /// </summary>
    public byte CC { readonly get; set; }

    /// <summary>
    ///  Gets or sets condition-code register CC as typed flags.
    /// </summary>
    public M6809ConditionCode Flags
    {
        readonly get => (M6809ConditionCode)CC;
        set => CC = (byte)value;
    }

    /// <summary>
    ///  Gets or sets whether the system stack pointer S has been loaded since reset, arming NMI edge detection.
    /// </summary>
    public bool NmiArmed { readonly get; set; }

    /// <summary>
    ///  Gets or sets the combined D accumulator (A is high, B is low).
    /// </summary>
    public ushort D
    {
        readonly get => (ushort)((A << 8) | B);
        set
        {
            A = (byte)(value >> 8);
            B = (byte)value;
        }
    }
}
