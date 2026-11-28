// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Tests;

/// <summary>
///  A peer that sends one message and leaves its input pipe open.
/// </summary>
/// <param name="message">The framed message.</param>
/// <param name="readingPastMessage">Signaled if the reader waits for more input.</param>
/// <param name="close">Releases the read, as if the peer closed its pipe.</param>
internal sealed class DisconnectReadStream(byte[] message, ManualResetEventSlim readingPastMessage, ManualResetEventSlim close)
    : MemoryStream(message, 0, message.Length, writable: false, publiclyVisible: true)
{
    /// <inheritdoc/>
    public override int Read(byte[] buffer, int offset, int count) => Read(buffer.AsSpan(offset, count));

    /// <inheritdoc/>
    public override int Read(Span<byte> buffer) => Read(buffer, CancellationToken.None);

    /// <summary>
    ///  Reads from the open input until it supplies bytes, closes or is canceled.
    /// </summary>
    /// <param name="buffer">Where to put the received bytes.</param>
    /// <param name="cancellation">The token that interrupts the input wait.</param>
    /// <returns>The number of bytes read.</returns>
    internal int Read(Span<byte> buffer, CancellationToken cancellation)
    {
        if (Position < Length)
        {
            int count = Math.Min((int)(Length - Position), buffer.Length);
            GetBuffer().AsSpan((int)Position, count).CopyTo(buffer);
            Position += count;
            return count;
        }

        readingPastMessage.Set();
        close.Wait(cancellation);
        return 0;
    }
}
