// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Tests;

/// <summary>
///  A stream that gives up its bytes three at a time, as a pipe may.
/// </summary>
/// <param name="bytes">The bytes.</param>
internal sealed class TrickleStream(byte[] bytes) : MemoryStream(bytes)
{
    /// <inheritdoc/>
    public override int Read(byte[] buffer, int offset, int count) => base.Read(buffer, offset, Math.Min(count, 3));

    /// <inheritdoc/>
    public override int Read(Span<byte> buffer) => base.Read(buffer[..Math.Min(buffer.Length, 3)]);
}
