// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Tests;

/// <summary>
///  Blocks the first wire write until the test releases it.
/// </summary>
/// <param name="writing">Signals that the writer reached the stream.</param>
/// <param name="release">Allows the write to finish.</param>
internal sealed class GatedWriteStream(ManualResetEventSlim writing, ManualResetEventSlim release) : MemoryStream
{
    /// <inheritdoc/>
    public override void Write(ReadOnlySpan<byte> buffer)
    {
        if (!writing.IsSet)
        {
            writing.Set();
            release.Wait();
        }

        base.Write(buffer);
    }
}
