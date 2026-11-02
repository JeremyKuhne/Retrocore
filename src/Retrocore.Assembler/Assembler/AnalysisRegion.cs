// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Assembler;

/// <summary>
///  An immutable, non-wrapping address range used for classifications and caller overrides.
/// </summary>
public sealed class AnalysisRegion
{
    /// <summary>
    ///  Creates a region in the 16-bit address space.
    /// </summary>
    /// <param name="address">The first address.</param>
    /// <param name="length">The number of bytes.</param>
    /// <param name="kind">The classification.</param>
    public AnalysisRegion(int address, int length, AnalysisRegionKind kind)
    {
        ArgumentOutOfRangeException.ThrowIfNegative(address);
        ArgumentOutOfRangeException.ThrowIfGreaterThan(address, ushort.MaxValue);
        ArgumentOutOfRangeException.ThrowIfNegativeOrZero(length);
        ArgumentOutOfRangeException.ThrowIfGreaterThan(length, InstructionEncoding.AddressSpaceSize - address);
        if (!Enum.IsDefined(kind)) { throw new ArgumentOutOfRangeException(nameof(kind)); }
        Address = (ushort)address;
        Length = length;
        Kind = kind;
    }

    /// <summary>
    ///  Gets the first address.
    /// </summary>
    public ushort Address { get; }

    /// <summary>
    ///  Gets the byte count.
    /// </summary>
    public int Length { get; }

    /// <summary>
    ///  Gets the classification.
    /// </summary>
    public AnalysisRegionKind Kind { get; }
}
