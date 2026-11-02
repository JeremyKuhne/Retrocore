// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Media;

/// <summary>
///  Standard reflected CRC-32 used by the WOZ specification.
/// </summary>
internal static class WozCrc
{
    /// <summary>
    ///  Computes a WOZ checksum over all bytes following its twelve-byte header.
    /// </summary>
    /// <param name="data">The bytes to checksum.</param>
    /// <returns>The CRC-32 value.</returns>
    internal static uint Compute(ReadOnlySpan<byte> data)
    {
        uint value = uint.MaxValue;
        foreach (byte next in data)
        {
            value ^= next;
            for (int bit = 0; bit < 8; bit++) { value = (value >> 1) ^ ((value & 1) != 0 ? 0xEDB88320u : 0); }
        }

        return ~value;
    }
}
