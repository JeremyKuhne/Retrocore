// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using Retrocore.Media;

namespace Retrocore.Tests;

public sealed partial class DebugModuleTests
{
    /// <summary>
    ///  An empty block device, so the bus maps the slot-seven firmware.
    /// </summary>
    private sealed class BlockDevice : IBlockDevice
    {
        /// <inheritdoc/>
        public uint BlockCount => 280;

        /// <inheritdoc/>
        public bool IsReadOnly => true;

        /// <inheritdoc/>
        public void ReadBlock(uint block, Span<byte> destination) => destination.Clear();

        /// <inheritdoc/>
        public void WriteBlock(uint block, ReadOnlySpan<byte> source) => throw new NotSupportedException();
    }
}
