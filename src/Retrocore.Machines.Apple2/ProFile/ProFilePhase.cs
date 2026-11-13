// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Machines.Apple2;

/// <summary>
///  Where a <see cref="ProFileDrive"/> is in an exchange with its host.
/// </summary>
internal enum ProFilePhase : byte
{
    /// <summary>
    ///  Waiting for CMD, with BSY low.
    /// </summary>
    Idle,

    /// <summary>
    ///  CMD is up and BSY with it: the response is on the port, waiting for the host's answer and CMD down.
    /// </summary>
    Responding,

    /// <summary>
    ///  Response 1 was taken: the host writes the six command bytes.
    /// </summary>
    Command,

    /// <summary>
    ///  Response 3 or 4 was taken: the host writes the block's data and tags.
    /// </summary>
    WriteData,

    /// <summary>
    ///  A read or write is done: the host reads the status, and for a read the block.
    /// </summary>
    Result
}
