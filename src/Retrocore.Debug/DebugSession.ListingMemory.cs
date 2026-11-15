// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Debug;

internal sealed partial class DebugSession
{
    /// <summary>
    ///  Memory for one listing: each byte read once, and whether it can be read at all, as Retrocore Memory's grid
    ///  shows, so a long data statement checked at each of its bytes reads memory only once.
    /// </summary>
    /// <param name="memory">The memory debug modules read, for its areas.</param>
    /// <param name="read">Reads a byte of the listing's space, or null where it cannot be read.</param>
    private sealed class ListingMemory(IDebugMemory memory, Func<long, byte?> read) : IDebugMemory
    {
        // Each address's byte plus one, -1 where it cannot be read, or 0 where it is not read yet.
        private readonly short[] _bytes = new short[0x10000];

        /// <inheritdoc/>
        public byte Peek(ushort address) => (byte)Math.Max(0, Read(address));

        /// <summary>
        ///  Gets whether a byte can be read.
        /// </summary>
        /// <param name="address">The address, which may be outside the 64K.</param>
        /// <returns>Whether the byte is in the space and can be read.</returns>
        public bool Readable(int address) => address is >= 0 and <= 0xFFFF && Read((ushort)address) >= 0;

        /// <inheritdoc/>
        public Enum ReadArea(ushort address) => memory.ReadArea(address);

        /// <inheritdoc/>
        public Enum WriteArea(ushort address) => memory.WriteArea(address);

        // The byte at an address, or -1 where it cannot be read.
        private int Read(ushort address)
        {
            if (_bytes[address] == 0) { _bytes[address] = read(address) is { } value ? (short)(value + 1) : (short)-1; }
            return _bytes[address] < 0 ? -1 : _bytes[address] - 1;
        }
    }
}
